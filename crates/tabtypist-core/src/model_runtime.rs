use anyhow::{Context, Result};
use std::path::Path;

/// A loaded model that can produce completions.
pub trait Completer: Send + Sync {
    /// Generate a completion for the given prefix.
    /// Returns up to `max_tokens` tokens, stopping at sentence boundaries.
    fn complete(&self, prefix: &str, max_tokens: u32) -> Result<String>;
}

// ── llama.cpp implementation ──────────────────────────────────────────────────

pub struct LlamaCppCompleter {
    model: llama_cpp_2::model::LlamaModel,
    context_params: llama_cpp_2::context::params::LlamaContextParams,
}

impl LlamaCppCompleter {
    pub fn load(model_path: &Path) -> Result<Self> {
        use llama_cpp_2::model::params::LlamaModelParams;

        let model_params = LlamaModelParams::default().with_n_gpu_layers(99);

        let model = llama_cpp_2::model::LlamaModel::load_from_file(
            &llama_cpp_2::llama_backend::LlamaBackend::init()?,
            model_path,
            &model_params,
        )
        .with_context(|| format!("loading model from {}", model_path.display()))?;

        let context_params = llama_cpp_2::context::params::LlamaContextParams::default()
            .with_n_ctx(std::num::NonZeroU32::new(512).unwrap())
            .with_n_batch(512);

        Ok(Self {
            model,
            context_params,
        })
    }
}

impl Completer for LlamaCppCompleter {
    fn complete(&self, prefix: &str, max_tokens: u32) -> Result<String> {
        use llama_cpp_2::context::LlamaContext;
        use llama_cpp_2::token::data_array::LlamaTokenDataArray;

        let mut ctx = self.model.new_context(
            &llama_cpp_2::llama_backend::LlamaBackend::init()?,
            self.context_params.clone(),
        )?;

        let tokens = self
            .model
            .str_to_token(prefix, llama_cpp_2::model::AddBos::Always)?;

        let mut batch = llama_cpp_2::llama_batch::LlamaBatch::new(512, 1);
        let last_idx = (tokens.len() - 1) as i32;
        for (i, &tok) in tokens.iter().enumerate() {
            batch.add(tok, i as i32, &[0], i as i32 == last_idx)?;
        }
        ctx.decode(&mut batch)?;

        let mut result = String::new();
        let mut n_cur = tokens.len() as i32;

        for _ in 0..max_tokens {
            let candidates = ctx.candidates_ith(n_cur - 1);
            let mut data = LlamaTokenDataArray::from_iter(candidates, false);
            ctx.sample_temp(&mut data, 0.1);
            ctx.sample_top_p(&mut data, 0.9, 1);
            let token = ctx.sample_token_greedy(&mut data);

            if token == self.model.token_eos() {
                break;
            }

            let piece = self.model.token_to_str(token, llama_cpp_2::model::Special::Tokenize)?;
            result.push_str(&piece);

            if ends_at_sentence_boundary(&result) {
                break;
            }

            let mut next_batch = llama_cpp_2::llama_batch::LlamaBatch::new(1, 1);
            next_batch.add(token, n_cur, &[0], true)?;
            ctx.decode(&mut next_batch)?;
            n_cur += 1;
        }

        Ok(truncate_at_sentence_boundary(result))
    }
}

// ── Sentence boundary helpers ─────────────────────────────────────────────────

fn ends_at_sentence_boundary(text: &str) -> bool {
    text.ends_with(|c| matches!(c, '.' | '!' | '?' | '\n'))
}

pub fn truncate_at_sentence_boundary(mut text: String) -> String {
    // Stop at the first sentence-ending punctuation or newline.
    if let Some(pos) = text.find(|c| matches!(c, '.' | '!' | '?' | '\n')) {
        text.truncate(pos + 1);
    }
    text.trim_end().to_string()
}

// ── Stub completer for tests ──────────────────────────────────────────────────

#[cfg(test)]
pub struct StubCompleter {
    pub response: String,
}

#[cfg(test)]
impl Completer for StubCompleter {
    fn complete(&self, _prefix: &str, _max_tokens: u32) -> Result<String> {
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
}
