use std::cmp::{max, min};
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
use ratatui::prelude::{Color, Line, Modifier, Span, Style};
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

const UPDATE_TIMEOUT_SECS: u64 = 120;
const MAX_LOG_ENTRIES: usize = 160;
const DASHBOARD_LOG_LINES: usize = 5;

const COLOR_BG_OUTER: Color = Color::Rgb(0x1C, 0x1B, 0x34);
const COLOR_BG_INNER: Color = Color::Rgb(0x1A, 0x1A, 0x22);
const COLOR_FG_MAIN: Color = Color::Rgb(0xF7, 0xF7, 0xF9);
const COLOR_ACCENT: Color = Color::Rgb(0x87, 0x7C, 0xFC);
const COLOR_ACCENT_SOFT: Color = Color::Rgb(0x6B, 0x6B, 0xD7);
const COLOR_DANGER: Color = Color::Rgb(0xFF, 0x00, 0x25);
const COLOR_MUTED: Color = Color::Rgb(0xD4, 0xD4, 0xD7);
const COLOR_MUTED_2: Color = Color::Rgb(0xAD, 0xAD, 0xB1);
const COLOR_BORDER_DIM: Color = Color::Rgb(0x4A, 0x4A, 0x52);
const COLOR_BORDER_MID: Color = Color::Rgb(0x73, 0x73, 0x7A);
const COLOR_WARNING: Color = Color::Rgb(0xC1, 0xC1, 0xC7);
const COLOR_SUCCESS: Color = Color::Rgb(0x87, 0x7C, 0xFC);
const COLOR_INFO: Color = Color::Rgb(0x6B, 0x6B, 0xD7);

#[derive(Clone, Debug)]
struct ActionItem {
    kind: ActionKind,
    title: &'static str,
    detail: &'static str,
    shortcut: Option<char>,
}

#[derive(Clone, Debug)]
struct UpdateItem {
    title: &'static str,
    detail: &'static str,
    backend: &'static str,
    shortcut: char,
}

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
    xen_orchestra_version: Option<String>,
    web_ui_url: Option<String>,
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
enum Page {
    Dashboard,
    Configure,
    Software,
    Maintenance,
    Logs,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Focus {
    TopNav,
    MainActions,
    DashboardAlerts,
    ConfigureSshKeys,
    MaintenanceFlakeInputs,
    LogsView,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionKind {
    RefreshSnapshot,
    CheckForUpdates,
    EditHostname,
    EditUsername,
    ToggleExtras,
    ManageSshKeys,
    AddSystemPackage,
    AddUserPackage,
    AddService,
    ApplyConfiguration,
    RollbackGeneration,
    RunGarbageCollection,
    RebootSystem,
    ShutdownSystem,
    CleanupUnmanagedUsers,
    FilterLogs,
    ClearLogFilter,
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
    ConfirmCleanupUnmanagedUsers,
    SetLogFilter,
}

#[derive(Debug, Clone, Copy)]
enum Severity {
    Info,
    Warning,
    Error,
}

#[derive(Debug, Clone, Copy)]
enum AlertCommand {
    OpenMaintenance,
    CheckForUpdates,
    ApplyConfiguration,
    OpenLogs,
}

#[derive(Debug, Clone)]
struct AlertItem {
    severity: Severity,
    message: String,
    action_label: Option<&'static str>,
    action: Option<AlertCommand>,
}

#[derive(Debug, Clone)]
struct InputModal {
    title: String,
    help: String,
    action: InputAction,
    value: String,
}

#[derive(Debug, Clone)]
struct CommandPalette {
    query: String,
    selected: usize,
}

#[derive(Debug, Clone)]
struct PaletteEntry {
    title: String,
    detail: String,
    action: PaletteAction,
}

#[derive(Debug, Clone)]
enum PaletteAction {
    SwitchPage(Page),
    RunAction(ActionKind),
    OpenShell,
    OpenHelp,
}

#[derive(Debug)]
struct App {
    repo_root: PathBuf,
    snapshot: Snapshot,
    update_status: UpdateStatus,
    update_rx: Option<Receiver<UpdateStatus>>,
    page: Page,
    focus: Focus,
    page_selection: [usize; 5],
    selected_update: usize,
    selected_key: usize,
    selected_alert: usize,
    modal: Option<InputModal>,
    command_palette: Option<CommandPalette>,
    help_open: bool,
    quit_confirm: bool,
    logs: Vec<String>,
    log_filter: String,
    log_scroll: usize,
    should_quit: bool,
    should_open_shell: bool,
    tick: usize,
}

const DASHBOARD_ACTIONS: [ActionItem; 2] = [
    ActionItem {
        kind: ActionKind::RefreshSnapshot,
        title: "Refresh Snapshot",
        detail: "Reload host state, repository status, and current appliance health.",
        shortcut: Some('r'),
    },
    ActionItem {
        kind: ActionKind::CheckForUpdates,
        title: "Check for Updates",
        detail: "Open the Flake Inputs update submenu in Maintenance and re-run the lock check.",
        shortcut: Some('u'),
    },
];

const CONFIGURE_ACTIONS: [ActionItem; 4] = [
    ActionItem {
        kind: ActionKind::EditHostname,
        title: "Hostname",
        detail: "Write a new hostname into config/menu.nix and commit the change immediately.",
        shortcut: Some('1'),
    },
    ActionItem {
        kind: ActionKind::EditUsername,
        title: "Username",
        detail: "Write a new primary username into config/menu.nix and commit the change immediately.",
        shortcut: Some('2'),
    },
    ActionItem {
        kind: ActionKind::ToggleExtras,
        title: "Extras",
        detail: "Enable or disable the extras feature set and commit the resulting menu override.",
        shortcut: Some('3'),
    },
    ActionItem {
        kind: ActionKind::ManageSshKeys,
        title: "SSH Keys",
        detail: "Manage the authorized SSH public keys tracked by the console override layer.",
        shortcut: Some('4'),
    },
];

const SOFTWARE_ACTIONS: [ActionItem; 3] = [
    ActionItem {
        kind: ActionKind::AddSystemPackage,
        title: "System Packages",
        detail: "Append a nixpkgs attribute path to extraSystemPackages in config/menu.nix.",
        shortcut: Some('5'),
    },
    ActionItem {
        kind: ActionKind::AddUserPackage,
        title: "User Packages",
        detail: "Append a nixpkgs attribute path to extraUserPackages in config/menu.nix.",
        shortcut: Some('6'),
    },
    ActionItem {
        kind: ActionKind::AddService,
        title: "Services",
        detail: "Enable a service by dotted NixOS option path in config/menu.nix.",
        shortcut: Some('7'),
    },
];

const MAINTENANCE_ACTIONS: [ActionItem; 7] = [
    ActionItem {
        kind: ActionKind::CheckForUpdates,
        title: "Check for Updates",
        detail: "Inspect flake input updates for nixpkgs, Home Manager, XOA, or the full system.",
        shortcut: Some('8'),
    },
    ActionItem {
        kind: ActionKind::ApplyConfiguration,
        title: "Apply Configuration",
        detail: "Run apply-config.sh for the current host and refresh console state after completion.",
        shortcut: Some('a'),
    },
    ActionItem {
        kind: ActionKind::RollbackGeneration,
        title: "Rollback Generation",
        detail: "Run nixos-rebuild switch --rollback interactively for the current host.",
        shortcut: Some('0'),
    },
    ActionItem {
        kind: ActionKind::RunGarbageCollection,
        title: "Run Garbage Collection",
        detail: "Run nix-collect-garbage -d interactively for a full manual store cleanup.",
        shortcut: Some('g'),
    },
    ActionItem {
        kind: ActionKind::RebootSystem,
        title: "Reboot System",
        detail: "Run systemctl reboot through wrapper sudo for a clean systemd-managed reboot.",
        shortcut: Some('b'),
    },
    ActionItem {
        kind: ActionKind::ShutdownSystem,
        title: "Shut Down System",
        detail: "Run systemctl poweroff through wrapper sudo for a clean systemd-managed shutdown.",
        shortcut: Some('s'),
    },
    ActionItem {
        kind: ActionKind::CleanupUnmanagedUsers,
        title: "Cleanup Unmanaged Users",
        detail: "Remove non-system users outside the flake-managed admin account and delete their home data after confirmation.",
        shortcut: Some('x'),
    },
];

const LOG_ACTIONS: [ActionItem; 2] = [
    ActionItem {
        kind: ActionKind::FilterLogs,
        title: "Filter Logs",
        detail: "Set a substring filter for Recent Activity and the dedicated Logs page.",
        shortcut: Some('/'),
    },
    ActionItem {
        kind: ActionKind::ClearLogFilter,
        title: "Clear Log Filter",
        detail: "Clear the current activity log filter and reset log scrolling to the newest entries.",
        shortcut: Some('c'),
    },
];

const UPDATE_ACTIONS: [UpdateItem; 5] = [
    UpdateItem {
        title: "Update nixpkgs",
        detail: "Refresh only the nixpkgs lock entry and then choose whether to rebuild now or on reboot.",
        backend: "update-nixpkgs",
        shortcut: '1',
    },
    UpdateItem {
        title: "Update Home Manager",
        detail: "Refresh only the home-manager lock entry and then choose whether to rebuild now or on reboot.",
        backend: "update-home-manager",
        shortcut: '2',
    },
    UpdateItem {
        title: "Update Determinate",
        detail: "Refresh only the determinate lock entry and then choose whether to rebuild now or on reboot.",
        backend: "update-determinate",
        shortcut: '3',
    },
    UpdateItem {
        title: "Update XOA",
        detail: "Check the latest xen-orchestra-ce tag, refresh that input lock, and then choose whether to rebuild now or on reboot.",
        backend: "update-xoa",
        shortcut: '4',
    },
    UpdateItem {
        title: "Update all",
        detail: "Run a full nix flake update and then choose whether to rebuild now or on reboot.",
        backend: "update-all",
        shortcut: '5',
    },
];

impl App {
    fn new(repo_root: PathBuf, snapshot: Snapshot) -> Self {
        let mut app = Self {
            repo_root,
            snapshot,
            update_status: UpdateStatus::Idle,
            update_rx: None,
            page: Page::Dashboard,
            focus: Focus::MainActions,
            page_selection: [0; 5],
            selected_update: 0,
            selected_key: 0,
            selected_alert: 0,
            modal: None,
            command_palette: None,
            help_open: false,
            quit_confirm: false,
            logs: vec![
                "NiXOA console ready.".to_string(),
                "Use arrows or h/j/k/l for navigation, Tab for focus cycling, and [ ] for pages."
                    .to_string(),
            ],
            log_filter: String::new(),
            log_scroll: 0,
            should_quit: false,
            should_open_shell: false,
            tick: 0,
        };
        app.clamp_selection_state();
        app
    }

    fn page_index(page: Page) -> usize {
        match page {
            Page::Dashboard => 0,
            Page::Configure => 1,
            Page::Software => 2,
            Page::Maintenance => 3,
            Page::Logs => 4,
        }
    }

    fn current_page_actions(&self) -> &'static [ActionItem] {
        match self.page {
            Page::Dashboard => &DASHBOARD_ACTIONS,
            Page::Configure => &CONFIGURE_ACTIONS,
            Page::Software => &SOFTWARE_ACTIONS,
            Page::Maintenance => &MAINTENANCE_ACTIONS,
            Page::Logs => &LOG_ACTIONS,
        }
    }

    fn current_selection(&self) -> usize {
        self.page_selection[Self::page_index(self.page)]
    }

    fn current_selection_mut(&mut self) -> &mut usize {
        &mut self.page_selection[Self::page_index(self.page)]
    }

    fn sidebar_len(&self) -> usize {
        self.current_page_actions().len() + 1
    }

    fn selected_page_action(&self) -> Option<&'static ActionItem> {
        let actions = self.current_page_actions();
        actions.get(self.current_selection())
    }

    fn selected_action_kind(&self) -> Option<ActionKind> {
        self.selected_page_action().map(|item| item.kind)
    }

    fn selected_sidebar_title(&self) -> &'static str {
        self.selected_page_action()
            .map(|item| item.title)
            .unwrap_or("Open Shell")
    }

    fn selected_sidebar_detail(&self) -> &'static str {
        self.selected_page_action()
            .map(|item| item.detail)
            .unwrap_or("Leave the TUI and exec the configured login shell with TUI bypass enabled.")
    }

    fn page_title(&self) -> &'static str {
        match self.page {
            Page::Dashboard => "Dashboard",
            Page::Configure => "Configure",
            Page::Software => "Software",
            Page::Maintenance => "Maintenance",
            Page::Logs => "Logs",
        }
    }

    fn set_page(&mut self, page: Page) {
        let keep_top_nav = self.focus == Focus::TopNav;
        self.page = page;
        self.clamp_selection_state();
        self.focus = if keep_top_nav {
            Focus::TopNav
        } else {
            Focus::MainActions
        };
        self.ensure_focus_valid();
    }

    fn next_page(&mut self) {
        self.set_page(match self.page {
            Page::Dashboard => Page::Configure,
            Page::Configure => Page::Software,
            Page::Software => Page::Maintenance,
            Page::Maintenance => Page::Logs,
            Page::Logs => Page::Dashboard,
        });
    }

    fn previous_page(&mut self) {
        self.set_page(match self.page {
            Page::Dashboard => Page::Logs,
            Page::Configure => Page::Dashboard,
            Page::Software => Page::Configure,
            Page::Maintenance => Page::Software,
            Page::Logs => Page::Maintenance,
        });
    }

    fn is_focus_valid(&self, focus: Focus) -> bool {
        match focus {
            Focus::TopNav | Focus::MainActions => true,
            Focus::DashboardAlerts => self.page == Page::Dashboard,
            Focus::ConfigureSshKeys => {
                self.page == Page::Configure
                    && self.selected_action_kind() == Some(ActionKind::ManageSshKeys)
            }
            Focus::MaintenanceFlakeInputs => {
                self.page == Page::Maintenance
                    && self.selected_action_kind() == Some(ActionKind::CheckForUpdates)
            }
            Focus::LogsView => self.page == Page::Logs,
        }
    }

    fn ensure_focus_valid(&mut self) {
        if !self.is_focus_valid(self.focus) {
            self.focus = Focus::MainActions;
        }
    }

    fn set_focus(&mut self, focus: Focus) {
        self.focus = focus;
        self.ensure_focus_valid();
    }

    fn action_child_focus(&self) -> Option<Focus> {
        if self.current_selection() >= self.current_page_actions().len() {
            return None;
        }

        match self.page {
            Page::Dashboard => Some(Focus::DashboardAlerts),
            Page::Configure if self.selected_action_kind() == Some(ActionKind::ManageSshKeys) => {
                Some(Focus::ConfigureSshKeys)
            }
            Page::Maintenance
                if self.selected_action_kind() == Some(ActionKind::CheckForUpdates) =>
            {
                Some(Focus::MaintenanceFlakeInputs)
            }
            Page::Logs => Some(Focus::LogsView),
            _ => None,
        }
    }

    fn parent_focus(&self) -> Option<Focus> {
        match self.focus {
            Focus::DashboardAlerts
            | Focus::ConfigureSshKeys
            | Focus::MaintenanceFlakeInputs
            | Focus::LogsView => Some(Focus::MainActions),
            Focus::TopNav | Focus::MainActions => None,
        }
    }

    fn focus_order(&self) -> Vec<Focus> {
        let mut order = vec![Focus::TopNav, Focus::MainActions];
        if let Some(child) = self.action_child_focus() {
            order.push(child);
        }
        order
    }

    fn cycle_focus_forward(&mut self) {
        let order = self.focus_order();
        let index = order.iter().position(|focus| *focus == self.focus).unwrap_or(0);
        let next = (index + 1) % order.len();
        self.focus = order[next];
    }

    fn cycle_focus_backward(&mut self) {
        let order = self.focus_order();
        let index = order.iter().position(|focus| *focus == self.focus).unwrap_or(0);
        let next = (index + order.len() - 1) % order.len();
        self.focus = order[next];
    }

    fn move_sidebar_up(&mut self) -> bool {
        if self.current_selection() == 0 {
            false
        } else {
            *self.current_selection_mut() -= 1;
            true
        }
    }

    fn move_sidebar_down(&mut self) -> bool {
        let next = self.current_selection() + 1;
        if next >= self.sidebar_len() {
            false
        } else {
            *self.current_selection_mut() = next;
            true
        }
    }

    fn focus_is(&self, focus: Focus) -> bool {
        self.focus == focus
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
        self.clamp_selection_state();
        Ok(())
    }

    fn clamp_selection_state(&mut self) {
        let sidebar_len = self.sidebar_len();
        if self.current_selection() >= sidebar_len {
            *self.current_selection_mut() = sidebar_len.saturating_sub(1);
        }

        self.selected_update = min(self.selected_update, UPDATE_ACTIONS.len().saturating_sub(1));

        if self.snapshot.ssh_keys.is_empty() {
            self.selected_key = 0;
        } else if self.selected_key >= self.snapshot.ssh_keys.len() {
            self.selected_key = self.snapshot.ssh_keys.len() - 1;
        }

        let alert_count = self.alerts().len();
        if alert_count == 0 {
            self.selected_alert = 0;
        } else if self.selected_alert >= alert_count {
            self.selected_alert = alert_count - 1;
        }

        let filtered_count = self.filtered_logs().len();
        if filtered_count == 0 {
            self.log_scroll = 0;
        } else {
            self.log_scroll = min(self.log_scroll, filtered_count.saturating_sub(1));
        }

        self.ensure_focus_valid();
    }

    fn push_log(&mut self, message: impl Into<String>) {
        self.logs.push(message.into());
        if self.logs.len() > MAX_LOG_ENTRIES {
            let drain = self.logs.len() - MAX_LOG_ENTRIES;
            self.logs.drain(0..drain);
        }
        self.clamp_selection_state();
    }

    fn alerts(&self) -> Vec<AlertItem> {
        let mut alerts = Vec::new();

        if self.snapshot.dirty_count > 0 {
            alerts.push(AlertItem {
                severity: Severity::Warning,
                message: format!(
                    "{} tracked repository changes are still uncommitted.",
                    self.snapshot.dirty_count
                ),
                action_label: Some("Open Logs"),
                action: Some(AlertCommand::OpenLogs),
            });
        }

        if self.snapshot.rebuild_needed {
            alerts.push(AlertItem {
                severity: Severity::Warning,
                message: "Current repository state has not been switched onto the host.".to_string(),
                action_label: Some("Apply now"),
                action: Some(AlertCommand::ApplyConfiguration),
            });
        }

        if self.snapshot.rebuild_queued {
            alerts.push(AlertItem {
                severity: Severity::Info,
                message: "A rebuild has been queued for the next boot.".to_string(),
                action_label: Some("Maintenance"),
                action: Some(AlertCommand::OpenMaintenance),
            });
        }

        if self.snapshot.behind > 0 {
            alerts.push(AlertItem {
                severity: Severity::Warning,
                message: format!(
                    "Local branch is behind {} by {} commits.",
                    self.snapshot
                        .upstream
                        .clone()
                        .unwrap_or_else(|| "its upstream".to_string()),
                    self.snapshot.behind
                ),
                action_label: Some("Check updates"),
                action: Some(AlertCommand::CheckForUpdates),
            });
        }

        if self.snapshot.ahead > 0 {
            alerts.push(AlertItem {
                severity: Severity::Info,
                message: format!(
                    "Local branch is ahead of upstream by {} commits.",
                    self.snapshot.ahead
                ),
                action_label: Some("Open Logs"),
                action: Some(AlertCommand::OpenLogs),
            });
        }

        if self.snapshot.memory_used_percent >= 90 {
            alerts.push(AlertItem {
                severity: Severity::Error,
                message: format!(
                    "RAM usage is high: {}.",
                    format_usage(
                        self.snapshot.memory_used_bytes,
                        self.snapshot.memory_total_bytes,
                        self.snapshot.memory_used_percent
                    )
                ),
                action_label: None,
                action: None,
            });
        } else if self.snapshot.memory_used_percent >= 75 {
            alerts.push(AlertItem {
                severity: Severity::Warning,
                message: format!(
                    "RAM usage is elevated: {}.",
                    format_usage(
                        self.snapshot.memory_used_bytes,
                        self.snapshot.memory_total_bytes,
                        self.snapshot.memory_used_percent
                    )
                ),
                action_label: None,
                action: None,
            });
        }

        if self.snapshot.storage_used_percent >= 90 {
            alerts.push(AlertItem {
                severity: Severity::Error,
                message: format!(
                    "Root storage usage is high: {}.",
                    format_usage(
                        self.snapshot.storage_used_bytes,
                        self.snapshot.storage_total_bytes,
                        self.snapshot.storage_used_percent
                    )
                ),
                action_label: None,
                action: None,
            });
        } else if self.snapshot.storage_used_percent >= 75 {
            alerts.push(AlertItem {
                severity: Severity::Warning,
                message: format!(
                    "Root storage usage is elevated: {}.",
                    format_usage(
                        self.snapshot.storage_used_bytes,
                        self.snapshot.storage_total_bytes,
                        self.snapshot.storage_used_percent
                    )
                ),
                action_label: None,
                action: None,
            });
        }

        if self.snapshot.primary_ip.is_none() {
            alerts.push(AlertItem {
                severity: Severity::Warning,
                message: "No primary IPv4 address was detected.".to_string(),
                action_label: None,
                action: None,
            });
        }

        match &self.update_status {
            UpdateStatus::Available(count) => alerts.push(AlertItem {
                severity: Severity::Info,
                message: format!("{count} flake input lock entries can be updated."),
                action_label: Some("Check updates"),
                action: Some(AlertCommand::CheckForUpdates),
            }),
            UpdateStatus::Error(message) => alerts.push(AlertItem {
                severity: Severity::Error,
                message: format!("Flake input check failed: {message}"),
                action_label: Some("Check updates"),
                action: Some(AlertCommand::CheckForUpdates),
            }),
            UpdateStatus::Idle | UpdateStatus::Checking | UpdateStatus::UpToDate => {}
        }

        if let Some(last_apply) = &self.snapshot.last_apply {
            if last_apply.result != "success" {
                alerts.push(AlertItem {
                    severity: Severity::Error,
                    message: format!(
                        "Last {} failed at {} with exit code {}.",
                        last_apply.action, last_apply.timestamp, last_apply.exit_code
                    ),
                    action_label: Some("Open Logs"),
                    action: Some(AlertCommand::OpenLogs),
                });
            }
        } else {
            alerts.push(AlertItem {
                severity: Severity::Warning,
                message: "No successful host switch has been recorded yet.".to_string(),
                action_label: Some("Apply now"),
                action: Some(AlertCommand::ApplyConfiguration),
            });
        }

        if alerts.is_empty() {
            alerts.push(AlertItem {
                severity: Severity::Info,
                message: "No outstanding alerts.".to_string(),
                action_label: None,
                action: None,
            });
        }

        alerts
    }

    fn filtered_logs(&self) -> Vec<String> {
        let query = self.log_filter.trim().to_lowercase();
        let iter = self.logs.iter().rev();
        if query.is_empty() {
            iter.cloned().collect()
        } else {
            iter.filter(|line| line.to_lowercase().contains(&query))
                .cloned()
                .collect()
        }
    }

    fn recent_logs(&self) -> Vec<String> {
        let mut logs = self.filtered_logs();
        logs.truncate(DASHBOARD_LOG_LINES);
        logs
    }

    fn palette_entries(&self) -> Vec<PaletteEntry> {
        let mut entries = vec![
            PaletteEntry {
                title: "Go to Dashboard".to_string(),
                detail: "Switch to the Dashboard page.".to_string(),
                action: PaletteAction::SwitchPage(Page::Dashboard),
            },
            PaletteEntry {
                title: "Go to Configure".to_string(),
                detail: "Switch to the Configure page.".to_string(),
                action: PaletteAction::SwitchPage(Page::Configure),
            },
            PaletteEntry {
                title: "Go to Software".to_string(),
                detail: "Switch to the Software page.".to_string(),
                action: PaletteAction::SwitchPage(Page::Software),
            },
            PaletteEntry {
                title: "Go to Maintenance".to_string(),
                detail: "Switch to the Maintenance page.".to_string(),
                action: PaletteAction::SwitchPage(Page::Maintenance),
            },
            PaletteEntry {
                title: "Go to Logs".to_string(),
                detail: "Switch to the Logs page.".to_string(),
                action: PaletteAction::SwitchPage(Page::Logs),
            },
            PaletteEntry {
                title: "Open Help".to_string(),
                detail: "Show the full shortcut and navigation reference.".to_string(),
                action: PaletteAction::OpenHelp,
            },
            PaletteEntry {
                title: "Open Shell".to_string(),
                detail: "Leave the TUI and exec the configured login shell.".to_string(),
                action: PaletteAction::OpenShell,
            },
        ];

        for page in [
            Page::Dashboard,
            Page::Configure,
            Page::Software,
            Page::Maintenance,
            Page::Logs,
        ] {
            for action in page_actions(page) {
                entries.push(PaletteEntry {
                    title: format!("{} / {}", page_label(page), action.title),
                    detail: action.detail.to_string(),
                    action: PaletteAction::RunAction(action.kind),
                });
            }
        }

        let query = self
            .command_palette
            .as_ref()
            .map(|palette| palette.query.trim().to_lowercase())
            .unwrap_or_default();

        if query.is_empty() {
            entries
        } else {
            entries
                .into_iter()
                .filter(|entry| {
                    entry.title.to_lowercase().contains(&query)
                        || entry.detail.to_lowercase().contains(&query)
                })
                .collect()
        }
    }
}

fn page_actions(page: Page) -> &'static [ActionItem] {
    match page {
        Page::Dashboard => &DASHBOARD_ACTIONS,
        Page::Configure => &CONFIGURE_ACTIONS,
        Page::Software => &SOFTWARE_ACTIONS,
        Page::Maintenance => &MAINTENANCE_ACTIONS,
        Page::Logs => &LOG_ACTIONS,
    }
}

fn page_label(page: Page) -> &'static str {
    match page {
        Page::Dashboard => "Dashboard",
        Page::Configure => "Configure",
        Page::Software => "Software",
        Page::Maintenance => "Maintenance",
        Page::Logs => "Logs",
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
    if app.command_palette.is_some() {
        return handle_palette_key(app, key);
    }
    if app.help_open {
        return handle_help_key(app, key);
    }
    if app.modal.is_some() {
        return handle_modal_key(app, key);
    }
    if app.quit_confirm {
        return handle_quit_confirm_key(app, key);
    }

    if key.modifiers.contains(KeyModifiers::CONTROL) && matches!(key.code, KeyCode::Char('p')) {
        app.command_palette = Some(CommandPalette {
            query: String::new(),
            selected: 0,
        });
        return Ok(());
    }

    match key.code {
        KeyCode::Char(':') => {
            app.command_palette = Some(CommandPalette {
                query: String::new(),
                selected: 0,
            });
            return Ok(());
        }
        KeyCode::Char('?') => {
            app.help_open = true;
            return Ok(());
        }
        KeyCode::Char('q') | KeyCode::Char('9') => {
            app.should_open_shell = true;
            return Ok(());
        }
        KeyCode::Esc => {
            if let Some(parent) = app.parent_focus() {
                app.focus = parent;
            } else if app.focus == Focus::TopNav {
                app.focus = Focus::MainActions;
            } else if app.focus == Focus::MainActions {
                app.quit_confirm = true;
            }
            return Ok(());
        }
        KeyCode::Char('r') => {
            app.refresh_snapshot()?;
            app.start_update_check();
            app.push_log("Refreshed repository snapshot.");
            return Ok(());
        }
        KeyCode::Char('u') => {
            app.start_update_check();
            app.push_log("Started a new flake input update check.");
            return Ok(());
        }
        KeyCode::Tab => {
            app.cycle_focus_forward();
            return Ok(());
        }
        KeyCode::BackTab => {
            app.cycle_focus_backward();
            return Ok(());
        }
        KeyCode::Char('[') => {
            app.previous_page();
            return Ok(());
        }
        KeyCode::Char(']') => {
            app.next_page();
            return Ok(());
        }
        _ => {}
    }

    match app.focus {
        Focus::TopNav => handle_top_nav_key(app, key),
        Focus::MainActions => handle_main_actions_key(terminal, app, key),
        Focus::DashboardAlerts => handle_dashboard_alerts_key(terminal, app, key),
        Focus::ConfigureSshKeys => handle_configure_ssh_keys_key(app, key),
        Focus::MaintenanceFlakeInputs => handle_maintenance_flake_inputs_key(terminal, app, key),
        Focus::LogsView => handle_logs_view_key(app, key),
    }
}

fn handle_top_nav_key(app: &mut App, key: KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Left | KeyCode::Char('h') => app.previous_page(),
        KeyCode::Right | KeyCode::Char('l') => app.next_page(),
        KeyCode::Down | KeyCode::Char('j') => app.focus = Focus::MainActions,
        _ => {}
    }
    Ok(())
}

fn handle_main_actions_key(terminal: &mut AppTerminal, app: &mut App, key: KeyEvent) -> Result<()> {
    if let KeyCode::Char(ch) = key.code {
        if ch == '9' || ch == 'q' {
            app.should_open_shell = true;
            return Ok(());
        }

        if let Some(index) = app
            .current_page_actions()
            .iter()
            .position(|item| item.shortcut == Some(ch))
        {
            *app.current_selection_mut() = index;
            activate_sidebar_selection(terminal, app)?;
            return Ok(());
        }
    }

    match key.code {
        KeyCode::Up | KeyCode::Char('k') => {
            if !app.move_sidebar_up() {
                app.focus = Focus::TopNav;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            let _ = app.move_sidebar_down();
        }
        KeyCode::Right | KeyCode::Char('l') => {
            if let Some(child) = app.action_child_focus() {
                app.focus = child;
            }
        }
        KeyCode::Enter => activate_sidebar_selection(terminal, app)?,
        _ => {}
    }

    Ok(())
}

fn handle_dashboard_alerts_key(
    terminal: &mut AppTerminal,
    app: &mut App,
    key: KeyEvent,
) -> Result<()> {
    let alerts = app.alerts();
    match key.code {
        KeyCode::Left | KeyCode::Char('h') => app.focus = Focus::MainActions,
        KeyCode::Up | KeyCode::Char('k') => {
            if !alerts.is_empty() && app.selected_alert > 0 {
                app.selected_alert -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            if !alerts.is_empty() {
                app.selected_alert = min(app.selected_alert + 1, alerts.len() - 1);
            }
        }
        KeyCode::Enter => {
            if let Some(alert) = alerts.get(app.selected_alert) {
                if let Some(action) = alert.action {
                    run_alert_action(terminal, app, action)?;
                }
            }
        }
        _ => {}
    }
    Ok(())
}

fn handle_configure_ssh_keys_key(app: &mut App, key: KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Left | KeyCode::Char('h') => app.focus = Focus::MainActions,
        KeyCode::Up | KeyCode::Char('k') => {
            if !app.snapshot.ssh_keys.is_empty() && app.selected_key > 0 {
                app.selected_key -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            if !app.snapshot.ssh_keys.is_empty() {
                app.selected_key = min(app.selected_key + 1, app.snapshot.ssh_keys.len() - 1);
            }
        }
        KeyCode::Char('a') => open_modal(
            app,
            InputAction::AddKey,
            "Add SSH key",
            "Paste a full public key line.",
            "",
        ),
        KeyCode::Char('e') => open_modal(
            app,
            InputAction::SetPrimaryKey,
            "Replace SSH keys",
            "Replace the managed key list with a single public key line.",
            "",
        ),
        KeyCode::Delete | KeyCode::Backspace | KeyCode::Char('d') => {
            if let Some(selected_key) = app.snapshot.ssh_keys.get(app.selected_key).cloned() {
                run_action_capture(app, &["remove-ssh-key", selected_key.as_str()])?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn handle_maintenance_flake_inputs_key(
    terminal: &mut AppTerminal,
    app: &mut App,
    key: KeyEvent,
) -> Result<()> {
    match key.code {
        KeyCode::Left | KeyCode::Char('h') => app.focus = Focus::MainActions,
        KeyCode::Up | KeyCode::Char('k') => {
            if app.selected_update > 0 {
                app.selected_update -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            app.selected_update = min(app.selected_update + 1, UPDATE_ACTIONS.len() - 1);
        }
        KeyCode::Enter => activate_selected_update(terminal, app)?,
        KeyCode::Char(ch) => {
            if let Some(index) = UPDATE_ACTIONS.iter().position(|item| item.shortcut == ch) {
                app.selected_update = index;
                activate_selected_update(terminal, app)?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn handle_logs_view_key(app: &mut App, key: KeyEvent) -> Result<()> {
    let total = app.filtered_logs().len();
    match key.code {
        KeyCode::Left | KeyCode::Char('h') => app.focus = Focus::MainActions,
        KeyCode::Up | KeyCode::Char('k') => {
            if total > 0 && app.log_scroll < total.saturating_sub(1) {
                app.log_scroll = min(app.log_scroll + 1, total.saturating_sub(1));
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            app.log_scroll = app.log_scroll.saturating_sub(1);
        }
        KeyCode::PageUp => {
            if total > 0 {
                app.log_scroll = min(app.log_scroll + 10, total.saturating_sub(1));
            }
        }
        KeyCode::PageDown => {
            app.log_scroll = app.log_scroll.saturating_sub(10);
        }
        KeyCode::Home => {
            if total > 0 {
                app.log_scroll = total - 1;
            }
        }
        KeyCode::End => app.log_scroll = 0,
        KeyCode::Char('/') => {
            let current = app.log_filter.clone();
            open_modal(
                app,
                InputAction::SetLogFilter,
                "Filter logs",
                "Enter a substring to filter Recent Activity entries.",
                current.as_str(),
            )
        }
        KeyCode::Char('c') => {
            app.log_filter.clear();
            app.log_scroll = 0;
            app.push_log("Cleared log filter.");
        }
        _ => {}
    }
    Ok(())
}

fn handle_modal_key(app: &mut App, key: KeyEvent) -> Result<()> {
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
        KeyCode::Char(ch) => modal.value.push(ch),
        _ => {}
    }
    Ok(())
}

fn handle_quit_confirm_key(app: &mut App, key: KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Esc | KeyCode::Char('n') | KeyCode::Char('N') => app.quit_confirm = false,
        KeyCode::Char('y') | KeyCode::Char('Y') => {
            app.quit_confirm = false;
            app.should_quit = true;
        }
        _ => {}
    }
    Ok(())
}

fn handle_help_key(app: &mut App, key: KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Esc | KeyCode::Char('?') => app.help_open = false,
        _ => {}
    }
    Ok(())
}

fn handle_palette_key(app: &mut App, key: KeyEvent) -> Result<()> {
    match key.code {
        KeyCode::Esc => app.command_palette = None,
        KeyCode::Backspace => {
            let palette = app.command_palette.as_mut().expect("palette checked above");
            palette.query.pop();
            palette.selected = 0;
        }
        KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
            let palette = app.command_palette.as_mut().expect("palette checked above");
            palette.query.clear();
            palette.selected = 0;
        }
        KeyCode::Up | KeyCode::Char('k') => {
            let len = app.palette_entries().len();
            if len > 0 {
                let palette = app.command_palette.as_mut().expect("palette checked above");
                if palette.selected == 0 {
                    palette.selected = len - 1;
                } else {
                    palette.selected -= 1;
                }
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            let len = app.palette_entries().len();
            if len > 0 {
                let palette = app.command_palette.as_mut().expect("palette checked above");
                palette.selected = (palette.selected + 1) % len;
            }
        }
        KeyCode::Enter => {
            let entries = app.palette_entries();
            let selected = app
                .command_palette
                .as_ref()
                .map(|palette| palette.selected)
                .unwrap_or(0);
            let action = entries.get(selected).map(|entry| entry.action.clone());
            app.command_palette = None;
            if let Some(action) = action {
                run_palette_action(app, action)?;
            }
        }
        KeyCode::Char(ch) => {
            let palette = app.command_palette.as_mut().expect("palette checked above");
            palette.query.push(ch);
            palette.selected = 0;
        }
        _ => {}
    }
    Ok(())
}

fn run_palette_action(app: &mut App, action: PaletteAction) -> Result<()> {
    match action {
        PaletteAction::SwitchPage(page) => app.set_page(page),
        PaletteAction::RunAction(kind) => run_quick_action(app, kind)?,
        PaletteAction::OpenShell => app.should_open_shell = true,
        PaletteAction::OpenHelp => app.help_open = true,
    }
    Ok(())
}

fn run_alert_action(terminal: &mut AppTerminal, app: &mut App, action: AlertCommand) -> Result<()> {
    match action {
        AlertCommand::OpenMaintenance => {
            app.set_page(Page::Maintenance);
            *app.current_selection_mut() = 0;
            app.set_focus(Focus::MainActions);
        }
        AlertCommand::CheckForUpdates => {
            app.set_page(Page::Maintenance);
            *app.current_selection_mut() = 0;
            app.set_focus(Focus::MaintenanceFlakeInputs);
            app.start_update_check();
        }
        AlertCommand::ApplyConfiguration => {
            app.set_page(Page::Maintenance);
            *app.current_selection_mut() = 1;
            run_apply_configuration(terminal, app)?;
        }
        AlertCommand::OpenLogs => {
            app.set_page(Page::Logs);
            app.set_focus(Focus::LogsView);
        }
    }
    Ok(())
}

fn run_quick_action(app: &mut App, kind: ActionKind) -> Result<()> {
    match kind {
        ActionKind::RefreshSnapshot => {
            app.refresh_snapshot()?;
            app.start_update_check();
            app.push_log("Refreshed repository snapshot.");
        }
        ActionKind::CheckForUpdates => {
            app.set_page(Page::Maintenance);
            *app.current_selection_mut() = 0;
            app.set_focus(Focus::MaintenanceFlakeInputs);
            app.start_update_check();
            app.push_log("Opened Flake Inputs update view.");
        }
        ActionKind::EditHostname => {
            let current = app.snapshot.hostname.clone();
            open_modal(
                app,
                InputAction::SetHostname,
                "Edit hostname",
                "Press Enter to write and commit the new hostname.",
                current.as_str(),
            );
        }
        ActionKind::EditUsername => {
            let current = app.snapshot.username.clone();
            open_modal(
                app,
                InputAction::SetUsername,
                "Edit username",
                "Press Enter to write and commit the new username.",
                current.as_str(),
            );
        }
        ActionKind::ToggleExtras => run_action_capture(app, &["toggle-extras"])?,
        ActionKind::ManageSshKeys => {
            app.set_page(Page::Configure);
            *app.current_selection_mut() = 3;
            app.set_focus(Focus::ConfigureSshKeys);
        }
        ActionKind::AddSystemPackage => open_modal(
            app,
            InputAction::AddSystemPackage,
            "Add system package",
            "Enter a nixpkgs attribute path such as tailscale or unstable.myPkg.",
            "",
        ),
        ActionKind::AddUserPackage => open_modal(
            app,
            InputAction::AddUserPackage,
            "Add user package",
            "Enter a nixpkgs attribute path for the user package list.",
            "",
        ),
        ActionKind::AddService => open_modal(
            app,
            InputAction::AddService,
            "Add service",
            "Enter a dotted NixOS service path such as tailscale or prometheus.exporters.node.",
            "",
        ),
        ActionKind::ApplyConfiguration
        | ActionKind::RollbackGeneration
        | ActionKind::RunGarbageCollection
        | ActionKind::RebootSystem
        | ActionKind::ShutdownSystem
        | ActionKind::CleanupUnmanagedUsers => {
            app.set_page(Page::Maintenance);
        }
        ActionKind::FilterLogs => {
            app.set_page(Page::Logs);
            let current = app.log_filter.clone();
            open_modal(
                app,
                InputAction::SetLogFilter,
                "Filter logs",
                "Enter a substring to filter Recent Activity entries.",
                current.as_str(),
            );
        }
        ActionKind::ClearLogFilter => {
            app.log_filter.clear();
            app.log_scroll = 0;
            app.push_log("Cleared log filter.");
        }
    }
    Ok(())
}

fn activate_sidebar_selection(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    if let Some(action) = app.selected_page_action() {
        match action.kind {
            ActionKind::RefreshSnapshot => {
                app.refresh_snapshot()?;
                app.start_update_check();
                app.push_log("Refreshed repository snapshot.");
            }
            ActionKind::CheckForUpdates => {
                app.start_update_check();
                app.set_page(Page::Maintenance);
                *app.current_selection_mut() = 0;
                app.set_focus(Focus::MaintenanceFlakeInputs);
            }
            ActionKind::EditHostname => {
                let current = app.snapshot.hostname.clone();
                open_modal(
                    app,
                    InputAction::SetHostname,
                    "Edit hostname",
                    "Press Enter to write and commit the new hostname.",
                    current.as_str(),
                );
            }
            ActionKind::EditUsername => {
                let current = app.snapshot.username.clone();
                open_modal(
                    app,
                    InputAction::SetUsername,
                    "Edit username",
                    "Press Enter to write and commit the new username.",
                    current.as_str(),
                );
            }
            ActionKind::ToggleExtras => run_action_capture(app, &["toggle-extras"])?,
            ActionKind::ManageSshKeys => app.set_focus(Focus::ConfigureSshKeys),
            ActionKind::AddSystemPackage => open_modal(
                app,
                InputAction::AddSystemPackage,
                "Add system package",
                "Enter a nixpkgs attribute path such as tailscale or unstable.myPkg.",
                "",
            ),
            ActionKind::AddUserPackage => open_modal(
                app,
                InputAction::AddUserPackage,
                "Add user package",
                "Enter a nixpkgs attribute path for the user package list.",
                "",
            ),
            ActionKind::AddService => open_modal(
                app,
                InputAction::AddService,
                "Add service",
                "Enter a dotted NixOS service path such as tailscale or prometheus.exporters.node.",
                "",
            ),
            ActionKind::ApplyConfiguration => run_apply_configuration(terminal, app)?,
            ActionKind::RollbackGeneration => run_rollback_generation(terminal, app)?,
            ActionKind::RunGarbageCollection => run_garbage_collection(terminal, app)?,
            ActionKind::RebootSystem => run_reboot_system(terminal, app)?,
            ActionKind::ShutdownSystem => run_shutdown_system(terminal, app)?,
            ActionKind::CleanupUnmanagedUsers => open_modal(
                app,
                InputAction::ConfirmCleanupUnmanagedUsers,
                "Cleanup unmanaged users",
                "Type WIPE to remove unmanaged users under /home and delete their home data.",
                "",
            ),
            ActionKind::FilterLogs => {
                let current = app.log_filter.clone();
                open_modal(
                    app,
                    InputAction::SetLogFilter,
                    "Filter logs",
                    "Enter a substring to filter Recent Activity entries.",
                    current.as_str(),
                )
            }
            ActionKind::ClearLogFilter => {
                app.log_filter.clear();
                app.log_scroll = 0;
                app.push_log("Cleared log filter.");
            }
        }
    } else {
        app.should_open_shell = true;
    }
    Ok(())
}

fn submit_modal(app: &mut App, action: InputAction, value: String) -> Result<()> {
    match action {
        InputAction::SetHostname => {
            if value.is_empty() {
                app.push_log("Ignored empty hostname.");
            } else {
                run_action_capture(app, &["set-hostname", value.as_str()])?;
            }
        }
        InputAction::SetUsername => {
            if value.is_empty() {
                app.push_log("Ignored empty username.");
            } else {
                run_action_capture(app, &["set-username", value.as_str()])?;
            }
        }
        InputAction::SetPrimaryKey => {
            if value.is_empty() {
                app.push_log("Ignored empty SSH key.");
            } else {
                run_action_capture(app, &["set-ssh-key", value.as_str()])?;
                app.set_page(Page::Configure);
                *app.current_selection_mut() = 3;
                app.set_focus(Focus::ConfigureSshKeys);
            }
        }
        InputAction::AddKey => {
            if value.is_empty() {
                app.push_log("Ignored empty SSH key.");
            } else {
                run_action_capture(app, &["add-ssh-key", value.as_str()])?;
                app.set_page(Page::Configure);
                *app.current_selection_mut() = 3;
                app.set_focus(Focus::ConfigureSshKeys);
            }
        }
        InputAction::AddSystemPackage => {
            if value.is_empty() {
                app.push_log("Ignored empty package path.");
            } else {
                run_action_capture(app, &["add-system-package", value.as_str()])?;
                app.set_page(Page::Software);
                *app.current_selection_mut() = 0;
            }
        }
        InputAction::AddUserPackage => {
            if value.is_empty() {
                app.push_log("Ignored empty package path.");
            } else {
                run_action_capture(app, &["add-user-package", value.as_str()])?;
                app.set_page(Page::Software);
                *app.current_selection_mut() = 1;
            }
        }
        InputAction::AddService => {
            if value.is_empty() {
                app.push_log("Ignored empty service path.");
            } else {
                run_action_capture(app, &["add-service", value.as_str()])?;
                app.set_page(Page::Software);
                *app.current_selection_mut() = 2;
            }
        }
        InputAction::ConfirmCleanupUnmanagedUsers => {
            if value == "WIPE" {
                run_action_capture(app, &["cleanup-unmanaged-users"])?;
                app.set_page(Page::Maintenance);
                *app.current_selection_mut() = 6;
            } else {
                app.push_log("Cleanup canceled. Type WIPE to confirm unmanaged-user removal.");
            }
        }
        InputAction::SetLogFilter => {
            app.log_filter = value;
            app.log_scroll = 0;
            app.set_page(Page::Logs);
            app.set_focus(Focus::LogsView);
            if app.log_filter.is_empty() {
                app.push_log("Cleared log filter.");
            } else {
                app.push_log(format!("Set log filter to `{}`.", app.log_filter));
            }
        }
    }
    Ok(())
}

fn activate_selected_update(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    let update = &UPDATE_ACTIONS[app.selected_update];
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

fn run_apply_configuration(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    run_command_interactive(terminal, app, "Apply Configuration", {
        let mut command = Command::new(app.repo_root.join("scripts/apply-config.sh"));
        command.args(["--hostname", app.snapshot.hostname.as_str()]);
        command
    })
}

fn run_rollback_generation(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    run_command_interactive(terminal, app, "Rollback Generation", {
        let mut command = Command::new(app.repo_root.join("scripts/apply-config.sh"));
        command.arg("--rollback");
        command
    })
}

fn run_garbage_collection(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    run_command_interactive(terminal, app, "Run Garbage Collection", {
        let mut command = sudo_command();
        command.args(["nix-collect-garbage", "-d"]);
        command
    })
}

fn run_reboot_system(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    run_command_interactive(terminal, app, "Reboot System", {
        let mut command = sudo_command();
        command.args(["systemctl", "reboot"]);
        command
    })
}

fn run_shutdown_system(terminal: &mut AppTerminal, app: &mut App) -> Result<()> {
    run_command_interactive(terminal, app, "Shut Down System", {
        let mut command = sudo_command();
        command.args(["systemctl", "poweroff"]);
        command
    })
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
        COLOR_DANGER
    } else if percent >= 75 {
        COLOR_WARNING
    } else {
        COLOR_SUCCESS
    }
}

fn repo_status(snapshot: &Snapshot) -> (String, Color) {
    if snapshot.dirty_count == 0 {
        ("clean".to_string(), COLOR_SUCCESS)
    } else {
        (format!("{} dirty", snapshot.dirty_count), COLOR_WARNING)
    }
}

fn apply_status(snapshot: &Snapshot) -> (String, Color) {
    if snapshot.rebuild_queued {
        ("queued for reboot".to_string(), COLOR_INFO)
    } else {
        match &snapshot.last_apply {
            Some(last_apply)
                if last_apply.result == "success"
                    && last_apply.action == "switch"
                    && !snapshot.rebuild_needed =>
            {
                (format!("synced {}", last_apply.timestamp), COLOR_SUCCESS)
            }
            Some(last_apply) if last_apply.result != "success" => {
                (format!("failed {}", last_apply.timestamp), COLOR_DANGER)
            }
            Some(last_apply) => (
                format!("{} {}", last_apply.action, last_apply.timestamp),
                COLOR_WARNING,
            ),
            None => ("not applied".to_string(), COLOR_WARNING),
        }
    }
}

fn upstream_status(snapshot: &Snapshot) -> (String, Color) {
    if snapshot.behind > 0 {
        (
            format!("behind {} / ahead {}", snapshot.behind, snapshot.ahead),
            COLOR_WARNING,
        )
    } else if snapshot.ahead > 0 {
        (format!("ahead {}", snapshot.ahead), COLOR_INFO)
    } else {
        ("aligned".to_string(), COLOR_SUCCESS)
    }
}

fn inputs_status(update_status: &UpdateStatus, tick: usize) -> (String, Color) {
    match update_status {
        UpdateStatus::Idle => ("idle".to_string(), COLOR_MUTED_2),
        UpdateStatus::Checking => {
            let frames = ["-", "\\", "|", "/"];
            (
                format!("checking {}", frames[tick % frames.len()]),
                COLOR_INFO,
            )
        }
        UpdateStatus::UpToDate => ("up to date".to_string(), COLOR_SUCCESS),
        UpdateStatus::Available(count) => (format!("{count} updates"), COLOR_WARNING),
        UpdateStatus::Error(_) => ("check failed".to_string(), COLOR_DANGER),
    }
}

fn xoa_version(snapshot: &Snapshot) -> String {
    snapshot
        .xen_orchestra_version
        .clone()
        .unwrap_or_else(|| "unavailable".to_string())
}

fn web_ui(snapshot: &Snapshot) -> String {
    snapshot
        .web_ui_url
        .clone()
        .or_else(|| snapshot.primary_ip.clone())
        .unwrap_or_else(|| "unavailable".to_string())
}

fn format_storage_capacity(used_bytes: u64, total_bytes: u64) -> String {
    if total_bytes == 0 || used_bytes > total_bytes {
        "unavailable".to_string()
    } else {
        format!("{:.1} / {:.1}", format_gib(used_bytes), format_gib(total_bytes))
    }
}

#[derive(Clone, Copy)]
enum PanelTone {
    Neutral,
    Info,
    Warning,
    Danger,
}

fn panel_color(tone: PanelTone, focused: bool) -> Color {
    if focused {
        match tone {
            PanelTone::Neutral | PanelTone::Info => COLOR_ACCENT,
            PanelTone::Warning => COLOR_WARNING,
            PanelTone::Danger => COLOR_DANGER,
        }
    } else {
        match tone {
            PanelTone::Neutral => COLOR_BORDER_DIM,
            PanelTone::Info | PanelTone::Warning => COLOR_BORDER_MID,
            PanelTone::Danger => COLOR_DANGER,
        }
    }
}

fn panel_block(title: impl Into<String>, focused: bool, tone: PanelTone) -> Block<'static> {
    Block::default()
        .title(
            Line::from(format!(" {} ", title.into()))
                .style(Style::default().fg(COLOR_FG_MAIN).add_modifier(Modifier::BOLD)),
        )
        .borders(Borders::ALL)
        .border_set(border::ROUNDED)
        .border_style(Style::default().fg(panel_color(tone, focused)))
        .border_type(BorderType::Rounded)
        .style(Style::default().bg(COLOR_BG_INNER))
}

fn action_row_width(actions: &[ActionItem]) -> u16 {
    let max_label = actions
        .iter()
        .map(|action| action.title.chars().count() + 6)
        .max()
        .unwrap_or(16);
    (max_label as u16).saturating_add(6)
}

fn inset_rect(area: Rect, x: u16, y: u16) -> Rect {
    let width = area.width.saturating_sub(x.saturating_mul(2));
    let height = area.height.saturating_sub(y.saturating_mul(2));
    Rect {
        x: area.x.saturating_add(x),
        y: area.y.saturating_add(y),
        width,
        height,
    }
}

fn draw_panel(
    frame: &mut Frame,
    area: Rect,
    title: impl Into<String>,
    focused: bool,
    tone: PanelTone,
) -> Rect {
    let block = panel_block(title, focused, tone);
    let inner = inset_rect(block.inner(area), 1, 0);
    frame.render_widget(block, area);
    inner
}

fn render(frame: &mut Frame, app: &App) {
    let area = frame.area();
    frame.render_widget(Block::default().style(Style::default().bg(COLOR_BG_OUTER)), area);

    let outer = inset_rect(area, 1, 1);
    if outer.width < 80 || outer.height < 22 {
        render_too_small(frame, outer, app);
        if let Some(modal) = &app.modal {
            render_input_modal(frame, outer, modal);
        }
        if let Some(_) = &app.command_palette {
            render_command_palette(frame, outer, app);
        }
        if app.help_open {
            render_help_modal(frame, outer, app);
        }
        if app.quit_confirm {
            render_quit_confirm(frame, outer);
        }
        return;
    }

    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(7),
            Constraint::Length(3),
            Constraint::Min(10),
            Constraint::Length(4),
        ])
        .split(outer);

    render_header(frame, vertical[0], app);
    render_tabs(frame, vertical[1], app);

    let body = if app.page == Page::Maintenance {
        let sidebar_width = action_row_width(&MAINTENANCE_ACTIONS);
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Length(sidebar_width),
                Constraint::Length(1),
                Constraint::Min(40),
            ])
            .split(vertical[2])
    } else if outer.width >= 120 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Length(33), Constraint::Min(40)])
            .split(vertical[2])
    } else {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Length(29), Constraint::Min(30)])
            .split(vertical[2])
    };

    let sidebar_area = body[0];
    let page_area = if app.page == Page::Maintenance { body[2] } else { body[1] };

    render_sidebar(frame, inset_rect(sidebar_area, 0, 0), app);
    render_page(frame, inset_rect(page_area, 0, 0), app);
    render_footer(frame, vertical[3], app);

    if let Some(modal) = &app.modal {
        render_input_modal(frame, outer, modal);
    }
    if app.command_palette.is_some() {
        render_command_palette(frame, outer, app);
    }
    if app.help_open {
        render_help_modal(frame, outer, app);
    }
    if app.quit_confirm {
        render_quit_confirm(frame, outer);
    }
}

fn render_too_small(frame: &mut Frame, area: Rect, app: &App) {
    let inner = draw_panel(
        frame,
        area,
        "NiXOA Console",
        true,
        PanelTone::Info,
    );
    let text = vec![
        Line::from(vec![
            Span::styled("Host: ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled(
                format!("{}@{}", app.snapshot.username, app.snapshot.hostname),
                Style::default().fg(COLOR_FG_MAIN),
            ),
        ]),
        Line::from(vec![
            Span::styled("Page: ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled(app.page_title(), Style::default().fg(COLOR_ACCENT)),
        ]),
        Line::from(""),
        Line::from("Increase terminal size for the full multi-pane console."),
        Line::from("Esc unwinds to the main menu. Esc on the main menu prompts to quit."),
    ];

    let paragraph = Paragraph::new(text)
        .style(Style::default().bg(COLOR_BG_INNER).fg(COLOR_FG_MAIN))
        .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, inner);
}

fn render_header(frame: &mut Frame, area: Rect, app: &App) {
    let inner = draw_panel(frame, area, "NiXOA", false, PanelTone::Info);
    let sections = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Length(34), Constraint::Min(20)])
        .split(inner);

    let ascii = Paragraph::new(vec![
        Line::from(Span::styled(
            " _   _ _ __  __  ___    _   ",
            Style::default()
                .fg(COLOR_FG_MAIN)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(
            "| \\ | | |\\ \\/ / / _ \\  /_\\  ",
            Style::default().fg(COLOR_FG_MAIN),
        )),
        Line::from(Span::styled(
            "|  \\| | | >  < | | | |/ _ \\ ",
            Style::default().fg(COLOR_FG_MAIN),
        )),
        Line::from(Span::styled(
            "| |\\  | |/ /\\ \\| |_| / ___ \\",
            Style::default().fg(COLOR_FG_MAIN),
        )),
        Line::from(Span::styled(
            "|_| \\_|_/_/  \\_\\\\___/_/   \\_\\",
            Style::default().fg(COLOR_FG_MAIN),
        )),
    ]);
    frame.render_widget(ascii, sections[0]);

    let upstream = app
        .snapshot
        .upstream
        .clone()
        .unwrap_or_else(|| "no upstream".to_string());

    let summary = Paragraph::new(vec![
        Line::from(vec![
            Span::styled("Console ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled("appliance view", Style::default().fg(COLOR_FG_MAIN)),
        ]),
        Line::from(vec![
            Span::styled("Host: ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled(
                format!("{}@{}", app.snapshot.username, app.snapshot.hostname),
                Style::default().fg(COLOR_ACCENT),
            ),
        ]),
        Line::from(vec![
            Span::styled("Branch: ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled(
                format!("{} [{}]", app.snapshot.branch, short_sha(&app.snapshot.head)),
                Style::default().fg(COLOR_FG_MAIN),
            ),
            Span::styled("  Upstream: ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled(upstream, Style::default().fg(COLOR_INFO)),
        ]),
        Line::from(vec![
            Span::styled("Page: ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled(app.page_title(), Style::default().fg(COLOR_FG_MAIN)),
            Span::styled("  Focus: ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled(focus_label(app.focus), Style::default().fg(COLOR_ACCENT)),
        ]),
        Line::from(vec![
            Span::styled("Last event: ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled(
                app.logs
                    .last()
                    .cloned()
                    .unwrap_or_else(|| "NiXOA console ready.".to_string()),
                Style::default().fg(COLOR_MUTED),
            ),
        ]),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(summary, sections[1]);
}

fn render_tabs(frame: &mut Frame, area: Rect, app: &App) {
    let inner = draw_panel(
        frame,
        area,
        "Navigation",
        app.focus_is(Focus::TopNav),
        PanelTone::Neutral,
    );

    let mut spans = Vec::new();
    for page in [
        Page::Dashboard,
        Page::Configure,
        Page::Software,
        Page::Maintenance,
        Page::Logs,
    ] {
        if !spans.is_empty() {
            spans.push(Span::raw("  "));
        }
        let active = app.page == page;
        let style = if active {
            Style::default()
                .fg(COLOR_FG_MAIN)
                .bg(COLOR_ACCENT)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(COLOR_MUTED).bg(COLOR_BG_INNER)
        };
        spans.push(Span::styled(format!(" {} ", page_label(page)), style));
    }

    spans.push(Span::raw("   "));
    spans.push(Span::styled(
        "Left/Right or h/l pages  Down or j enters actions  Esc returns  [ ] pages",
        Style::default().fg(COLOR_MUTED),
    ));

    let paragraph = Paragraph::new(Line::from(spans))
        .alignment(Alignment::Left)
        .style(Style::default().bg(COLOR_BG_INNER));
    frame.render_widget(paragraph, inner);
}

fn render_sidebar(frame: &mut Frame, area: Rect, app: &App) {
    let inner = draw_panel(
        frame,
        area,
        format!("{} Actions", app.page_title()),
        app.focus_is(Focus::MainActions),
        PanelTone::Neutral,
    );

    let actions = app.current_page_actions();
    let mut items: Vec<ListItem> = actions
        .iter()
        .enumerate()
        .map(|(idx, action)| {
            let prefix = if idx == app.current_selection() { "›" } else { " " };
            let shortcut = action
                .shortcut
                .map(|ch| format!("[{ch}] "))
                .unwrap_or_default();
            ListItem::new(Line::from(vec![
                Span::styled(prefix, Style::default().fg(COLOR_ACCENT)),
                Span::raw(" "),
                Span::styled(shortcut, Style::default().fg(COLOR_MUTED_2)),
                Span::styled(action.title, Style::default().fg(COLOR_FG_MAIN)),
            ]))
        })
        .collect();

    items.push(ListItem::new(Line::from("")));
    let shell_prefix = if app.current_selection() == actions.len() {
        "›"
    } else {
        " "
    };
    items.push(ListItem::new(Line::from(vec![
        Span::styled(shell_prefix, Style::default().fg(COLOR_ACCENT)),
        Span::raw(" "),
        Span::styled("[9] ", Style::default().fg(COLOR_MUTED_2)),
        Span::styled("Open Shell", Style::default().fg(COLOR_FG_MAIN)),
    ])));

    let mut state = ListState::default();
    state.select(Some(if app.current_selection() >= actions.len() {
        actions.len() + 1
    } else {
        app.current_selection()
    }));

    let list = List::new(items).highlight_style(
        Style::default()
            .bg(COLOR_ACCENT_SOFT)
            .fg(COLOR_FG_MAIN)
            .add_modifier(Modifier::BOLD),
    );
    frame.render_stateful_widget(list, inner, &mut state);

    let detail_area = Rect {
        x: inner.x,
        y: inner.y.saturating_add(inner.height.saturating_sub(3)),
        width: inner.width,
        height: min(3, inner.height),
    };

    let detail = Paragraph::new(vec![
        Line::from(Span::styled(
            app.selected_sidebar_title(),
            Style::default()
                .fg(COLOR_FG_MAIN)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(
            app.selected_sidebar_detail(),
            Style::default().fg(COLOR_MUTED),
        )),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(Clear, detail_area);
    frame.render_widget(detail, detail_area);
}

fn render_page(frame: &mut Frame, area: Rect, app: &App) {
    if app.current_selection() >= app.current_page_actions().len() {
        render_simple_detail(
            frame,
            area,
            "Open Shell",
            &[
                "Leave the NiXOA console and exec the configured login shell.".to_string(),
                "Use this to drop into a normal shell session with the TUI bypass enabled."
                    .to_string(),
                "Press Enter, q, or 9 to open the shell.".to_string(),
            ],
            false,
            PanelTone::Info,
        );
        return;
    }

    match app.page {
        Page::Dashboard => render_dashboard(frame, area, app),
        Page::Configure => render_configure(frame, area, app),
        Page::Software => render_software(frame, area, app),
        Page::Maintenance => render_maintenance(frame, area, app),
        Page::Logs => render_logs_page(frame, area, app),
    }
}

fn render_dashboard(frame: &mut Frame, area: Rect, app: &App) {
    let rows = if area.height >= 22 {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(11), Constraint::Min(8)])
            .split(area)
    } else {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(11), Constraint::Min(4)])
            .split(area)
    };

    let top = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(58), Constraint::Percentage(42)])
        .split(rows[0]);

    render_system_summary(frame, top[0], app);
    render_repository_status(frame, top[1], app);

    if area.height >= 26 {
        let bottom = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(62), Constraint::Percentage(38)])
            .split(rows[1]);
        render_alerts(frame, bottom[0], app);
        render_recent_activity(frame, bottom[1], app);
    } else {
        render_alerts(frame, rows[1], app);
    }
}

fn render_system_summary(frame: &mut Frame, area: Rect, app: &App) {
    let inner = draw_panel(
        frame,
        area,
        "System Summary",
        false,
        PanelTone::Info,
    );

    let content = Paragraph::new(vec![
        key_value_line("Hostname", &app.snapshot.hostname, COLOR_ACCENT),
        key_value_line("Username", &app.snapshot.username, COLOR_FG_MAIN),
        key_value_line("XOA", &xoa_version(&app.snapshot), COLOR_FG_MAIN),
        key_value_line("Web UI", &web_ui(&app.snapshot), COLOR_FG_MAIN),
        key_value_line(
            "RAM",
            &format_usage(
                app.snapshot.memory_used_bytes,
                app.snapshot.memory_total_bytes,
                app.snapshot.memory_used_percent,
            ),
            usage_color(app.snapshot.memory_used_percent),
        ),
        key_value_line(
            "Storage",
            &format_storage_capacity(
                app.snapshot.storage_used_bytes,
                app.snapshot.storage_total_bytes,
            ),
            usage_color(app.snapshot.storage_used_percent),
        ),
        key_value_line("Time zone", &app.snapshot.timezone, COLOR_FG_MAIN),
        key_value_line(
            "Extras",
            if app.snapshot.extras { "enabled" } else { "disabled" },
            if app.snapshot.extras {
                COLOR_SUCCESS
            } else {
                COLOR_WARNING
            },
        ),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(content, inner);
}

fn render_repository_status(frame: &mut Frame, area: Rect, app: &App) {
    let inner = draw_panel(frame, area, "Repository Status", false, PanelTone::Neutral);
    let (repo_text, repo_color) = repo_status(&app.snapshot);
    let (apply_text, apply_color) = apply_status(&app.snapshot);
    let (upstream_text, upstream_color) = upstream_status(&app.snapshot);
    let (inputs_text, inputs_color) = inputs_status(&app.update_status, app.tick);

    let content = Paragraph::new(vec![
        key_value_line(
            "Branch",
            &format!("{} [{}]", app.snapshot.branch, short_sha(&app.snapshot.head)),
            COLOR_FG_MAIN,
        ),
        key_value_line("Repository Status", &repo_text, repo_color),
        key_value_line("Apply Status", &apply_text, apply_color),
        key_value_line("Upstream", &upstream_text, upstream_color),
        key_value_line("Flake Inputs", &inputs_text, inputs_color),
        key_value_line(
            "Managed items",
            &format!(
                "{} keys / {} system / {} user / {} services",
                app.snapshot.ssh_keys.len(),
                app.snapshot.system_packages.len(),
                app.snapshot.user_packages.len(),
                app.snapshot.services.len()
            ),
            COLOR_FG_MAIN,
        ),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(content, inner);
}

fn render_alerts(frame: &mut Frame, area: Rect, app: &App) {
    let inner = draw_panel(
        frame,
        area,
        "Alerts",
        app.focus_is(Focus::DashboardAlerts),
        PanelTone::Warning,
    );

    let alerts = app.alerts();
    let items: Vec<ListItem> = alerts
        .iter()
        .map(|alert| {
            let badge = match alert.severity {
                Severity::Info => ("INFO", COLOR_INFO),
                Severity::Warning => ("WARN", COLOR_WARNING),
                Severity::Error => ("ERROR", COLOR_DANGER),
            };

            let mut spans = vec![
                Span::styled(
                    format!("[{}] ", badge.0),
                    Style::default().fg(badge.1).add_modifier(Modifier::BOLD),
                ),
                Span::styled(alert.message.clone(), Style::default().fg(COLOR_FG_MAIN)),
            ];

            if let Some(label) = alert.action_label {
                spans.push(Span::raw("  "));
                spans.push(Span::styled(
                    format!("({label})"),
                    Style::default().fg(COLOR_ACCENT),
                ));
            }

            ListItem::new(Line::from(spans))
        })
        .collect();

    let mut state = ListState::default();
    if !alerts.is_empty() {
        state.select(Some(app.selected_alert));
    }

    let list = List::new(items).highlight_style(
        Style::default()
            .bg(COLOR_ACCENT_SOFT)
            .fg(COLOR_FG_MAIN)
            .add_modifier(Modifier::BOLD),
    );
    frame.render_stateful_widget(list, inner, &mut state);
}

fn render_recent_activity(frame: &mut Frame, area: Rect, app: &App) {
    let inner = draw_panel(
        frame,
        area,
        "Recent Activity",
        false,
        PanelTone::Neutral,
    );
    let lines: Vec<Line> = app
        .recent_logs()
        .into_iter()
        .map(Line::from)
        .collect();
    let paragraph = Paragraph::new(Text::from(lines)).wrap(Wrap { trim: false });
    frame.render_widget(paragraph, inner);
}

fn render_configure(frame: &mut Frame, area: Rect, app: &App) {
    let action = app
        .selected_page_action()
        .map(|item| item.kind)
        .unwrap_or(ActionKind::ManageSshKeys);

    match action {
        ActionKind::ManageSshKeys => render_ssh_keys(frame, area, app),
        ActionKind::EditHostname => render_simple_detail(
            frame,
            area,
            "Hostname",
            &[
                format!("Current hostname: {}", app.snapshot.hostname),
                "Press Enter to open an edit modal and commit the new hostname.".to_string(),
                "The change is written into config/menu.nix immediately.".to_string(),
            ],
            false,
            PanelTone::Info,
        ),
        ActionKind::EditUsername => render_simple_detail(
            frame,
            area,
            "Username",
            &[
                format!("Current username: {}", app.snapshot.username),
                "Press Enter to open an edit modal and commit the new username.".to_string(),
                "The change is written into config/menu.nix immediately.".to_string(),
            ],
            false,
            PanelTone::Info,
        ),
        ActionKind::ToggleExtras => render_simple_detail(
            frame,
            area,
            "Extras",
            &[
                format!(
                    "Extras are currently {}.",
                    if app.snapshot.extras { "enabled" } else { "disabled" }
                ),
                "Press Enter to toggle the extras feature set and commit the override.".to_string(),
            ],
            false,
            PanelTone::Info,
        ),
        _ => {}
    }
}

fn render_ssh_keys(frame: &mut Frame, area: Rect, app: &App) {
    let split = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(62), Constraint::Percentage(38)])
        .split(area);

    let list_inner = draw_panel(
        frame,
        split[0],
        "SSH Keys",
        app.focus_is(Focus::ConfigureSshKeys),
        PanelTone::Info,
    );

    let items: Vec<ListItem> = if app.snapshot.ssh_keys.is_empty() {
        vec![ListItem::new("No SSH keys are currently configured.")]
    } else {
        app.snapshot
            .ssh_keys
            .iter()
            .enumerate()
            .map(|(index, key)| {
                let prefix = if index == app.selected_key { "› " } else { "  " };
                ListItem::new(Line::from(format!("{prefix}{}", truncate_middle(key, 96))))
            })
            .collect()
    };

    let mut state = ListState::default();
    if !app.snapshot.ssh_keys.is_empty() {
        state.select(Some(app.selected_key));
    }
    let list = List::new(items).highlight_style(
        Style::default()
            .bg(COLOR_ACCENT_SOFT)
            .fg(COLOR_FG_MAIN)
            .add_modifier(Modifier::BOLD),
    );
    frame.render_stateful_widget(list, list_inner, &mut state);

    let help_inner = draw_panel(
        frame,
        split[1],
        "Shortcuts",
        false,
        PanelTone::Neutral,
    );
    let help = Paragraph::new(vec![
        Line::from("a add a key"),
        Line::from("e replace all keys"),
        Line::from("d delete selected key"),
        Line::from("Esc/Left returns to actions"),
        Line::from(""),
        Line::from("Each successful action commits only config/menu.nix."),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(help, help_inner);
}

fn render_software(frame: &mut Frame, area: Rect, app: &App) {
    let action = app
        .selected_page_action()
        .map(|item| item.kind)
        .unwrap_or(ActionKind::AddSystemPackage);

    match action {
        ActionKind::AddSystemPackage => render_item_list_page(
            frame,
            area,
            "System Packages",
            &app.snapshot.system_packages,
            "Press Enter to add a new nixpkgs attribute path to the system package list.",
            false,
            false,
        ),
        ActionKind::AddUserPackage => render_item_list_page(
            frame,
            area,
            "User Packages",
            &app.snapshot.user_packages,
            "Press Enter to add a new nixpkgs attribute path to the user package list.",
            false,
            false,
        ),
        ActionKind::AddService => render_item_list_page(
            frame,
            area,
            "Services",
            &app.snapshot.services,
            "Press Enter to enable a service by dotted NixOS option path.",
            false,
            false,
        ),
        _ => {}
    }
}

fn render_maintenance(frame: &mut Frame, area: Rect, app: &App) {
    match app
        .selected_page_action()
        .map(|item| item.kind)
        .unwrap_or(ActionKind::CheckForUpdates)
    {
        ActionKind::CheckForUpdates => render_updates(frame, area, app),
        ActionKind::ApplyConfiguration => render_simple_detail(
            frame,
            area,
            "Apply Configuration",
            &[
                format!("Host: {}", app.snapshot.hostname),
                "Press Enter to run ./scripts/apply-config.sh for this host.".to_string(),
                "The console refreshes state and alerts after the interactive command exits."
                    .to_string(),
            ],
            false,
            PanelTone::Info,
        ),
        ActionKind::RollbackGeneration => render_simple_detail(
            frame,
            area,
            "Rollback Generation",
            &[
                "Press Enter to run nixos-rebuild switch --rollback.".to_string(),
                "Use this after a bad switch when the previous generation should be restored."
                    .to_string(),
            ],
            false,
            PanelTone::Danger,
        ),
        ActionKind::RunGarbageCollection => render_simple_detail(
            frame,
            area,
            "Run Garbage Collection",
            &[
                "Press Enter to run nix-collect-garbage -d.".to_string(),
                "This is a destructive cleanup operation and uses wrapper sudo on NixOS."
                    .to_string(),
            ],
            false,
            PanelTone::Danger,
        ),
        ActionKind::RebootSystem => render_simple_detail(
            frame,
            area,
            "Reboot System",
            &[
                "Press Enter to run systemctl reboot.".to_string(),
                "This uses wrapper sudo and asks systemd to perform a clean reboot."
                    .to_string(),
            ],
            false,
            PanelTone::Danger,
        ),
        ActionKind::ShutdownSystem => render_simple_detail(
            frame,
            area,
            "Shut Down System",
            &[
                "Press Enter to run systemctl poweroff.".to_string(),
                "This uses wrapper sudo and asks systemd to perform a clean shutdown."
                    .to_string(),
            ],
            false,
            PanelTone::Danger,
        ),
        ActionKind::CleanupUnmanagedUsers => render_simple_detail(
            frame,
            area,
            "Cleanup Unmanaged Users",
            &[
                "Press Enter to open a confirmation prompt.".to_string(),
                "Typing WIPE removes non-system users outside the flake-managed admin account."
                    .to_string(),
                "The cleanup also deletes their home directories and orphaned /home entries."
                    .to_string(),
            ],
            false,
            PanelTone::Danger,
        ),
        _ => {}
    }
}

fn render_updates(frame: &mut Frame, area: Rect, app: &App) {
    let input_width = if area.width >= 72 { 24 } else { 20 };
    let split = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Length(input_width),
            Constraint::Length(1),
            Constraint::Min(40),
        ])
        .split(area);

    let list_inner = draw_panel(
        frame,
        split[0],
        "Flake Inputs",
        app.focus_is(Focus::MaintenanceFlakeInputs),
        PanelTone::Warning,
    );

    let items: Vec<ListItem> = UPDATE_ACTIONS
        .iter()
        .map(|action| {
            ListItem::new(Line::from(vec![
                Span::styled(
                    format!("[{}] ", action.shortcut),
                    Style::default().fg(COLOR_MUTED_2),
                ),
                Span::styled(action.title, Style::default().fg(COLOR_FG_MAIN)),
            ]))
        })
        .collect();
    let mut state = ListState::default();
    state.select(Some(app.selected_update));
    let list = List::new(items).highlight_style(
        Style::default()
            .bg(COLOR_ACCENT_SOFT)
            .fg(COLOR_FG_MAIN)
            .add_modifier(Modifier::BOLD),
    );
    frame.render_stateful_widget(list, list_inner, &mut state);

    let detail_inner = draw_panel(
        frame,
        split[2],
        "Update Details",
        false,
        PanelTone::Neutral,
    );
    let update = &UPDATE_ACTIONS[app.selected_update];
    let content = Paragraph::new(vec![
        Line::from(update.detail),
        Line::from(""),
        key_value_line(
            "Queued on boot",
            if app.snapshot.rebuild_queued { "yes" } else { "no" },
            if app.snapshot.rebuild_queued {
                COLOR_INFO
            } else {
                COLOR_FG_MAIN
            },
        ),
        key_value_line(
            "Needs rebuild",
            if app.snapshot.rebuild_needed { "yes" } else { "no" },
            if app.snapshot.rebuild_needed {
                COLOR_WARNING
            } else {
                COLOR_FG_MAIN
            },
        ),
        key_value_line(
            "Input status",
            &inputs_status(&app.update_status, app.tick).0,
            inputs_status(&app.update_status, app.tick).1,
        ),
        Line::from(""),
        Line::from("Each update commits only flake.lock."),
        Line::from("After a lock change, the backend asks whether to rebuild now or on the next boot."),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(content, detail_inner);
}

fn render_logs_page(frame: &mut Frame, area: Rect, app: &App) {
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(5), Constraint::Min(8)])
        .split(area);

    let meta_inner = draw_panel(frame, rows[0], "Recent Activity", false, PanelTone::Neutral);
    let filtered_logs = app.filtered_logs();
    let meta = Paragraph::new(vec![
        key_value_line(
            "Filter",
            if app.log_filter.is_empty() {
                "none"
            } else {
                app.log_filter.as_str()
            },
            if app.log_filter.is_empty() {
                COLOR_MUTED
            } else {
                COLOR_ACCENT
            },
        ),
        key_value_line("Visible entries", &filtered_logs.len().to_string(), COLOR_FG_MAIN),
        Line::from("Use / to set a filter, c to clear it, and arrows/jk to scroll."),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(meta, meta_inner);

    let log_inner = draw_panel(
        frame,
        rows[1],
        "Logs",
        app.focus_is(Focus::LogsView),
        PanelTone::Info,
    );
    if filtered_logs.is_empty() {
        frame.render_widget(
            Paragraph::new("No log entries matched the current filter.")
                .wrap(Wrap { trim: true }),
            log_inner,
        );
        return;
    }

    let visible_height = max(log_inner.height as usize, 1);
    let scroll = min(app.log_scroll, filtered_logs.len().saturating_sub(1));
    let start = scroll;
    let end = min(start + visible_height, filtered_logs.len());
    let lines: Vec<Line> = filtered_logs[start..end]
        .iter()
        .map(|line| Line::from(line.clone()))
        .collect();

    let paragraph = Paragraph::new(Text::from(lines)).wrap(Wrap { trim: false });
    frame.render_widget(paragraph, log_inner);
}

fn render_footer(frame: &mut Frame, area: Rect, app: &App) {
    let inner = draw_panel(frame, area, "Shortcuts", false, PanelTone::Neutral);
    let footer = Paragraph::new(vec![
        Line::from(vec![
            Span::styled("Tab ", Style::default().fg(COLOR_ACCENT)),
            Span::styled("focus", Style::default().fg(COLOR_MUTED)),
            Span::raw("   "),
            Span::styled("Up/Down ", Style::default().fg(COLOR_ACCENT)),
            Span::styled("or j/k move within the focused list", Style::default().fg(COLOR_MUTED)),
            Span::raw("   "),
            Span::styled("Left/Right ", Style::default().fg(COLOR_ACCENT)),
            Span::styled("or h/l handle page and parent/child navigation", Style::default().fg(COLOR_MUTED)),
            Span::raw("   "),
            Span::styled("[ ] ", Style::default().fg(COLOR_ACCENT)),
            Span::styled("pages", Style::default().fg(COLOR_MUTED)),
            Span::raw("   "),
            Span::styled("Enter ", Style::default().fg(COLOR_ACCENT)),
            Span::styled("run / open", Style::default().fg(COLOR_MUTED)),
            Span::raw("   "),
            Span::styled("Esc ", Style::default().fg(COLOR_ACCENT)),
            Span::styled("back / quit prompt", Style::default().fg(COLOR_MUTED)),
            Span::raw("   "),
            Span::styled(": ", Style::default().fg(COLOR_ACCENT)),
            Span::styled("palette", Style::default().fg(COLOR_MUTED)),
            Span::raw("   "),
            Span::styled("? ", Style::default().fg(COLOR_ACCENT)),
            Span::styled("help", Style::default().fg(COLOR_MUTED)),
            Span::raw("   "),
            Span::styled("q ", Style::default().fg(COLOR_ACCENT)),
            Span::styled("shell", Style::default().fg(COLOR_MUTED)),
        ]),
        Line::from(vec![
            Span::styled("Last apply: ", Style::default().fg(COLOR_MUTED_2)),
            Span::styled(last_apply_label(&app.snapshot), Style::default().fg(COLOR_MUTED)),
        ]),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(footer, inner);
}

fn render_simple_detail(
    frame: &mut Frame,
    area: Rect,
    title: &str,
    lines: &[String],
    focused: bool,
    tone: PanelTone,
) {
    let inner = draw_panel(frame, area, title, focused, tone);
    let paragraph = Paragraph::new(lines.iter().cloned().map(Line::from).collect::<Vec<_>>())
        .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, inner);
}

fn render_item_list_page(
    frame: &mut Frame,
    area: Rect,
    title: &str,
    items: &[String],
    help: &str,
    list_focused: bool,
    details_focused: bool,
) {
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(6), Constraint::Length(5)])
        .split(area);

    let list_inner = draw_panel(frame, rows[0], title, list_focused, PanelTone::Info);
    let list_items: Vec<ListItem> = if items.is_empty() {
        vec![ListItem::new("No entries are currently configured.")]
    } else {
        items.iter()
            .map(|item| ListItem::new(truncate_middle(item, 100)))
            .collect()
    };
    frame.render_widget(List::new(list_items), list_inner);

    let help_inner = draw_panel(frame, rows[1], "Details", details_focused, PanelTone::Neutral);
    frame.render_widget(
        Paragraph::new(help).wrap(Wrap { trim: true }),
        help_inner,
    );
}

fn render_input_modal(frame: &mut Frame, area: Rect, modal: &InputModal) {
    let popup = centered_rect(72, 32, area);
    frame.render_widget(Clear, popup);
    let inner = draw_panel(frame, popup, modal.title.clone(), true, PanelTone::Info);
    let paragraph = Paragraph::new(vec![
        Line::from(modal.help.clone()),
        Line::from(""),
        Line::from(format!("> {}", modal.value)),
        Line::from(""),
        Line::from("Enter submits. Esc cancels. Ctrl+u clears the input."),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, inner);
}

fn render_quit_confirm(frame: &mut Frame, area: Rect) {
    let popup = centered_rect(44, 24, area);
    frame.render_widget(Clear, popup);
    let inner = draw_panel(frame, popup, "Exit Console?", true, PanelTone::Danger);
    let paragraph = Paragraph::new(vec![
        Line::from("Close the TUI and return to the shell?"),
        Line::from(""),
        Line::from("Press Y to exit."),
        Line::from("Press N or Esc to stay in the console."),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, inner);
}

fn render_command_palette(frame: &mut Frame, area: Rect, app: &App) {
    let popup = centered_rect(74, 62, area);
    frame.render_widget(Clear, popup);
    let inner = draw_panel(frame, popup, "Command Palette", true, PanelTone::Info);
    let sections = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(6), Constraint::Length(3)])
        .split(inner);

    let query = app
        .command_palette
        .as_ref()
        .map(|palette| palette.query.as_str())
        .unwrap_or("");
    frame.render_widget(
        Paragraph::new(vec![
            Line::from("Search actions and pages."),
            Line::from(format!("> {query}")),
        ]),
        sections[0],
    );

    let entries = app.palette_entries();
    let items: Vec<ListItem> = if entries.is_empty() {
        vec![ListItem::new("No commands matched the current query.")]
    } else {
        entries
            .iter()
            .map(|entry| {
                ListItem::new(vec![
                    Line::from(Span::styled(
                        entry.title.clone(),
                        Style::default().fg(COLOR_FG_MAIN),
                    )),
                    Line::from(Span::styled(
                        entry.detail.clone(),
                        Style::default().fg(COLOR_MUTED),
                    )),
                ])
            })
            .collect()
    };

    let mut state = ListState::default();
    if !entries.is_empty() {
        let selected = app
            .command_palette
            .as_ref()
            .map(|palette| min(palette.selected, entries.len() - 1))
            .unwrap_or(0);
        state.select(Some(selected));
    }

    let list = List::new(items).highlight_style(
        Style::default()
            .bg(COLOR_ACCENT_SOFT)
            .fg(COLOR_FG_MAIN)
            .add_modifier(Modifier::BOLD),
    );
    frame.render_stateful_widget(list, sections[1], &mut state);

    frame.render_widget(
        Paragraph::new("Esc closes. Enter runs the selected action. Up/Down move the selection.")
            .wrap(Wrap { trim: true }),
        sections[2],
    );
}

fn render_help_modal(frame: &mut Frame, area: Rect, app: &App) {
    let popup = centered_rect(76, 68, area);
    frame.render_widget(Clear, popup);
    let inner = draw_panel(frame, popup, "Help", true, PanelTone::Info);
    let help = Paragraph::new(vec![
        Line::from("Global navigation"),
        Line::from("  Up/Down or j/k move inside the focused list or menu."),
        Line::from("  Left/Right or h/l switch pages at the top nav, or move between an action pane and its child pane."),
        Line::from("  Enter only runs, confirms, or opens the selected item."),
        Line::from("  Esc unwinds back to the main actions pane. Esc on the main actions pane opens a Y/N quit prompt."),
        Line::from("  Tab / Shift-Tab still provide an optional deterministic focus cycle. [ and ] still switch pages."),
        Line::from("  ? opens this help modal. q or 9 exec the configured login shell."),
        Line::from(""),
        Line::from("Page model"),
        Line::from("  Dashboard: Main Actions -> Alerts."),
        Line::from("  Configure: Main Actions -> SSH Keys only for the SSH Keys action."),
        Line::from("  Software: Main Actions only; package/service details are read-only."),
        Line::from("  Maintenance: Main Actions -> Flake Inputs only for Check for Updates."),
        Line::from("  Logs: Main Actions -> Logs."),
        Line::from(""),
        Line::from("Current page"),
        Line::from(format!("  {}", app.page_title())),
        Line::from(format!("  Selected action: {}", app.selected_sidebar_title())),
        Line::from(format!("  Focus: {}", focus_label(app.focus))),
        Line::from(""),
        Line::from("Esc closes this help modal."),
    ])
    .wrap(Wrap { trim: true });
    frame.render_widget(help, inner);
}

fn key_value_line(label: &str, value: &str, color: Color) -> Line<'static> {
    Line::from(vec![
        Span::styled(format!("{label:<16}"), Style::default().fg(COLOR_MUTED_2)),
        Span::styled(value.to_string(), Style::default().fg(color)),
    ])
}

fn focus_label(focus: Focus) -> &'static str {
    match focus {
        Focus::TopNav => "Top Nav",
        Focus::MainActions => "Main Actions",
        Focus::DashboardAlerts => "Alerts",
        Focus::ConfigureSshKeys => "SSH Keys",
        Focus::MaintenanceFlakeInputs => "Flake Inputs",
        Focus::LogsView => "Logs",
    }
}

fn last_apply_label(snapshot: &Snapshot) -> String {
    if let Some(last_apply) = &snapshot.last_apply {
        format!(
            "{} {} on {} @ {}{} [{}]",
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
        "not recorded".to_string()
    }
}

fn sudo_command() -> Command {
    if Path::new("/run/wrappers/bin/sudo").exists() {
        Command::new("/run/wrappers/bin/sudo")
    } else {
        Command::new("sudo")
    }
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
