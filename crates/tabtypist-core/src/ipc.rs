use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, ChildStdout};
use tokio::sync::mpsc;
use tracing::{debug, warn};

// ── Wire types ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcMessage {
    pub id: Option<u64>,
    pub method: Option<String>,
    pub params: Option<Value>,
    pub result: Option<Value>,
    pub error: Option<RpcError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
}

impl RpcMessage {
    pub fn request(id: u64, method: impl Into<String>, params: Value) -> Self {
        Self {
            id: Some(id),
            method: Some(method.into()),
            params: Some(params),
            result: None,
            error: None,
        }
    }

    pub fn notification(method: impl Into<String>, params: Value) -> Self {
        Self {
            id: None,
            method: Some(method.into()),
            params: Some(params),
            result: None,
            error: None,
        }
    }

    pub fn ok_response(id: u64, result: Value) -> Self {
        Self {
            id: Some(id),
            method: None,
            params: None,
            result: Some(result),
            error: None,
        }
    }

    pub fn is_notification(&self) -> bool {
        self.id.is_none() && self.method.is_some()
    }
}

// ── Outbound messages Rust→Swift ─────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "method", content = "params", rename_all = "camelCase")]
pub enum CoreToSidecar {
    /// Show ghost text at the given screen position
    ShowOverlay { x: f64, y: f64, text: String, height: f64 },
    /// Hide ghost text overlay
    HideOverlay,
    /// Request the current text context (prefix, suffix, caret rect, app)
    GetContext,
}

// ── Inbound messages Swift→Rust ──────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "method", content = "params", rename_all = "camelCase")]
pub enum SidecarToCore {
    /// Text context update from the focused field
    ContextUpdate {
        prefix: String,
        suffix: String,
        caret_x: f64,
        caret_y: f64,
        caret_height: f64,
        app_bundle_id: String,
        is_secure_field: bool,
    },
    /// User pressed Tab — accept the current completion
    AcceptCompletion { completion_id: u64 },
    /// User pressed Escape — dismiss the current completion
    DismissCompletion,
    /// App responded to ping
    Pong,
}

// ── IPC transport ─────────────────────────────────────────────────────────────

pub struct IpcTransport {
    stdin: ChildStdin,
    next_id: u64,
}

impl IpcTransport {
    pub fn new(stdin: ChildStdin) -> Self {
        Self { stdin, next_id: 1 }
    }

    pub async fn send(&mut self, msg: &RpcMessage) -> Result<()> {
        let mut line = serde_json::to_string(msg)?;
        line.push('\n');
        self.stdin.write_all(line.as_bytes()).await?;
        debug!(msg = %line.trim(), "→ sidecar");
        Ok(())
    }

    pub async fn send_notification(&mut self, method: &str, params: Value) -> Result<()> {
        let msg = RpcMessage::notification(method, params);
        self.send(&msg).await
    }

    pub async fn request(&mut self, method: &str, params: Value) -> Result<u64> {
        let id = self.next_id;
        self.next_id += 1;
        let msg = RpcMessage::request(id, method, params);
        self.send(&msg).await?;
        Ok(id)
    }

    pub fn next_id(&self) -> u64 {
        self.next_id
    }
}

/// Spawn a reader task that forwards incoming lines to a channel.
pub fn spawn_reader(stdout: ChildStdout) -> mpsc::Receiver<RpcMessage> {
    let (tx, rx) = mpsc::channel(64);
    tokio::spawn(async move {
        let mut reader = BufReader::new(stdout).lines();
        while let Ok(Some(line)) = reader.next_line().await {
            debug!(msg = %line, "← sidecar");
            match serde_json::from_str::<RpcMessage>(&line) {
                Ok(msg) => {
                    if tx.send(msg).await.is_err() {
                        break;
                    }
                }
                Err(e) => warn!("malformed RPC line: {e}: {line}"),
            }
        }
    });
    rx
}
