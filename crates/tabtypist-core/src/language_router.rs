use crate::model_runtime::Completer;
use crate::settings_store::Settings;
use std::collections::HashMap;
use std::sync::Arc;

/// Detect the script of a text snippet from the last characters typed.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Script {
    Latin,   // English and other Latin-script languages
    Ethiopic, // Amharic (Ge'ez script)
    Unknown,
}

/// Unicode ranges for Ethiopic (Ge'ez) block: U+1200–U+137F (and extended blocks).
fn is_ethiopic(c: char) -> bool {
    matches!(c as u32,
        0x1200..=0x137F   // Ethiopic
        | 0x1380..=0x139F // Ethiopic Supplement
        | 0x2D80..=0x2DDF // Ethiopic Extended
        | 0xAB00..=0xAB2F // Ethiopic Extended-A
    )
}

pub fn detect_script(text: &str) -> Script {
    // Sample the last 20 non-whitespace characters.
    let sample: String = text
        .chars()
        .rev()
        .filter(|c| !c.is_whitespace())
        .take(20)
        .collect();

    if sample.is_empty() {
        return Script::Unknown;
    }

    let ethiopic_count = sample.chars().filter(|&c| is_ethiopic(c)).count();
    let latin_count = sample
        .chars()
        .filter(|c| c.is_ascii_alphabetic())
        .count();

    if ethiopic_count > latin_count {
        Script::Ethiopic
    } else if latin_count > 0 {
        Script::Latin
    } else {
        Script::Unknown
    }
}

// ── LanguageRouter ────────────────────────────────────────────────────────────

pub struct LanguageRouter {
    /// Loaded completers keyed by language code ("en", "am").
    completers: HashMap<String, Arc<dyn Completer>>,
}

impl LanguageRouter {
    pub fn new() -> Self {
        Self {
            completers: HashMap::new(),
        }
    }

    pub fn register(&mut self, lang: impl Into<String>, completer: Arc<dyn Completer>) {
        self.completers.insert(lang.into(), completer);
    }

    /// Given the current prefix text and user settings, return the appropriate completer.
    pub fn route<'a>(&'a self, prefix: &str, settings: &Settings) -> Option<Arc<dyn Completer>> {
        let script = detect_script(prefix);

        let lang_code = match script {
            Script::Ethiopic if settings.selected_languages.contains(&"am".to_string()) => "am",
            Script::Latin | Script::Unknown => "en",
            _ => "en",
        };

        // Honour model overrides from settings (language code key).
        // The override value is a model ID; the completer is looked up by language.
        // For v1, one completer per language, so just look up by lang_code.
        self.completers.get(lang_code).cloned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detect_latin() {
        assert_eq!(detect_script("Hello world"), Script::Latin);
    }

    #[test]
    fn detect_ethiopic() {
        // Amharic "Hello" (selam): ሰላም
        assert_eq!(detect_script("ሰላም ዓለም"), Script::Ethiopic);
    }

    #[test]
    fn detect_unknown_for_empty() {
        assert_eq!(detect_script(""), Script::Unknown);
    }

    #[test]
    fn detect_mixed_uses_majority() {
        // More Latin than Ethiopic
        assert_eq!(detect_script("Hello world ሰ"), Script::Latin);
        // More Ethiopic than Latin
        assert_eq!(detect_script("ሰሰሰሰ a"), Script::Ethiopic);
    }
}
