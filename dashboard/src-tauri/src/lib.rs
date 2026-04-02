use axum::{extract::State, http::StatusCode, routing::{get, post}, Json, Router};
use serde::{Deserialize, Serialize};
use std::process::Command;
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, Manager};
use tower_http::cors::CorsLayer;

const DEFAULT_PORT: u16 = 9717;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notification {
    pub title: String,
    pub message: String,
    #[serde(default = "default_timestamp")]
    pub timestamp: String,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub read: bool,
    /// Client type: "terminal", "vscode", "cursor", "windsurf"
    #[serde(default)]
    pub client: String,
    /// macOS app name for activation: "iTerm2", "Terminal", "Visual Studio Code", "Cursor"
    #[serde(default)]
    pub client_app: String,
    /// Working directory of the Claude session
    #[serde(default)]
    pub client_path: String,
}

fn default_timestamp() -> String {
    chrono::Utc::now().to_rfc3339()
}

type NotificationStore = Arc<Mutex<Vec<Notification>>>;

// --- HTTP handlers (receive from dev-kit hooks) ---

async fn receive_notification(
    State((store, app)): State<(NotificationStore, AppHandle)>,
    Json(mut notif): Json<Notification>,
) -> StatusCode {
    if notif.timestamp.is_empty() {
        notif.timestamp = default_timestamp();
    }
    notif.read = false;

    let count = {
        let mut events = store.lock().unwrap();
        events.insert(0, notif.clone());
        // Keep last 200
        events.truncate(200);
        events.iter().filter(|n| !n.read).count()
    };

    // Emit to frontend
    let _ = app.emit("new-notification", &notif);
    let _ = app.emit("badge-count", count);

    // Bring window to front
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }

    StatusCode::OK
}

async fn health() -> &'static str {
    "devkit-dashboard ok"
}

// --- Tauri commands (called from frontend) ---

#[tauri::command]
fn get_notifications(store: tauri::State<'_, NotificationStore>) -> Vec<Notification> {
    store.lock().unwrap().clone()
}

#[tauri::command]
fn get_badge_count(store: tauri::State<'_, NotificationStore>) -> usize {
    store.lock().unwrap().iter().filter(|n| !n.read).count()
}

#[tauri::command]
fn mark_all_read(store: tauri::State<'_, NotificationStore>) {
    let mut events = store.lock().unwrap();
    for n in events.iter_mut() {
        n.read = true;
    }
}

#[tauri::command]
fn clear_notifications(store: tauri::State<'_, NotificationStore>) {
    store.lock().unwrap().clear();
}

#[tauri::command]
fn get_port() -> u16 {
    DEFAULT_PORT
}

/// Focus the source application that sent the notification.
/// Uses osascript on macOS to activate the app by name,
/// or opens VS Code/Cursor to the workspace path.
#[tauri::command]
fn focus_client(client: String, client_app: String, client_path: String) -> Result<(), String> {
    if client_app.is_empty() {
        return Err("No client app specified".into());
    }

    match client.as_str() {
        "vscode" | "cursor" | "windsurf" => {
            // Use `open -a <App> <path>` — works from app bundles where CLI tools
            // like `code` are not on the restricted macOS PATH.
            let app_name = match client.as_str() {
                "cursor"   => "Cursor",
                "windsurf" => "Windsurf",
                _          => "Visual Studio Code",
            };

            if !client_path.is_empty() {
                Command::new("open")
                    .args(["-a", app_name, &client_path])
                    .spawn()
                    .map_err(|e| format!("Failed to open {}: {}", app_name, e))?;
            } else {
                activate_app(&client_app)?;
            }
        }
        _ => {
            // Terminal apps: activate via osascript
            activate_app(&client_app)?;
        }
    }

    Ok(())
}

fn activate_app(app_name: &str) -> Result<(), String> {
    Command::new("osascript")
        .arg("-e")
        .arg(format!("tell application \"{}\" to activate", app_name))
        .spawn()
        .map_err(|e| format!("Failed to activate {}: {}", app_name, e))?;
    Ok(())
}

// --- App setup ---

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let store: NotificationStore = Arc::new(Mutex::new(Vec::new()));

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(store.clone())
        .setup(move |app| {
            let app_handle = app.handle().clone();
            let server_store = store.clone();

            // Start HTTP server on a dedicated thread with its own Tokio runtime
            std::thread::spawn(move || {
                let rt = tokio::runtime::Runtime::new().unwrap();
                rt.block_on(async move {
                    let state = (server_store, app_handle);
                    let router = Router::new()
                        .route("/", get(health))
                        .route("/notify", post(receive_notification))
                        .layer(CorsLayer::permissive())
                        .with_state(state);

                    let addr = format!("127.0.0.1:{}", DEFAULT_PORT);
                    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
                    eprintln!("DevKit Dashboard listening on http://{}", addr);
                    axum::serve(listener, router).await.unwrap();
                });
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_notifications,
            get_badge_count,
            mark_all_read,
            clear_notifications,
            get_port,
            focus_client,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
