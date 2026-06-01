// Diagnostic: dump a GGUF model's chat template + special tokens, and run one
// completion so we can see the exact prompt format the model expects.
//
// Usage: cargo run --example inspect_model -- /path/to/model.gguf

use llama_cpp_2::context::params::LlamaContextParams;
use llama_cpp_2::llama_backend::LlamaBackend;
use llama_cpp_2::llama_batch::LlamaBatch;
use llama_cpp_2::model::params::LlamaModelParams;
use llama_cpp_2::model::{AddBos, LlamaChatMessage, LlamaModel};
use llama_cpp_2::sampling::LlamaSampler;
use std::num::NonZeroU32;

fn probe(model: &LlamaModel, s: &str) -> String {
    match model.str_to_token(s, AddBos::Never) {
        Ok(t) => format!("{t:?}"),
        Err(e) => format!("ERR {e}"),
    }
}

fn main() -> anyhow::Result<()> {
    let path = std::env::args().nth(1).expect("usage: inspect_model <gguf>");
    let backend = LlamaBackend::init()?;
    let model = LlamaModel::load_from_file(
        &backend,
        &path,
        &LlamaModelParams::default().with_n_gpu_layers(99),
    )?;

    println!("=== chat_template ===");
    match model.chat_template(None) {
        Ok(t) => println!("{:?}", t),
        Err(e) => println!("(none: {e})"),
    }

    println!("\n=== special token probes (Never-BOS tokenization) ===");
    for s in [
        "<start_of_turn>", "<end_of_turn>", "<|im_start|>", "<|im_end|>",
        "<|turn>", "<turn|>", "<bos>", "<eos>", "<|user|>", "<|assistant|>",
    ] {
        println!("{s:>18} -> {}", probe(&model, s));
    }

    println!("\n=== apply_chat_template (model's own) ===");
    if let Ok(tmpl) = model.chat_template(None) {
        let msgs = vec![
            LlamaChatMessage::new("user".into(), "The weather today is".into()).unwrap(),
        ];
        match model.apply_chat_template(&tmpl, &msgs, true) {
            Ok(p) => println!("PROMPT:\n{p}\n--- tokens: {} ---", model.str_to_token(&p, AddBos::Always).map(|t| t.len()).unwrap_or(0)),
            Err(e) => println!("apply failed: {e}"),
        }
    }

    // Run a real completion mirroring the app's prompt: background context + the
    // user's partial sentence, in the manual gemma4 format (<|turn>…<turn|>).
    println!("\n=== generation test (background context + continuation) ===");
    let body = "Task:\n\
        - You finish the sentence the user is currently typing. Output only the words that come next after their text.\n\
        - This is autocomplete, not chat. Do NOT answer, reply, or start a conversation.\n\
        - The screen/clipboard context is BACKGROUND only — it tells you the topic so your continuation fits. NEVER answer a question found in that context; only continue the user's own sentence.\n\
        - Match the user's voice: your continuation must read as if they typed it.\n\
        \n\
        Background context (reference only — do NOT reply to any of this):\n\
        The user is typing in Telegram.\n\
        Nearby on-screen text (e.g. the conversation being replied to):\n\
        Dawit: Cursor is so baddd btw. Why does it. Is it a python project\n\
        I seen it struggles to load extensions for that\n\
        \n\
        Final instruction:\n\
        - Continue ONLY the user's text below. The next line must begin with the words that come right after it — not a reply to the background context.\n\
        Text before caret:\n\
        I think it is not working properly";
    let _ = body;
    let bg = "Background — the chat the user is replying to (do NOT answer it, use only for topic): Dawit asked \"Is it a python project\" and said Cursor struggles to load extensions.";
    let prefix = "I think it is not working properly";

    let rules = "You are an inline autocomplete inside a text field. Continue the user's text from EXACTLY where they stopped, writing only the characters that come next. If they are mid-word or mid-sentence, finish it naturally. If their sentence already looks complete, add the next clause they would most likely type (e.g. a reason or detail). Use the background ONLY to make the continuation specific to their topic — never answer, reply to, or quote the background. Preserve correct spacing: if the continuation is a new word, begin it with a space. Output only the continuation, nothing else.";
    let midword = "I think it is not workin";
    let variants: Vec<(&str, String)> = vec![
        ("complete",
            format!("<|turn>user\n{rules}\n\n{bg}\n\nThe user has typed (continue from the end):\n{prefix}<turn|>\n<|turn>model\n")),
        ("midword",
            format!("<|turn>user\n{rules}\n\n{bg}\n\nThe user has typed (continue from the end):\n{midword}<turn|>\n<|turn>model\n")),
    ];
    for (name, prompt) in &variants {
        let out = run_gen(&model, &backend, prompt)?;
        println!("[{name:>20}] -> {out:?}");
    }
    return Ok(());
}

fn run_gen(model: &LlamaModel, backend: &LlamaBackend, prompt: &str) -> anyhow::Result<String> {
    {
    let tokens = model.str_to_token(prompt, AddBos::Always)?;
    let mut ctx = model.new_context(
        backend,
        LlamaContextParams::default().with_n_ctx(Some(NonZeroU32::new(2048).unwrap())),
    )?;
    let last = tokens.len() - 1;
    let mut batch = LlamaBatch::new(tokens.len().max(64), 1);
    for (i, &t) in tokens.iter().enumerate() {
        batch.add(t, i as i32, &[0], i == last)?;
    }
    ctx.decode(&mut batch)?;
    let mut sampler = LlamaSampler::chain_simple([LlamaSampler::temp(0.2), LlamaSampler::greedy()]);
    let mut decoder = encoding_rs::UTF_8.new_decoder();
    let mut out = String::new();
    let mut pos = tokens.len() as i32;
    let mut tok = sampler.sample(&mut ctx, last as i32);
    sampler.accept(tok);
    for _ in 0..40 {
        if tok == model.token_eos() { out.push_str("[EOS]"); break; }
        let piece = model.token_to_piece(tok, &mut decoder, false, None)?;
        out.push_str(&piece);
        let mut b = LlamaBatch::new(1, 1);
        b.add(tok, pos, &[0], true)?;
        ctx.decode(&mut b)?;
        pos += 1;
        tok = sampler.sample(&mut ctx, 0);
        sampler.accept(tok);
    }
    Ok(out)
    }
}
