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

    // Run a real completion using the MANUAL gemma4 format (<|turn>…<turn|>).
    println!("\n=== generation test (manual gemma4 format) ===");
    let prompt = "<|turn>user\nContinue this text, writing only what comes next:\nThe weather today is<turn|>\n<|turn>model\n".to_string();
    println!("PROMPT TOKENS: {}", model.str_to_token(&prompt, AddBos::Always)?.len());
    let tokens = model.str_to_token(&prompt, AddBos::Always)?;
    let mut ctx = model.new_context(
        &backend,
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
    println!("RAW OUTPUT: {out:?}");
    Ok(())
}
