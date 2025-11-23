use std::env;
use std::path::{Path, PathBuf};

use anyhow::{Context as AnyhowContext, Result, anyhow};

use crate::cli::Cli;
use crate::logging::Logger;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostKind {
    MacOs,
    ArchLinux,
    Linux,
}

impl HostKind {
    pub fn detect() -> Result<Self> {
        match env::consts::OS {
            "macos" => Ok(Self::MacOs),
            "linux" => {
                if is_present("pacman") {
                    Ok(Self::ArchLinux)
                } else {
                    Ok(Self::Linux)
                }
            }
            other => Err(anyhow!("unsupported operating system: {}", other)),
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::MacOs => "macOS",
            Self::ArchLinux => "Arch Linux",
            Self::Linux => "Linux",
        }
    }
}

fn is_present(bin: &str) -> bool {
    env::var_os("PATH").map_or(false, |path| {
        env::split_paths(&path).any(|dir| dir.join(bin).exists())
    })
}

#[derive(Debug, Clone)]
pub struct Paths {
    pub home: PathBuf,
    pub config: PathBuf,
    pub cache: PathBuf,
    pub bin: PathBuf,
    pub data: PathBuf,
    pub state: PathBuf,
}

impl Paths {
    pub fn from_env(home: &Path) -> Self {
        let config = env_var_path("XDG_CONFIG_HOME").unwrap_or_else(|| home.join(".config"));
        let cache = env_var_path("XDG_CACHE_HOME").unwrap_or_else(|| home.join(".cache"));
        let bin = env_var_path("XDG_BIN_HOME").unwrap_or_else(|| home.join(".local/bin"));
        let data = env_var_path("XDG_DATA_HOME").unwrap_or_else(|| home.join(".local/share"));
        let state = env_var_path("XDG_STATE_HOME").unwrap_or_else(|| home.join(".local/state"));

        Self {
            home: home.to_path_buf(),
            config,
            cache,
            bin,
            data,
            state,
        }
    }
}

fn env_var_path(key: &str) -> Option<PathBuf> {
    env::var_os(key).map(PathBuf::from)
}

#[derive(Debug, Clone)]
pub struct Context {
    pub root: PathBuf,
    pub paths: Paths,
    pub host: HostKind,
    pub logger: Logger,
    pub dry_run: bool,
    pub shell_path: PathBuf,
}

impl Context {
    pub fn new(args: &Cli) -> Result<Self> {
        let home = env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| anyhow!("$HOME is not set"))?;

        let supplied_root = args.root.clone().unwrap_or_else(crate::cli::default_root);
        let root = normalize_root(&supplied_root, &home)?;
        let host = HostKind::detect()?;
        let paths = Paths::from_env(&home);

        let dry_run = args.dry_run;
        let logger = Logger::new(args.verbose, dry_run);

        let shell_path = args
            .shell_path
            .clone()
            .unwrap_or_else(|| PathBuf::from("/usr/bin/zsh"));

        Ok(Self {
            root,
            paths,
            host,
            logger,
            dry_run,
            shell_path,
        })
    }
}

fn normalize_root(root: &Path, home: &Path) -> Result<PathBuf> {
    let candidate = if root.is_absolute() {
        root.to_path_buf()
    } else {
        home.join(root)
    };

    if candidate.exists() {
        candidate
            .canonicalize()
            .with_context(|| format!("failed to canonicalize root path: {}", candidate.display()))
    } else {
        Err(anyhow!(
            "dotfiles root does not exist: {}",
            candidate.display()
        ))
    }
}
