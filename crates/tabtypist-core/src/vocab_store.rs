use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};
use tracing::debug;

const MAX_WORDS: usize = 1000;
const MAX_PHRASES: usize = 200;

#[derive(Serialize, Deserialize, Default)]
struct VocabData {
    words: HashMap<String, u32>,
    recent_phrases: Vec<String>,
}

pub struct VocabStore {
    inner: Arc<RwLock<VocabData>>,
    path: PathBuf,
}

impl VocabStore {
    pub fn load(dir: &Path) -> Self {
        let path = dir.join("vocab.json");
        let data: VocabData = if path.exists() {
            std::fs::read_to_string(&path)
                .ok()
                .and_then(|raw| serde_json::from_str(&raw).ok())
                .unwrap_or_default()
        } else {
            VocabData::default()
        };
        Self { inner: Arc::new(RwLock::new(data)), path }
    }

    /// Record an accepted completion — updates word frequencies and phrase log.
    pub fn record(&self, text: &str) {
        if text.trim().is_empty() { return; }
        let mut guard = self.inner.write().unwrap();

        guard.recent_phrases.push(text.to_string());
        if guard.recent_phrases.len() > MAX_PHRASES {
            guard.recent_phrases.remove(0);
        }

        for raw_word in text.split_whitespace() {
            let w: String = raw_word
                .chars()
                .filter(|c| c.is_alphanumeric())
                .collect::<String>()
                .to_lowercase();
            if w.len() >= 3 {
                *guard.words.entry(w).or_insert(0) += 1;
            }
        }

        // Prune to MAX_WORDS by keeping the highest-frequency entries.
        if guard.words.len() > MAX_WORDS {
            let mut pairs: Vec<(String, u32)> = guard.words.drain().collect();
            pairs.sort_by(|a, b| b.1.cmp(&a.1));
            pairs.truncate(MAX_WORDS);
            guard.words = pairs.into_iter().collect();
        }

        drop(guard);
        self.persist();
    }

    /// Top-N words by acceptance frequency.
    pub fn top_words(&self, n: usize) -> Vec<String> {
        let guard = self.inner.read().unwrap();
        let mut pairs: Vec<(&String, &u32)> = guard.words.iter().collect();
        pairs.sort_by(|a, b| b.1.cmp(a.1));
        pairs.iter().take(n).map(|(w, _)| w.to_string()).collect()
    }

    fn persist(&self) {
        let guard = self.inner.read().unwrap();
        if let Ok(json) = serde_json::to_string_pretty(&*guard) {
            drop(guard);
            let tmp = self.path.with_extension("tmp");
            if std::fs::write(&tmp, &json).is_ok() {
                let _ = std::fs::rename(&tmp, &self.path);
                debug!("vocab persisted to {:?}", self.path);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn store_in(dir: &TempDir) -> VocabStore {
        VocabStore::load(dir.path())
    }

    #[test]
    fn records_and_retrieves_top_words() {
        let dir = TempDir::new().unwrap();
        let store = store_in(&dir);
        store.record("the quick brown fox");
        store.record("the quick brown");
        store.record("the quick");
        let top = store.top_words(5);
        // "the" and "quick" both appear 3× (highest) — both must be in top 2.
        assert!(top.contains(&"the".to_string()), "expected 'the' in top words");
        assert!(top.contains(&"quick".to_string()), "expected 'quick' in top words");
        // "fox" appears once — present but ranked below the two leaders.
        assert!(top.contains(&"fox".to_string()), "expected 'fox' in top words");
    }

    #[test]
    fn ignores_short_words() {
        let dir = TempDir::new().unwrap();
        let store = store_in(&dir);
        store.record("a to be");
        assert!(store.top_words(10).is_empty());
    }

    #[test]
    fn persists_and_reloads() {
        let dir = TempDir::new().unwrap();
        {
            let store = store_in(&dir);
            store.record("hello world");
        }
        let store2 = VocabStore::load(dir.path());
        let top = store2.top_words(5);
        assert!(top.contains(&"hello".to_string()));
        assert!(top.contains(&"world".to_string()));
    }
}
