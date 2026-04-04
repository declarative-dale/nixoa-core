use std::collections::{BTreeSet, HashMap};
use std::env;
use std::fs;
use std::io::{self, Stdout};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context, Result};
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Alignment, Constraint, Direction, Layout, Rect};
use ratatui::prelude::{Color, Line, Modifier, Style};
use ratatui::symbols::border;
use ratatui::text::Text;
use ratatui::widgets::{
    Block, BorderType, Borders, Clear, List, ListItem, ListState, Paragraph, Wrap,
};
use ratatui::{Frame, Terminal};
use serde::Deserialize;
use serde_json::Value;

type Backend = CrosstermBackend<Stdout>;
type AppTerminal = Terminal<Backend>;

const APP_TITLE: &str = "NiXOA XS Console";
const UPDATE_TIMEOUT_SECS: u64 = 120;

#[derive(Clone, Debug)]
struct ActionItem {
    shortcut: char,
    title: &'static str,
    detail: &'static str,
}

#[derive(Clone, Debug)]
struct UpdateItem {
    shortcut: char,
    title: &'static str,
    detail: &'static str,
    backend: &'static str,
}

const ACTIONS: [ActionItem; 11] = [
    ActionItem {
        shortcut: '1',
        title: "Edit hostname",
        detail: "Write a new hostname into config/menu.nix and commit that override immediately.",
    },
    ActionItem {
        shortcut: '2',
        title: "Edit username",
        detail: "Write a new primary username into config/menu.nix and commit that override immediately.",
    },
    ActionItem {
        shortcut: '3',
        title: "Manage SSH keys",
        detail: "Review, replace, add, or remove the authorized SSH public keys managed by the console.",
    },
    ActionItem {
        shortcut: '4',
        title: "Toggle extras",
        detail: "Enable or disable the extras feature set and commit the resulting menu override.",
    },
    ActionItem {
        shortcut: '5',
        title: "Add system package",
        detail: "Append a nixpkgs attribute path to extraSystemPackages in config/menu.nix.",
    },
    ActionItem {
        shortcut: '6',
        title: "Add user package",
        detail: "Append a nixpkgs attribute path to extraUserPackages in config/menu.nix.",
    },
    ActionItem {
        shortcut: '7',
        title: "Add service",
        detail: "Enable a service by dotted NixOS option path in config/menu.nix.",
    },
    ActionItem {
        shortcut: '8',
        title: "Updates",
        detail: "Open the update menu for nixpkgs, Home Manager, Xen Orchestra, or a full flake update.",
    },
    ActionItem {
        shortcut: '9',
        title: "Open shell",
        detail: "Leave the TUI and exec the configured login shell with TUI bypass enabled.",
    },
    ActionItem {
        shortcut: '0',
        title: "Rollback system",
        detail: "Run nixos-rebuild switch --rollback interactively and record the rollback in console state.",
    },
    ActionItem {
        shortcut: 'g',
        title: "Collect garbage",
        detail: "Run nix-collect-garbage -d interactively for a full manual store cleanup.",
    },
];

const UPDATE_ACTIONS: [UpdateItem; 4] = [
    UpdateItem {
        shortcut: '1',
        title: "Update nixpkgs",
        detail: "Refresh only the nixpkgs input lock and then choose whether to rebuild now or on reboot.",
        backend: "update-nixpkgs",
    },
    UpdateItem {
        shortcut: '2',
        title: "Update Home Manager",
        detail: "Refresh only the home-manager input lock and then choose whether to rebuild now or on reboot.",
        backend: "update-home-manager",
    },
    UpdateItem {
        shortcut: '3',
        title: "Update XOA",
        detail: "Check the latest xen-orchestra-ce tag, refresh that input lock, and then choose whether to rebuild now or on reboot.",
        backend: "update-xoa",
    },
    UpdateItem {
        shortcut: '4',
        title: "Update all",
        detail: "Run a full nix flake update across every direct input and then choose whether to rebuild now or on reboot.",
        backend: "update-all",
    },
];

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Snapshot {
    hostname: String,
    username: String,
    timezone: String,
    extras: bool,
    ssh_keys: Vec<String>,
    system_packages: Vec<String>,
    user_packages: Vec<String>,
    services: Vec<String>,
    dirty_count: u32,
    head: String,
    branch: String,
    upstream: Option<String>,
    ahead: u32,
    behind: u32,
    memory_total_bytes: u64,
    memory_used_bytes: u64,
    memory_used_percent: u32,
    storage_total_bytes: u64,
    storage_used_bytes: u64,
    storage_used_percent: u32,
    primary_ip: Option<String>,
    rebuild_queued: bool,
    rebuild_needed: bool,
    last_apply: Option<ApplyState>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ApplyState {
    result: String,
    action: String,
    hostname: String,
    head: String,
    first_install: bool,
    exit_code: i32,
    timestamp: String,
}

#[derive(Debug, Deserialize)]
struct FlakeLock {
    nodes: HashMap<String, LockNode>,
}

#[derive(Debug, Deserialize)]
struct LockNode {
    locked: Option<Value>,
}

#[derive(Debug, Clone)]
enum UpdateStatus {
    Idle,
    Checking,
    UpToDate,
    Available(usize),
    Error(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Screen {
    Main,
    Keys,
    Updates,
}

#[derive(Debug, Clone, Copy)]
enum InputAction {
    SetHostname,
    SetUsername,
    SetPrimaryKey,
    AddKey,
    AddSystemPackage,
    AddUserPackage,
    AddService,
}

#[derive(Debug, Clone)]
struct InputModal {
    title: String,
    help: String,
    action: InputAction,
    value: String,
}

#[derive(Debug)]
struct App {
    repo_root: PathBuf,
    snapshot: Snapshot,
    update_status: UpdateStatus,
    update_rx: Option<Receiver<UpdateStatus>>,
    selected_action: usize,
    selected_update: usize,
    selected_key: usize,
    screen: Screen,
    modal: Option<InputModal>,
    logs: Vec<String>,
    should_quit: bool,
    should_open_shell: bool,
    tick: usize,
}

impl App {
    fn new(repo_root: PathBuf, snapshot: Snapshot) -> Self {
        let mut app = Self {
            repo_root,
            snapshot,
            update_status: UpdateStatus::Idle,
            update_rx: None,
            selected_action: 0,
            selected_update: 0,
            selected_key: 0,
            screen: Screen::Main,
            modal: None,
            logs: vec![
                "NiXOA console ready.".to_string(),
                "Press r to refresh status or u to recheck flake updates.".to_string(),
            ],
            should_quit: false,
            should_open_shell: false,
            tick: 0,
        };
        app.clamp_key_selection();
        app
    }

    fn start_update_check(&mut self) {
        if matches!(self.update_status, UpdateStatus::Checking) {
            return;
        }

        self.update_status = UpdateStatus::Checking;
        let repo_root = self.repo_root.clone();
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let status = check_flake_updates(&repo_root);
            let _ = tx.send(status);
        });
        self.update_rx = Some(rx);
    }

    fn poll_background(&mut self) {
        if let Some(rx) = &self.update_rx {
            if let Ok(status) = rx.try_recv() {
                match &status {
                    UpdateStatus::UpToDate => {
                        self.push_log("Flake input check: inputs are up to date.");
                    }
                    UpdateStatus::Available(count) => {
                        self.push_log(format!(
                            "Flake input check: {count} input lock entries can be updated."
                        ));
                    }
                    UpdateStatus::Error(message) => {
                        self.push_log(format!("Flake input check failed: {message}"));
                    }
                    UpdateStatus::Idle | UpdateStatus::Checking => {}
                }
                self.update_status = status;
                self.update_rx = None;
            }
        }
    }

    fn refresh_snapshot(&mut self) -> Result<()> {
        self.snapshot = load_snapshot(&self.repo_root)?;
        self.clamp_key_selection();
        Ok(())
    }

    fn clamp_key_selection(&mut self) {
        if self.snapshot.ssh_keys.is_empty() {
            self.selected_key = 0;
        } else if self.selected_key >= self.snapshot.ssh_keys.len() {
            self.selected_key = self.snapshot.ssh_keys.len() - 1;
        }
    }

    fn push_log(&mut self, message: impl Into<String>) {
        self.logs.push(message.into());
        if self.logs.len() > 120 {
            let drain_count = self.logs.len() - 120;
            self.logs.drain(0..drain_count);
        }
    }

    fn selected_item(&self) -> &'static ActionItem {
        &ACTIONS[self.selected_action]
    }

    fn selected_update_item(&self) -> &'static UpdateItem {
        &UPDATE_ACTIONS[self.selected_update]
    }

    fn alerts(&self) -> Vec<String> {
        let mut alerts = Vec::new();

        if self.snapshot.dirty_count > 0 {
            alerts.push(format!(
                "{} tracked repo changes are still uncommitted.",
                self.snapshot.dirty_count
            ));
        }

        if self.snapshot.rebuild_needed {
            alerts
                .push("Current repository state has not been switched onto the host.".to_string());
        }

        if self.snapshot.rebuild_queued {
            alerts.push("A rebuild has been queued for the next boot.".to_string());
        }

        if self.snapshot.behind > 0 {
            alerts.push(format!(
                "Local branch is behind {} by {} commits.",
                self.snapshot
                    .upstream
                    .clone()
                    .unwrap_or_else(|| "its upstream".to_string()),
                self.snapshot.behind
            ));
        }

        if self.snapshot.ahead > 0 {
            alerts.push(format!(
                "Local branch is ahead of upstream by {} commits.",
                self.snapshot.ahead
            ));
        }

        if self.snapshot.memory_used_percent >= 90 {
            alerts.push(format!(
                "RAM usage is high: {}.",
                format_usage(
                    self.snapshot.memory_used_bytes,
                    self.snapshot.memory_total_bytes,
                    self.snapshot.memory_used_percent
                )
            ));
        }

        if self.snapshot.storage_used_percent >= 90 {
            alerts.push(format!(
                "Root storage usage is high: {}.",
                format_usage(
                    self.snapshot.storage_used_bytes,
                    self.snapshot.storage_total_bytes,
                    self.snapshot.storage_used_percent
                )
            ));
        }

        if self.snapshot.primary_ip.is_none() {
            alerts.push("No primary IPv4 address was detected.".to_string());
        }

        match &self.update_status {
            UpdateStatus::Available(count) => {
                alerts.push(format!("{count} flake input lock entries can be updated."));
            }
            UpdateStatus::Error(message) => {
                alerts.push(format!("Flake input check failed: {message}"));
            }
            UpdateStatus::Idle | UpdateStatus::Checking | UpdateStatus::UpToDate => {}
        }

        if let Some(last_apply) = &self.snapshot.last_apply {
            if last_apply.result != "success" {
                alerts.push(format!(
                    "Last {} failed at {} with exit code {}.",
                    last_apply.action, last_apply.timestamp, last_apply.exit_code
                ));
            }
        } else {
            alerts.push("No successful host switch has been recorded yet.".to_string());
        }

        if alerts.is_empty() {
            alerts.push("No outstanding alerts.".to_string());
        }

        alerts
    }
}

fn main() -> Result<()> {
    let repo_root = discover_repo_root()?;
    let snapshot = load_snapshot(&repo_root)?;
    let mut app = App::new(repo_root, snapshot);
    app.start_update_check();

    let mut terminal = init_terminal()?;
    let run_result = run_app(&mut terminal, &mut app);
    restore_terminal(&mut terminal)?;

    if app.should_open_shell {
        open_shell();
    }

    run_result
}

fn discover_repo_root() -> Result<PathBuf> {
    if let Some(root) = env::var_os("NIXOA_SYSTEM_ROOT") {
        return Ok(PathBuf::from(root));
    }

    if let Ok(output) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if output.status.success() {
            let value = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !value.is_empty() {
                return Ok(PathBuf::from(value));
            }
        }
    }

    if let Some(home) = env::var_os("HOME") {
        let candidate = PathBuf::from(home).join("system");
        if candidate.is_dir() {
            return Ok(candidate);
        }
    }

    env::current_dir().context("failed to determine current directory for NIXOA_SYSTEM_ROOT")
}

fn init_terminal() -> Result<AppTerminal> {
    enable_raw_mode().context("failed to enable raw mode")?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen).context("failed to enter alternate screen")?;
    let backend = CrosstermBackend::new(stdout);
    Terminal::new(backend).context("failed to initialize terminal")
}

fn restore_terminal(terminal: &mut AppTerminal) -> Result<()> {
    disable_raw_mode().context("failed to disable raw mode")?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)
        .context("failed to leave alternate screen")?;
    terminal.show_cursor().context("failed to show cursor")
}

fn suspend_terminal(terminal: &mut AppTerminal) -> Result<()> {
    disable_raw_mode().context("failed to disable raw mode")?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)
        .context("failed to leave alternate screen")?;
    terminal.show_cursor().context("failed to show cursor")
}

fn resume_terminal(terminal: &mut AppTerminal) -> Result<()> {
    enable_raw_mode().context("failed to re-enable raw mode")?;
    execute!(terminal.backend_mut(), EnterAlternateScreen)
        .context("failed to re-enter alternate screen")?;
    terminal.clear().context("failed to clear terminal")
}

fn load_snapshot(repo_root: &Path) -> Result<Snapshot> {
    let output = Command::new(repo_root.join("scripts/tui/state.sh"))
        .arg("--json")
        .env("NIXOA_SYSTEM_ROOT", repo_root)
        .output()
        .with_context(|| {
            format!(
                "failed to run {}",
                repo_root.join("scripts/tui/state.sh").display()
            )
        })?;

    if !output.status.success() {
        return Err(anyhow!(
            "state backend failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    serde_json::from_slice(&output.stdout).context("failed to parse state backend JSON")
}

fn run_app(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    loop {
        app.poll_background();
        app.tick = app.tick.wrapping_add(1);

        terminal.draw(|frame| render(frame, app))?;

        if app.should_quit || app.should_open_shell {
            return Ok(());
        }

        if event::poll(Duration::from_millis(200)).context("failed to poll terminal events")? {
            if let Event::Key(key) = event::read().context("failed to read terminal event")? {
                if key.kind == KeyEventKind::Press {
                    handle_key(terminal, app, key)?;
                }
            }
        }
    }
}

fn handle_key(terminal: &mut AppTerminal, app: &mut App, key: KeyEvent) -> Result<()> {
    if app.modal.is_some() {
        return handle_modal_key(terminal, app, key);
    }

    match app.screen {
        Screen::Main => handle_main_key(terminal, app, key),
        Screen::Keys => handle_keys_key(terminal, app, key),
        Screen::Updates => handle_updates_key(terminal, app, key),
    }
}

fn handle_main_key(terminal: &mut AppTerminal, app: &mut App, key: KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Up | KeyCode::Char('k') => {
            if app.selected_action == 0 {
                app.selected_action = ACTIONS.len() - 1;
            } else {
                app.selected_action -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            app.selected_action = (app.selected_action + 1) % ACTIONS.len();
        }
        KeyCode::Enter => activate_selected_action(terminal, app)?,
        KeyCode::Char('r') => {
            app.refresh_snapshot()?;
            app.start_update_check();
            app.push_log("Refreshed repository snapshot.");
        }
        KeyCode::Char('u') => {
            app.start_update_check();
            app.push_log("Started a new flake input update check.");
        }
        KeyCode::Char('q') => {
            app.should_open_shell = true;
        }
        KeyCode::Char(ch) if action_index_for_shortcut(ch).is_some() => {
            app.selected_action = action_index_for_shortcut(ch).expect("shortcut checked above");
            activate_selected_action(terminal, app)?;
        }
        _ => {}
    }

    Ok(())
}

fn handle_keys_key(_terminal: &mut AppTerminal, app: &mut App, key: KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Esc | KeyCode::Char('h') | KeyCode::Char('b') => {
            app.screen = Screen::Main;
        }
        KeyCode::Up | KeyCode::Char('k') => {
            if !app.snapshot.ssh_keys.is_empty() {
                if app.selected_key == 0 {
                    app.selected_key = app.snapshot.ssh_keys.len() - 1;
                } else {
                    app.selected_key -= 1;
                }
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            if !app.snapshot.ssh_keys.is_empty() {
                app.selected_key = (app.selected_key + 1) % app.snapshot.ssh_keys.len();
            }
        }
        KeyCode::Char('a') => {
            open_modal(
                app,
                InputAction::AddKey,
                "Add SSH key",
                "Paste a full public key line.",
                "",
            );
        }
        KeyCode::Char('e') | KeyCode::Char('s') => {
            open_modal(
                app,
                InputAction::SetPrimaryKey,
                "Replace SSH keys",
                "Replace the managed key list with a single public key line.",
                "",
            );
        }
        KeyCode::Delete | KeyCode::Backspace | KeyCode::Char('d') => {
            if let Some(selected_key) = app.snapshot.ssh_keys.get(app.selected_key).cloned() {
                run_action_capture(app, &["remove-ssh-key", selected_key.as_str()])?;
            }
        }
        _ => {}
    }

    Ok(())
}

fn handle_updates_key(terminal: &mut AppTerminal, app: &mut App, key: KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Esc | KeyCode::Char('h') | KeyCode::Char('b') => {
            app.screen = Screen::Main;
        }
        KeyCode::Up | KeyCode::Char('k') => {
            if app.selected_update == 0 {
                app.selected_update = UPDATE_ACTIONS.len() - 1;
            } else {
                app.selected_update -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            app.selected_update = (app.selected_update + 1) % UPDATE_ACTIONS.len();
        }
        KeyCode::Enter => activate_selected_update(terminal, app)?,
        KeyCode::Char('r') => {
            app.refresh_snapshot()?;
            app.start_update_check();
            app.push_log("Refreshed repository snapshot.");
        }
        KeyCode::Char('u') => {
            app.start_update_check();
            app.push_log("Started a new flake input update check.");
        }
        KeyCode::Char('q') => {
            app.should_open_shell = true;
        }
        KeyCode::Char(ch) if update_index_for_shortcut(ch).is_some() => {
            app.selected_update =
                update_index_for_shortcut(ch).expect("update shortcut checked above");
            activate_selected_update(terminal, app)?;
        }
        _ => {}
    }

    Ok(())
}

fn handle_modal_key(_terminal: &mut AppTerminal, app: &mut App, key: KeyEvent) -> Result<()> {
    let modal = app.modal.as_mut().expect("modal checked above");
    match key.code {
        KeyCode::Esc => app.modal = None,
        KeyCode::Enter => {
            let action = modal.action;
            let value = modal.value.trim().to_string();
            app.modal = None;
            submit_modal(app, action, value)?;
        }
        KeyCode::Backspace => {
            modal.value.pop();
        }
        KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
            modal.value.clear();
        }
        KeyCode::Char(ch) => {
            modal.value.push(ch);
        }
        _ => {}
    }

    Ok(())
}

fn submit_modal(app: &mut App, action: InputAction, value: String) -> Result<()> {
    if value.is_empty() {
        app.push_log("Ignored empty input.");
        return Ok(());
    }

    match action {
        InputAction::SetHostname => run_action_capture(app, &["set-hostname", value.as_str()])?,
        InputAction::SetUsername => run_action_capture(app, &["set-username", value.as_str()])?,
        InputAction::SetPrimaryKey => run_action_capture(app, &["set-ssh-key", value.as_str()])?,
        InputAction::AddKey => run_action_capture(app, &["add-ssh-key", value.as_str()])?,
        InputAction::AddSystemPackage => {
            run_action_capture(app, &["add-system-package", value.as_str()])?
        }
        InputAction::AddUserPackage => {
            run_action_capture(app, &["add-user-package", value.as_str()])?
        }
        InputAction::AddService => run_action_capture(app, &["add-service", value.as_str()])?,
    }

    if matches!(action, InputAction::SetPrimaryKey | InputAction::AddKey) {
        app.screen = Screen::Keys;
    }

    if matches!(action, InputAction::SetHostname | InputAction::SetUsername) {
        app.screen = Screen::Main;
    }

    Ok(())
}

fn activate_selected_action(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    match app.selected_action {
        0 => {
            let hostname = app.snapshot.hostname.clone();
            open_modal(
                app,
                InputAction::SetHostname,
                "Edit hostname",
                "Press Enter to write and commit the new hostname.",
                hostname.as_str(),
            )
        }
        1 => {
            let username = app.snapshot.username.clone();
            open_modal(
                app,
                InputAction::SetUsername,
                "Edit username",
                "Press Enter to write and commit the new username.",
                username.as_str(),
            )
        }
        2 => app.screen = Screen::Keys,
        3 => run_action_capture(app, &["toggle-extras"])?,
        4 => open_modal(
            app,
            InputAction::AddSystemPackage,
            "Add system package",
            "Enter a nixpkgs attribute path such as tailscale or unstable.myPkg.",
            "",
        ),
        5 => open_modal(
            app,
            InputAction::AddUserPackage,
            "Add user package",
            "Enter a nixpkgs attribute path for the user package list.",
            "",
        ),
        6 => open_modal(
            app,
            InputAction::AddService,
            "Add service",
            "Enter a dotted NixOS service path such as tailscale or prometheus.exporters.node.",
            "",
        ),
        7 => app.screen = Screen::Updates,
        8 => app.should_open_shell = true,
        9 => run_command_interactive(terminal, app, "Rollback system", {
            let mut command = Command::new(app.repo_root.join("scripts/apply-config.sh"));
            command.arg("--rollback");
            command
        })?,
        10 => run_command_interactive(terminal, app, "Collect garbage", {
            let mut command = Command::new("sudo");
            command.args(["nix-collect-garbage", "-d"]);
            command
        })?,
        _ => {}
    }

    Ok(())
}

fn activate_selected_update(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    let update = app.selected_update_item();
    run_action_interactive(terminal, app, &[update.backend])
}

fn open_modal(app: &mut App, action: InputAction, title: &str, help: &str, initial: &str) {
    app.modal = Some(InputModal {
        title: title.to_string(),
        help: help.to_string(),
        action,
        value: initial.to_string(),
    });
}

fn run_action_capture(app: &mut App, args: &[&str]) -> Result<()> {
    let output = backend_action(&app.repo_root, args)
        .with_context(|| format!("failed to run backend action {}", args.join(" ")))?;
    let success = output.status.success();
    let rendered = render_output(&output);

    if rendered.is_empty() {
        app.push_log(format!("Action `{}` completed.", args.join(" ")));
    } else {
        for line in rendered.lines() {
            app.push_log(line.to_string());
        }
    }

    app.refresh_snapshot()?;
    app.start_update_check();

    if !success {
        app.push_log(format!(
            "Action `{}` exited with status {}.",
            args.join(" "),
            output.status
        ));
    }

    Ok(())
}

fn run_action_interactive(terminal: &mut AppTerminal, app: &mut App, args: &[&str]) -> Result<()> {
    let mut command = Command::new(app.repo_root.join("scripts/tui/action.sh"));
    command.args(args).env("NIXOA_SYSTEM_ROOT", &app.repo_root);
    run_command_interactive(
        terminal,
        app,
        format!("Interactive action `{}`", args.join(" ")),
        command,
    )
}

fn backend_action(repo_root: &Path, args: &[&str]) -> Result<Output> {
    Command::new(repo_root.join("scripts/tui/action.sh"))
        .args(args)
        .env("NIXOA_SYSTEM_ROOT", repo_root)
        .output()
        .with_context(|| {
            format!(
                "failed to execute {}",
                repo_root.join("scripts/tui/action.sh").display()
            )
        })
}

fn run_command_interactive(
    terminal: &mut AppTerminal,
    app: &mut App,
    label: impl Into<String>,
    mut command: Command,
) -> Result<()> {
    let label = label.into();
    command.env("NIXOA_SYSTEM_ROOT", &app.repo_root);

    suspend_terminal(terminal)?;
    let status_result = command.status();
    let resume_result = resume_terminal(terminal);
    let status =
        status_result.with_context(|| format!("failed to run interactive command for {label}"))?;
    resume_result?;

    if status.success() {
        app.push_log(format!("{label} completed successfully."));
    } else {
        app.push_log(format!("{label} failed with status {status}."));
    }

    app.refresh_snapshot()?;
    app.start_update_check();

    Ok(())
}

fn render_output(output: &Output) -> String {
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    match (stdout.is_empty(), stderr.is_empty()) {
        (true, true) => String::new(),
        (false, true) => stdout,
        (true, false) => stderr,
        (false, false) => format!("{stdout}\n{stderr}"),
    }
}

fn format_gib(bytes: u64) -> f64 {
    bytes as f64 / 1024.0 / 1024.0 / 1024.0
}

fn short_sha(value: &str) -> String {
    value.chars().take(8).collect()
}

fn format_usage(used_bytes: u64, total_bytes: u64, percent: u32) -> String {
    if total_bytes == 0 {
        "unavailable".to_string()
    } else {
        format!(
            "{:.1} / {:.1} GiB ({}%)",
            format_gib(used_bytes),
            format_gib(total_bytes),
            percent
        )
    }
}

fn usage_color(percent: u32) -> Color {
    if percent >= 90 {
        Color::Red
    } else if percent >= 75 {
        Color::Yellow
    } else {
        Color::Green
    }
}

fn action_index_for_shortcut(shortcut: char) -> Option<usize> {
    ACTIONS
        .iter()
        .position(|action| action.shortcut == shortcut)
}

fn update_index_for_shortcut(shortcut: char) -> Option<usize> {
    UPDATE_ACTIONS
        .iter()
        .position(|action| action.shortcut == shortcut)
}

fn check_flake_updates(repo_root: &Path) -> UpdateStatus {
    let current_lock = repo_root.join("flake.lock");
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    let temp_lock = env::temp_dir().join(format!("nixoa-menu-{nonce}.lock"));
    let timeout_seconds = UPDATE_TIMEOUT_SECS.to_string();
    let repo_arg = repo_root.to_string_lossy().to_string();
    let lock_arg = temp_lock.to_string_lossy().to_string();

    let output = Command::new("timeout")
        .args([
            timeout_seconds.as_str(),
            "nix",
            "flake",
            "update",
            "--flake",
            repo_arg.as_str(),
            "--output-lock-file",
            lock_arg.as_str(),
        ])
        .output();

    let status = match output {
        Ok(output) => {
            if output.status.success() {
                match count_lock_changes(&current_lock, &temp_lock) {
                    Ok(0) => UpdateStatus::UpToDate,
                    Ok(count) => UpdateStatus::Available(count),
                    Err(error) => UpdateStatus::Error(error.to_string()),
                }
            } else {
                let message = render_output(&output);
                UpdateStatus::Error(if message.is_empty() {
                    "nix flake update returned a non-zero status".to_string()
                } else {
                    message
                })
            }
        }
        Err(error) => UpdateStatus::Error(error.to_string()),
    };

    let _ = fs::remove_file(temp_lock);
    status
}

fn count_lock_changes(current_lock: &Path, updated_lock: &Path) -> Result<usize> {
    let current: FlakeLock = serde_json::from_slice(
        &fs::read(current_lock)
            .with_context(|| format!("failed to read {}", current_lock.display()))?,
    )
    .context("failed to parse current flake.lock")?;
    let updated: FlakeLock = serde_json::from_slice(
        &fs::read(updated_lock)
            .with_context(|| format!("failed to read {}", updated_lock.display()))?,
    )
    .context("failed to parse temporary flake.lock")?;

    let mut names = BTreeSet::new();
    names.extend(current.nodes.keys().cloned());
    names.extend(updated.nodes.keys().cloned());
    names.remove("root");

    Ok(names
        .into_iter()
        .filter(|name| {
            current.nodes.get(name).and_then(|node| node.locked.clone())
                != updated.nodes.get(name).and_then(|node| node.locked.clone())
        })
        .count())
}

fn render(frame: &mut Frame, app: &App) {
    let area = frame.area();
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(9),
            Constraint::Min(16),
            Constraint::Length(9),
        ])
        .split(area);

    render_status_grid(frame, vertical[0], app);

    let middle = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(38), Constraint::Percentage(62)])
        .split(vertical[1]);

    render_actions(frame, middle[0], app);

    match app.screen {
        Screen::Main => render_dashboard(frame, middle[1], app),
        Screen::Keys => render_keys(frame, middle[1], app),
        Screen::Updates => render_updates(frame, middle[1], app),
    }

    let bottom = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(62), Constraint::Percentage(38)])
        .split(vertical[2]);

    render_logs(frame, bottom[0], app);
    render_help(frame, bottom[1], app);

    if let Some(modal) = &app.modal {
        render_modal(frame, area, modal);
    }
}

fn render_status_grid(frame: &mut Frame, area: Rect, app: &App) {
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(4), Constraint::Length(4)])
        .split(area);

    let top_boxes = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
        ])
        .split(rows[0]);

    let bottom_boxes = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(34),
            Constraint::Percentage(33),
            Constraint::Percentage(33),
        ])
        .split(rows[1]);

    let (repo_text, repo_color) = if app.snapshot.dirty_count == 0 {
        ("clean".to_string(), Color::Green)
    } else {
        (format!("{} dirty", app.snapshot.dirty_count), Color::Yellow)
    };

    let (apply_text, apply_color) = if app.snapshot.rebuild_queued {
        ("queued for reboot".to_string(), Color::Cyan)
    } else {
        match &app.snapshot.last_apply {
            Some(last_apply)
                if last_apply.result == "success"
                    && last_apply.action == "switch"
                    && !app.snapshot.rebuild_needed =>
            {
                (format!("synced {}", last_apply.timestamp), Color::Green)
            }
            Some(last_apply) if last_apply.result != "success" => {
                (format!("failed {}", last_apply.timestamp), Color::Red)
            }
            Some(last_apply) => (
                format!("{} {}", last_apply.action, last_apply.timestamp),
                Color::Yellow,
            ),
            None => ("not applied".to_string(), Color::Yellow),
        }
    };

    let (upstream_text, upstream_color) = if app.snapshot.behind > 0 {
        (
            format!(
                "behind {} / ahead {}",
                app.snapshot.behind, app.snapshot.ahead
            ),
            Color::Yellow,
        )
    } else if app.snapshot.ahead > 0 {
        (format!("ahead {}", app.snapshot.ahead), Color::Cyan)
    } else {
        ("aligned".to_string(), Color::Green)
    };

    let (update_text, update_color) = match &app.update_status {
        UpdateStatus::Idle => ("idle".to_string(), Color::DarkGray),
        UpdateStatus::Checking => {
            let frames = ["-", "\\", "|", "/"];
            (
                format!("checking {}", frames[app.tick % frames.len()]),
                Color::Cyan,
            )
        }
        UpdateStatus::UpToDate => ("up to date".to_string(), Color::Green),
        UpdateStatus::Available(count) => (format!("{count} updates"), Color::Yellow),
        UpdateStatus::Error(_) => ("check failed".to_string(), Color::Red),
    };

    let memory_text = format_usage(
        app.snapshot.memory_used_bytes,
        app.snapshot.memory_total_bytes,
        app.snapshot.memory_used_percent,
    );
    let memory_color = usage_color(app.snapshot.memory_used_percent);

    let storage_text = format_usage(
        app.snapshot.storage_used_bytes,
        app.snapshot.storage_total_bytes,
        app.snapshot.storage_used_percent,
    );
    let storage_color = usage_color(app.snapshot.storage_used_percent);

    let ip_text = app
        .snapshot
        .primary_ip
        .clone()
        .unwrap_or_else(|| "unavailable".to_string());
    let ip_color = if app.snapshot.primary_ip.is_some() {
        Color::Green
    } else {
        Color::Yellow
    };

    render_status_box(frame, top_boxes[0], "Repo", &repo_text, repo_color);
    render_status_box(frame, top_boxes[1], "Apply", &apply_text, apply_color);
    render_status_box(
        frame,
        top_boxes[2],
        "Upstream",
        &upstream_text,
        upstream_color,
    );
    render_status_box(frame, top_boxes[3], "Inputs", &update_text, update_color);
    render_status_box(frame, bottom_boxes[0], "RAM", &memory_text, memory_color);
    render_status_box(
        frame,
        bottom_boxes[1],
        "Storage",
        &storage_text,
        storage_color,
    );
    render_status_box(frame, bottom_boxes[2], "IP", &ip_text, ip_color);
}

fn render_status_box(frame: &mut Frame, area: Rect, title: &str, body: &str, color: Color) {
    let block = Block::default()
        .title(
            Line::from(title).style(
                Style::default()
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD),
            ),
        )
        .borders(Borders::ALL)
        .border_set(border::ROUNDED)
        .border_style(Style::default().fg(color))
        .border_type(BorderType::Rounded);

    let text = Paragraph::new(Line::from(body.to_string()).style(Style::default().fg(color)))
        .alignment(Alignment::Center)
        .block(block);
    frame.render_widget(text, area);
}

fn render_actions(frame: &mut Frame, area: Rect, app: &App) {
    let items: Vec<ListItem> = ACTIONS
        .iter()
        .enumerate()
        .map(|(index, action)| {
            let prefix = if index == app.selected_action {
                "›"
            } else {
                " "
            };
            ListItem::new(Line::from(format!(
                "{prefix} {}. {}",
                action.shortcut, action.title
            )))
        })
        .collect();

    let block = Block::default()
        .title(Line::from(APP_TITLE).style(Style::default().add_modifier(Modifier::BOLD)))
        .title_bottom(Line::from(format!(
            "{} @ {}",
            app.snapshot.username, app.snapshot.hostname
        )))
        .borders(Borders::ALL)
        .border_set(border::ROUNDED)
        .border_type(BorderType::Rounded);

    let list = List::new(items).block(block).highlight_style(
        Style::default()
            .fg(Color::Black)
            .bg(Color::Cyan)
            .add_modifier(Modifier::BOLD),
    );

    let mut state = ListState::default();
    state.select(Some(app.selected_action));
    frame.render_stateful_widget(list, area, &mut state);
}

fn render_dashboard(frame: &mut Frame, area: Rect, app: &App) {
    let sections = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(10), Constraint::Min(7)])
        .split(area);

    let summary = vec![
        Line::from(format!("Hostname: {}", app.snapshot.hostname)),
        Line::from(format!("Username: {}", app.snapshot.username)),
        Line::from(format!("Time zone: {}", app.snapshot.timezone)),
        Line::from(format!(
            "Extras: {}",
            if app.snapshot.extras {
                "enabled"
            } else {
                "disabled"
            }
        )),
        Line::from(format!(
            "SSH keys: {}    System packages: {}",
            app.snapshot.ssh_keys.len(),
            app.snapshot.system_packages.len()
        )),
        Line::from(format!(
            "User packages: {}    Services: {}",
            app.snapshot.user_packages.len(),
            app.snapshot.services.len()
        )),
        Line::from(format!(
            "RAM: {}",
            format_usage(
                app.snapshot.memory_used_bytes,
                app.snapshot.memory_total_bytes,
                app.snapshot.memory_used_percent
            )
        )),
        Line::from(format!(
            "Storage: {}    IP: {}",
            format_usage(
                app.snapshot.storage_used_bytes,
                app.snapshot.storage_total_bytes,
                app.snapshot.storage_used_percent
            ),
            app.snapshot
                .primary_ip
                .clone()
                .unwrap_or_else(|| "unavailable".to_string())
        )),
        Line::from(format!(
            "Branch: {}    Head: {}",
            app.snapshot.branch,
            short_sha(&app.snapshot.head)
        )),
        Line::from(format!(
            "Queued rebuild: {}",
            if app.snapshot.rebuild_queued {
                "next boot"
            } else {
                "no"
            }
        )),
        Line::from(format!("Selected: {}", app.selected_item().detail)),
    ];

    let summary_block = Paragraph::new(summary)
        .block(
            Block::default()
                .title("Host state")
                .borders(Borders::ALL)
                .border_set(border::ROUNDED)
                .border_type(BorderType::Rounded),
        )
        .wrap(Wrap { trim: true });
    frame.render_widget(summary_block, sections[0]);

    let alerts: Vec<ListItem> = app
        .alerts()
        .into_iter()
        .map(|alert| ListItem::new(Line::from(alert)))
        .collect();

    let alerts_block = List::new(alerts).block(
        Block::default()
            .title("Alerts")
            .borders(Borders::ALL)
            .border_set(border::ROUNDED)
            .border_type(BorderType::Rounded),
    );
    frame.render_widget(alerts_block, sections[1]);
}

fn render_keys(frame: &mut Frame, area: Rect, app: &App) {
    let sections = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(60), Constraint::Percentage(40)])
        .split(area);

    let items: Vec<ListItem> = if app.snapshot.ssh_keys.is_empty() {
        vec![ListItem::new(Line::from(
            "No SSH keys are currently configured.",
        ))]
    } else {
        app.snapshot
            .ssh_keys
            .iter()
            .enumerate()
            .map(|(index, key)| {
                let marker = if index == app.selected_key {
                    "›"
                } else {
                    " "
                };
                ListItem::new(Line::from(format!("{marker} {}", truncate_middle(key, 88))))
            })
            .collect()
    };

    let mut state = ListState::default();
    if !app.snapshot.ssh_keys.is_empty() {
        state.select(Some(app.selected_key));
    }

    let keys_list = List::new(items)
        .block(
            Block::default()
                .title("SSH key manager")
                .title_bottom("a add  e replace  d delete  Esc back")
                .borders(Borders::ALL)
                .border_set(border::ROUNDED)
                .border_type(BorderType::Rounded),
        )
        .highlight_style(
            Style::default()
                .fg(Color::Black)
                .bg(Color::Green)
                .add_modifier(Modifier::BOLD),
        );

    frame.render_stateful_widget(keys_list, sections[0], &mut state);

    let help_lines = vec![
        Line::from("The SSH key view edits the same config/menu.nix override layer used by the bootstrap and shell tools."),
        Line::from(""),
        Line::from("Each successful action commits only the affected menu file."),
        Line::from(""),
        Line::from("Replace writes a single managed key."),
        Line::from("Add appends a new unique key."),
        Line::from("Delete removes the selected key."),
    ];

    let help = Paragraph::new(help_lines)
        .block(
            Block::default()
                .title("Key actions")
                .borders(Borders::ALL)
                .border_set(border::ROUNDED)
                .border_type(BorderType::Rounded),
        )
        .wrap(Wrap { trim: true });
    frame.render_widget(help, sections[1]);
}

fn render_updates(frame: &mut Frame, area: Rect, app: &App) {
    let sections = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(46), Constraint::Percentage(54)])
        .split(area);

    let items: Vec<ListItem> = UPDATE_ACTIONS
        .iter()
        .enumerate()
        .map(|(index, action)| {
            let marker = if index == app.selected_update {
                "›"
            } else {
                " "
            };
            ListItem::new(Line::from(format!(
                "{marker} {}. {}",
                action.shortcut, action.title
            )))
        })
        .collect();

    let mut state = ListState::default();
    state.select(Some(app.selected_update));

    let updates = List::new(items)
        .block(
            Block::default()
                .title("Update menu")
                .title_bottom("Enter run  Esc back")
                .borders(Borders::ALL)
                .border_set(border::ROUNDED)
                .border_type(BorderType::Rounded),
        )
        .highlight_style(
            Style::default()
                .fg(Color::Black)
                .bg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        );

    frame.render_stateful_widget(updates, sections[0], &mut state);

    let detail_lines = vec![
        Line::from(app.selected_update_item().detail),
        Line::from(""),
        Line::from(format!(
            "Queued on boot: {}",
            if app.snapshot.rebuild_queued {
                "yes"
            } else {
                "no"
            }
        )),
        Line::from(format!(
            "Rebuild needed: {}",
            if app.snapshot.rebuild_needed {
                "yes"
            } else {
                "no"
            }
        )),
        Line::from(""),
        Line::from("Each update commits only flake.lock."),
        Line::from(
            "After a lock change, the console asks whether to rebuild now or on the next boot.",
        ),
        Line::from(
            "The XOA updater checks the latest upstream tag before refreshing xen-orchestra-ce.",
        ),
    ];

    let details = Paragraph::new(detail_lines)
        .block(
            Block::default()
                .title("Update details")
                .borders(Borders::ALL)
                .border_set(border::ROUNDED)
                .border_type(BorderType::Rounded),
        )
        .wrap(Wrap { trim: true });
    frame.render_widget(details, sections[1]);
}

fn render_logs(frame: &mut Frame, area: Rect, app: &App) {
    let lines: Vec<Line> = app
        .logs
        .iter()
        .rev()
        .take(8)
        .rev()
        .map(|entry| Line::from(entry.clone()))
        .collect();

    let logs = Paragraph::new(Text::from(lines))
        .block(
            Block::default()
                .title("Activity")
                .borders(Borders::ALL)
                .border_set(border::ROUNDED)
                .border_type(BorderType::Rounded),
        )
        .wrap(Wrap { trim: false });
    frame.render_widget(logs, area);
}

fn render_help(frame: &mut Frame, area: Rect, app: &App) {
    let help_text = match app.screen {
        Screen::Main => vec![
            Line::from("Arrows/jk move"),
            Line::from("Enter, 1-9, 0, or g run actions"),
            Line::from("r refresh snapshot"),
            Line::from("u refresh flake input check"),
            Line::from("q or 9 open shell"),
        ],
        Screen::Keys => vec![
            Line::from("Arrows/jk move"),
            Line::from("a add key"),
            Line::from("e replace all keys"),
            Line::from("d or Backspace remove selected"),
            Line::from("Esc back to dashboard"),
        ],
        Screen::Updates => vec![
            Line::from("Arrows/jk move"),
            Line::from("Enter or 1-4 run updates"),
            Line::from("r refresh snapshot"),
            Line::from("u refresh flake input check"),
            Line::from("Esc back to dashboard, q open shell"),
        ],
    };

    let footer = if let Some(last_apply) = &app.snapshot.last_apply {
        format!(
            "Last apply: {} {} on {} @ {}{} [{}]",
            last_apply.result,
            last_apply.action,
            last_apply.hostname,
            last_apply.timestamp,
            if last_apply.first_install {
                " (first install)"
            } else {
                ""
            },
            short_sha(&last_apply.head)
        )
    } else {
        "Last apply: not recorded".to_string()
    };

    let help = Paragraph::new(help_text)
        .block(
            Block::default()
                .title("Keys")
                .title_bottom(footer)
                .borders(Borders::ALL)
                .border_set(border::ROUNDED)
                .border_type(BorderType::Rounded),
        )
        .wrap(Wrap { trim: true });
    frame.render_widget(help, area);
}

fn render_modal(frame: &mut Frame, area: Rect, modal: &InputModal) {
    let popup = centered_rect(68, 28, area);
    frame.render_widget(Clear, popup);

    let block = Block::default()
        .title(Line::from(modal.title.clone()).style(Style::default().add_modifier(Modifier::BOLD)))
        .borders(Borders::ALL)
        .border_set(border::ROUNDED)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(Color::Cyan));

    let content = vec![
        Line::from(modal.help.clone()),
        Line::from(""),
        Line::from(format!("> {}", modal.value)),
        Line::from(""),
        Line::from("Enter submits. Esc cancels. Ctrl+u clears the input."),
    ];

    let paragraph = Paragraph::new(content)
        .block(block)
        .alignment(Alignment::Left)
        .wrap(Wrap { trim: true });

    frame.render_widget(paragraph, popup);
}

fn centered_rect(percent_x: u16, percent_y: u16, area: Rect) -> Rect {
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(area);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(vertical[1])[1]
}

fn truncate_middle(value: &str, max_width: usize) -> String {
    if value.chars().count() <= max_width {
        return value.to_string();
    }

    let keep = max_width.saturating_sub(3) / 2;
    let start: String = value.chars().take(keep).collect();
    let end: String = value
        .chars()
        .rev()
        .take(keep)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    format!("{start}...{end}")
}

fn open_shell() -> ! {
    let shell = env::var("SHELL").unwrap_or_else(|_| "/run/current-system/sw/bin/bash".to_string());
    let error = Command::new(shell)
        .arg("-l")
        .env("NIXOA_TUI_BYPASS", "1")
        .exec();
    panic!("failed to exec shell: {error}");
}
