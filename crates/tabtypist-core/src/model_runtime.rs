use anyhow::{Context, Result};
use encoding_rs;
use llama_cpp_2::token::LlamaToken;
use std::num::NonZeroU32;
use std::path::{Path, PathBuf};
use std::sync::mpsc;

/// A loaded model that can produce completions.
pub trait Completer: Send + Sync {
    fn complete(&self, prefix: &str, suffix: &str, max_tokens: u32) -> Result<String>;
}

// ── Inference thread ──────────────────────────────────────────────────────────
//
// LlamaContext<'model> borrows from LlamaModel, so they cannot both live in a
// struct field without unsafe self-referential tricks.  Owning all three
// (backend, model, context) inside a dedicated thread's local scope avoids the
// lifetime problem entirely while also keeping a persistent KV cache that
// survives across completion calls.

struct InferRequest {
    prefix: String,
    suffix: String,
    max_tokens: u32,
    reply_tx: mpsc::SyncSender<Result<String>>,
}

pub struct LlamaCppCompleter {
    request_tx: mpsc::SyncSender<InferRequest>,
}

impl LlamaCppCompleter {
    pub fn load(model_path: &Path) -> Result<Self> {
        let (request_tx, request_rx) = mpsc::sync_channel::<InferRequest>(1);
        let model_path = model_path.to_owned();
        std::thread::spawn(move || {
            if let Err(e) = inference_thread(request_rx, model_path) {
                tracing::error!("inference thread exited: {e}");
            }
        });
        Ok(Self { request_tx })
    }
}

impl Completer for LlamaCppCompleter {
    fn complete(&self, prefix: &str, suffix: &str, max_tokens: u32) -> Result<String> {
        let (reply_tx, reply_rx) = mpsc::sync_channel(1);
        self.request_tx
            .send(InferRequest {
                prefix: prefix.to_owned(),
                suffix: suffix.to_owned(),
                max_tokens,
                reply_tx,
            })
            .context("inference thread disconnected")?;
        reply_rx.recv().context("inference thread dropped reply")?
    }
}

const N_CTX: u32 = 2048;

fn inference_thread(rx: mpsc::Receiver<InferRequest>, model_path: PathBuf) -> Result<()> {
    use llama_cpp_2::context::params::LlamaContextParams;
    use llama_cpp_2::llama_backend::LlamaBackend;
    use llama_cpp_2::model::params::LlamaModelParams;

    let backend = LlamaBackend::init()?;
    let model_params = LlamaModelParams::default().with_n_gpu_layers(99);
    let model = llama_cpp_2::model::LlamaModel::load_from_file(&backend, &model_path, &model_params)
        .with_context(|| format!("loading model from {}", model_path.display()))?;

    let ctx_params = LlamaContextParams::default()
        .with_n_ctx(Some(NonZeroU32::new(N_CTX).unwrap()))
        .with_n_batch(512);
    let mut ctx = model.new_context(&backend, ctx_params)?;

    // Tokens currently committed to the KV cache (prefix-only, no FIM framing).
    let mut kv_tokens: Vec<LlamaToken> = Vec::new();

    while let Ok(req) = rx.recv() {
        let InferRequest {
            prefix,
            suffix,
            max_tokens,
            reply_tx,
        } = req;
        let result = do_complete(&model, &mut ctx, &mut kv_tokens, &prefix, &suffix, max_tokens);
        let _ = reply_tx.send(result);
    }
    Ok(())
}

// ── Core completion ───────────────────────────────────────────────────────────

fn do_complete(
    model: &llama_cpp_2::model::LlamaModel,
    ctx: &mut llama_cpp_2::context::LlamaContext,
    kv_tokens: &mut Vec<LlamaToken>,
    prefix: &str,
    suffix: &str,
    max_tokens: u32,
) -> Result<String> {
    use llama_cpp_2::llama_batch::LlamaBatch;
    use llama_cpp_2::model::AddBos;
    use llama_cpp_2::sampling::LlamaSampler;

    let new_tokens = model
        .str_to_token(prefix, AddBos::Always)
        .context("tokenizing prefix")?;

    // Fast path: the new prefix is a strict forward extension of the cached
    // prefix.  Decode only the delta tokens; the existing KV entries are reused.
    let can_extend = suffix.is_empty()
        && new_tokens.len() > kv_tokens.len()
        && new_tokens[..kv_tokens.len()] == kv_tokens[..];

    let (mut pos, sample_idx): (i32, i32) = if can_extend {
        let delta = &new_tokens[kv_tokens.len()..];
        let start = kv_tokens.len() as i32;
        let mut batch = LlamaBatch::new(delta.len().max(1), 1);
        for (i, &tok) in delta.iter().enumerate() {
            batch.add(tok, start + i as i32, &[0], i == delta.len() - 1)?;
        }
        ctx.decode(&mut batch).context("delta prefill")?;
        *kv_tokens = new_tokens.clone();
        (new_tokens.len() as i32, delta.len() as i32 - 1)
    } else {
        // Slow path: diverged prefix (deletion / cursor jump / FIM mode / first call).
        ctx.clear_kv_cache();
        kv_tokens.clear();

        let token_stream =
            build_token_stream(model, &new_tokens, suffix, max_tokens as usize)?;
        if token_stream.is_empty() {
            return Ok(String::new());
        }

        let last_idx = token_stream.len() - 1;
        let mut batch = LlamaBatch::new(token_stream.len().max(512), 1);
        for (i, &tok) in token_stream.iter().enumerate() {
            batch.add(tok, i as i32, &[0], i == last_idx)?;
        }
        ctx.decode(&mut batch).context("full prefill")?;

        // FIM framing tokens pollute the sequence, so don't cache them.
        if suffix.is_empty() {
            *kv_tokens = token_stream.clone();
        }

        (token_stream.len() as i32, last_idx as i32)
    };

    let fim_pad_id = resolve_token(model, "<|fim_pad|>");
    let endoftext_id = resolve_token(model, "<|endoftext|>");

    let mut sampler = LlamaSampler::chain_simple([
        LlamaSampler::penalties(64, 1.1, 0.0, 0.0),
        LlamaSampler::temp(0.1),
        LlamaSampler::min_p(0.05, 1),
        LlamaSampler::greedy(),
    ]);

    let mut decoder = encoding_rs::UTF_8.new_decoder();
    let mut result = String::new();

    let mut token = sampler.sample(ctx, sample_idx);
    sampler.accept(token);

    for _ in 0..max_tokens {
        if token == model.token_eos() {
            break;
        }
        if fim_pad_id.map_or(false, |id| token == id) {
            break;
        }
        if endoftext_id.map_or(false, |id| token == id) {
            break;
        }

        let piece = model.token_to_piece(token, &mut decoder, false, None)?;
        if !piece.is_empty() {
            result.push_str(&piece);
            if ends_at_sentence_boundary(&result) {
                break;
            }
        }

        let mut next = LlamaBatch::new(1, 1);
        next.add(token, pos, &[0], true)?;
        ctx.decode(&mut next).context("autoregressive decode")?;
        pos += 1;

        token = sampler.sample(ctx, 0);
        sampler.accept(token);
    }

    // Trim autoregressive tokens out of the KV cache.  The next call's fast-path
    // check compares against kv_tokens (prefix only), so the cache must match.
    let _ = ctx.clear_kv_cache_seq(Some(0), Some(kv_tokens.len() as u32), None);

    let normalized = normalize_completion(result, prefix);
    tracing::debug!(
        "completion kv_hit={} cached={} normalized_len={}",
        can_extend,
        kv_tokens.len(),
        normalized.len()
    );
    Ok(truncate_at_sentence_boundary(normalized))
}

// ── Token stream construction ─────────────────────────────────────────────────

fn build_token_stream(
    model: &llama_cpp_2::model::LlamaModel,
    prefix_tokens: &[LlamaToken],
    suffix: &str,
    max_tokens: usize,
) -> Result<Vec<LlamaToken>> {
    use llama_cpp_2::model::AddBos;

    if suffix.is_empty() {
        let mut tokens = prefix_tokens.to_vec();
        let max_prefix = N_CTX as usize - max_tokens - 4;
        if tokens.len() > max_prefix {
            let drop = tokens.len() - max_prefix;
            tokens.drain(..drop);
        }
        return Ok(tokens);
    }

    // Fill-in-the-Middle: <fim_prefix> prefix <fim_suffix> suffix <fim_middle>
    let fim_prefix_id = resolve_token(model, "<|fim_prefix|>");
    let fim_suffix_id = resolve_token(model, "<|fim_suffix|>");
    let fim_middle_id = resolve_token(model, "<|fim_middle|>");

    if let (Some(fp), Some(fs), Some(fm)) = (fim_prefix_id, fim_suffix_id, fim_middle_id) {
        let mut prefix_tokens = prefix_tokens.to_vec();
        let mut suffix_tokens = model
            .str_to_token(suffix, AddBos::Never)
            .context("tokenizing suffix (FIM)")?;

        const SUFFIX_CAP: usize = 256;
        if suffix_tokens.len() > SUFFIX_CAP {
            suffix_tokens.truncate(SUFFIX_CAP);
        }

        let prefix_budget =
            N_CTX as usize - max_tokens - 3 - suffix_tokens.len() - 4;
        if prefix_tokens.len() > prefix_budget {
            let drop = prefix_tokens.len() - prefix_budget;
            prefix_tokens.drain(..drop);
        }

        let mut tokens =
            Vec::with_capacity(1 + prefix_tokens.len() + 1 + suffix_tokens.len() + 1);
        tokens.push(fp);
        tokens.extend_from_slice(&prefix_tokens);
        tokens.push(fs);
        tokens.extend_from_slice(&suffix_tokens);
        tokens.push(fm);
        Ok(tokens)
    } else {
        tracing::warn!("FIM tokens not found in vocab; falling back to prefix-only");
        let mut tokens = prefix_tokens.to_vec();
        let max_prefix = N_CTX as usize - max_tokens - 4;
        if tokens.len() > max_prefix {
            let drop = tokens.len() - max_prefix;
            tokens.drain(..drop);
        }
        Ok(tokens)
    }
}

fn resolve_token(
    model: &llama_cpp_2::model::LlamaModel,
    s: &str,
) -> Option<LlamaToken> {
    use llama_cpp_2::model::AddBos;
    model
        .str_to_token(s, AddBos::Never)
        .ok()
        .and_then(|t| t.into_iter().next())
}

// ── Sentence-boundary helpers ─────────────────────────────────────────────────

fn ends_at_sentence_boundary(text: &str) -> bool {
    text.ends_with(|c| matches!(c, '.' | '!' | '?' | '\n'))
}

pub fn truncate_at_sentence_boundary(mut text: String) -> String {
    if let Some(pos) = text.find(|c| matches!(c, '.' | '!' | '?' | '\n')) {
        text.truncate(pos + 1);
    }
    text.trim_end().to_string()
}

// ── Completion normaliser ─────────────────────────────────────────────────────

/// Cleans raw model output before it is surfaced to the user.
///
/// Passes in order:
/// 1. Strip chat-control tokens and `<think>` blocks (including unclosed).
/// 2. Collapse `\r`.
/// 3. Echo suppression — strip the longest word-suffix of `prefix` that
///    matches the start of the completion.  If that suffix spans the entire
///    last sentence fragment of the prefix, the completion is suppressed
///    entirely (returns `""`), because the model restarted from the beginning
///    of the user's thought instead of continuing after it.
/// 4. Leading-whitespace normalisation — if `prefix` ends with whitespace,
///    strip any leading whitespace from the result to prevent double-spacing.
pub fn normalize_completion(raw: String, prefix: &str) -> String {
    let text = strip_think_blocks(&raw);
    let mut text = text
        .replace("<|im_start|>assistant", "")
        .replace("<|im_start|>", "")
        .replace("<|im_end|>", "");

    text = text.replace('\r', "");
    text = suppress_echo(text, prefix);

    if prefix.ends_with(|c: char| c.is_whitespace()) {
        text = text.trim_start().to_string();
    }

    text
}

fn strip_think_blocks(text: &str) -> String {
    let mut result = text.to_string();
    loop {
        match result.find("<think>") {
            None => break,
            Some(start) => match result[start..].find("</think>") {
                Some(rel_end) => {
                    result.replace_range(start..start + rel_end + "</think>".len(), "");
                }
                None => {
                    result.truncate(start);
                    break;
                }
            },
        }
    }
    result
}

/// Strip the longest word-level suffix of `prefix` that appears at the start
/// of `completion`.  If the match covers the entire last sentence fragment of
/// the prefix (up to 15 words), the completion is fully suppressed.
fn suppress_echo(completion: String, prefix: &str) -> String {
    let fragment = prefix
        .rsplit(|c: char| matches!(c, '\n' | '.' | '!' | '?'))
        .next()
        .unwrap_or(prefix);

    let all_fragment_words: Vec<&str> = fragment.split_whitespace().collect();
    if all_fragment_words.is_empty() {
        return completion;
    }
    let cap = all_fragment_words.len().min(15);
    let fragment_words = &all_fragment_words[all_fragment_words.len() - cap..];

    // Build (byte_start, byte_end) spans for each word in the completion.
    let mut comp_spans: Vec<(usize, usize)> = Vec::new();
    let mut word_start: Option<usize> = None;
    for (i, c) in completion.char_indices() {
        if c.is_whitespace() {
            if let Some(s) = word_start.take() {
                comp_spans.push((s, i));
            }
        } else if word_start.is_none() {
            word_start = Some(i);
        }
    }
    if let Some(s) = word_start {
        comp_spans.push((s, completion.len()));
    }

    if comp_spans.is_empty() {
        return completion;
    }

    // Try the longest suffix first (greedy).
    for n in (1..=fragment_words.len()).rev() {
        if comp_spans.len() < n {
            continue;
        }
        let suffix = &fragment_words[fragment_words.len() - n..];
        let all_match = suffix
            .iter()
            .zip(comp_spans[..n].iter())
            .all(|(fw, &(s, e))| fw.eq_ignore_ascii_case(&completion[s..e]));

        if all_match {
            if n == fragment_words.len() {
                return String::new();
            }
            let (_, end) = comp_spans[n - 1];
            return completion[end..].to_string();
        }
    }

    completion
}

// ── Stub completer for tests ──────────────────────────────────────────────────

#[cfg(test)]
pub struct StubCompleter {
    pub response: String,
}

#[cfg(test)]
impl Completer for StubCompleter {
    fn complete(&self, _prefix: &str, _suffix: &str, _max_tokens: u32) -> Result<String> {
        Ok(self.response.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncate_at_period() {
        let s = "Hello world. And more text here.".to_string();
        assert_eq!(truncate_at_sentence_boundary(s), "Hello world.");
    }

    #[test]
    fn truncate_at_newline() {
        let s = "First line\nSecond line".to_string();
        assert_eq!(truncate_at_sentence_boundary(s), "First line");
    }

    #[test]
    fn truncate_no_boundary() {
        let s = "no sentence end here".to_string();
        assert_eq!(truncate_at_sentence_boundary(s), "no sentence end here");
    }

    // ── normalize_completion ──────────────────────────────────────────────────

    #[test]
    fn strips_im_end_token() {
        let out = normalize_completion("great idea<|im_end|>".into(), "that is a ");
        assert_eq!(out, "great idea");
    }

    #[test]
    fn strips_im_start_tokens() {
        let out = normalize_completion("<|im_start|>assistant hello".into(), "say");
        assert_eq!(out, " hello");
    }

    #[test]
    fn strips_complete_think_block() {
        let out = normalize_completion("<think>reasoning here</think>actual answer".into(), "q: ");
        assert_eq!(out, "actual answer");
    }

    #[test]
    fn strips_unclosed_think_tag() {
        let out = normalize_completion("<think>started but never ended".into(), "q: ");
        assert_eq!(out, "");
    }

    #[test]
    fn collapses_carriage_return() {
        let out = normalize_completion("line one\r\nline two".into(), "start ");
        assert_eq!(out, "line one\nline two");
    }

    #[test]
    fn echo_suppression_partial() {
        // Completion starts with the last word of prefix — strip that word.
        let out = normalize_completion("world is great".into(), "hello world");
        assert_eq!(out, " is great");
    }

    #[test]
    fn echo_suppression_full_fragment() {
        // Completion starts with the ENTIRE last fragment of prefix — suppress.
        let out = normalize_completion("I like to eat".into(), "I like");
        assert_eq!(out, "");
    }

    #[test]
    fn echo_suppression_case_insensitive() {
        let out = normalize_completion("World is great".into(), "hello world");
        assert_eq!(out, " is great");
    }

    #[test]
    fn echo_suppression_no_match() {
        let out = normalize_completion("something new".into(), "hello world");
        assert_eq!(out, "something new");
    }

    #[test]
    fn leading_whitespace_stripped_when_prefix_ends_in_space() {
        let out = normalize_completion(" great idea".into(), "that is ");
        assert_eq!(out, "great idea");
    }

    #[test]
    fn leading_whitespace_preserved_when_prefix_ends_in_word_char() {
        let out = normalize_completion(" great".into(), "hello");
        assert_eq!(out, " great");
    }
}
