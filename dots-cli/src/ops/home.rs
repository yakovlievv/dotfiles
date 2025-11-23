use std::path::{Path, PathBuf};

use anyhow::{Result, anyhow};

use crate::context::{Context, HostKind};

use super::common::{ensure_dir, ensure_symlink, run_command};

struct HomePlan {
    directories: Vec<PathBuf>,
    symlinks: Vec<(PathBuf, PathBuf)>,
    root_symlinks: Vec<(PathBuf, PathBuf)>,
}

impl HomePlan {
    fn new() -> Self {
        Self {
            directories: Vec::new(),
            symlinks: Vec::new(),
            root_symlinks: Vec::new(),
        }
    }
}

pub fn run(ctx: &Context) -> Result<()> {
    ctx.logger.info(format!(
        "Preparing home environment for {}",
        ctx.host.label()
    ));

    let plan = build_plan(ctx)?;

    for dir in plan.directories {
        ensure_dir(ctx, &dir)?;
    }

    for (src, dest) in plan.symlinks {
        ensure_symlink(ctx, &src, &dest)?;
    }

    for (src, dest) in plan.root_symlinks {
        link_with_sudo(ctx, &src, &dest)?;
    }

    Ok(())
}

fn build_plan(ctx: &Context) -> Result<HomePlan> {
    let mut plan = HomePlan::new();

    // Core XDG directories
    plan.directories.extend([
        ctx.paths.config.clone(),
        ctx.paths.cache.clone(),
        ctx.paths.bin.clone(),
        ctx.paths.data.clone(),
        ctx.paths.state.clone(),
    ]);

    match ctx.host {
        HostKind::MacOs => extend_mac_plan(ctx, &mut plan),
        HostKind::ArchLinux => extend_arch_plan(ctx, &mut plan),
        HostKind::Linux => {
            ctx.logger
                .warn("Generic Linux support is not implemented yet");
        }
    }

    Ok(plan)
}

fn extend_mac_plan(ctx: &Context, plan: &mut HomePlan) {
    const HOME_DIRS: &[&str] = &["docs", "bin", "tmp", "dev"];
    const CONFIG_DIRS: &[&str] = &[
        "fastfetch",
        "bat",
        "karabiner",
        "kitty",
        "nvim",
        "yazi",
        "wget",
        "prettier",
        "git",
        "lazygit",
        "opencode",
    ];

    plan.directories
        .extend(HOME_DIRS.iter().map(|dir| ctx.paths.home.join(dir)));

    plan.symlinks
        .extend(CONFIG_DIRS.iter().map(|dir| symlink_config(ctx, dir)));

    plan.symlinks.push((
        ctx.root.join("starship/starship.toml"),
        ctx.paths.config.join("starship.toml"),
    ));
    plan.symlinks
        .push((ctx.root.join("bin"), ctx.paths.home.join("bin")));
    plan.symlinks.push((
        ctx.root.join("tmux/.tmux.conf"),
        ctx.paths.home.join(".tmux.conf"),
    ));
    plan.symlinks.push((
        ctx.root.join("tmux/.config/tmux"),
        ctx.paths.config.join("tmux"),
    ));
    plan.symlinks
        .push((ctx.root.join("zsh/.zshenv"), ctx.paths.home.join(".zshenv")));
    plan.symlinks.push((
        ctx.root.join("zsh/.config/zsh"),
        ctx.paths.config.join("zsh"),
    ));
}

fn extend_arch_plan(ctx: &Context, plan: &mut HomePlan) {
    const HOME_DIRS: &[&str] = &["docs", "media", "media/wallpapers", "tmp", "dev"];
    const CONFIG_DIRS: &[&str] = &[
        "fastfetch",
        "bat",
        "kitty",
        "nvim",
        "zathura",
        "yazi",
        "wofi",
        "wlogout",
        "wget",
        "prettier",
        "git",
        "swaync",
        "waybar",
        "hypr",
        "lazygit",
        "gtk-3.0",
        "gtk-4.0",
    ];

    plan.directories
        .extend(HOME_DIRS.iter().map(|dir| ctx.paths.home.join(dir)));

    plan.symlinks
        .extend(CONFIG_DIRS.iter().map(|dir| symlink_config(ctx, dir)));

    plan.symlinks.push((
        ctx.root.join("starship/starship.toml"),
        ctx.paths.config.join("starship.toml"),
    ));
    plan.symlinks.push((
        ctx.root.join("tmux/.tmux.conf"),
        ctx.paths.home.join(".tmux.conf"),
    ));
    plan.symlinks.push((
        ctx.root.join("tmux/.config/tmux"),
        ctx.paths.config.join("tmux"),
    ));
    plan.symlinks
        .push((ctx.root.join("zsh/.zshenv"), ctx.paths.home.join(".zshenv")));
    plan.symlinks.push((
        ctx.root.join("zsh/.config/zsh"),
        ctx.paths.config.join("zsh"),
    ));
    plan.symlinks.push((
        ctx.root.join("wallpapers"),
        ctx.paths.home.join("media/wallpapers"),
    ));

    plan.root_symlinks.push((
        ctx.root.join("keyd/default.conf"),
        PathBuf::from("/etc/keyd/default.conf"),
    ));
}

fn symlink_config(ctx: &Context, name: &str) -> (PathBuf, PathBuf) {
    (ctx.root.join(name), ctx.paths.config.join(name))
}

fn link_with_sudo(ctx: &Context, source: &Path, dest: &Path) -> Result<()> {
    let src = source
        .to_str()
        .ok_or_else(|| anyhow!("non-utf8 path: {}", source.display()))?;
    let dst = dest
        .to_str()
        .ok_or_else(|| anyhow!("non-utf8 path: {}", dest.display()))?;

    run_command(ctx, "sudo", ["ln", "-sfn", src, dst])
}
