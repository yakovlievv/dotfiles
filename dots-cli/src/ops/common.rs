use std::ffi::OsStr;
use std::fs;
use std::os::unix::fs as unix_fs;
use std::path::Path;
use std::process::Command;

use anyhow::{Context as AnyhowContext, Result, anyhow};

use crate::context::Context;

pub fn ensure_dir(ctx: &Context, path: &Path) -> Result<()> {
    ctx.logger
        .action(format!("ensure directory {}", path.display()));

    if ctx.dry_run {
        return Ok(());
    }

    fs::create_dir_all(path).with_context(|| format!("failed to create {}", path.display()))?;
    Ok(())
}

pub fn ensure_symlink(ctx: &Context, source: &Path, dest: &Path) -> Result<()> {
    ctx.logger
        .action(format!("link {} -> {}", source.display(), dest.display()));

    if ctx.dry_run {
        return Ok(());
    }

    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to prepare parent {}", parent.display()))?;
    }

    if let Ok(meta) = fs::symlink_metadata(dest) {
        ctx.logger
            .verbose(format!("removing existing {}", dest.display()));
        if meta.file_type().is_dir() && !meta.file_type().is_symlink() {
            fs::remove_dir_all(dest)
                .with_context(|| format!("failed to remove existing dir {}", dest.display()))?;
        } else {
            fs::remove_file(dest)
                .with_context(|| format!("failed to remove existing file {}", dest.display()))?;
        }
    }

    unix_fs::symlink(source, dest).with_context(|| {
        format!(
            "failed to create symlink {} -> {}",
            source.display(),
            dest.display()
        )
    })?;

    Ok(())
}

pub fn remove_path(ctx: &Context, path: &Path) -> Result<()> {
    ctx.logger.action(format!("remove {}", path.display()));

    if ctx.dry_run {
        return Ok(());
    }

    if let Ok(meta) = fs::symlink_metadata(path) {
        ctx.logger
            .verbose(format!("removing existing {}", path.display()));
        if meta.file_type().is_dir() && !meta.file_type().is_symlink() {
            fs::remove_dir_all(path)
                .with_context(|| format!("failed to remove directory {}", path.display()))?;
        } else {
            fs::remove_file(path)
                .with_context(|| format!("failed to remove file {}", path.display()))?;
        }
    }

    Ok(())
}

pub fn run_command<I, S>(ctx: &Context, program: &str, args: I) -> Result<()>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let args_vec: Vec<_> = args.into_iter().collect();
    let display_args: Vec<String> = args_vec
        .iter()
        .map(|arg| arg.as_ref().to_string_lossy().into_owned())
        .collect();

    if display_args.is_empty() {
        ctx.logger.action(format!("run {}", program));
    } else {
        ctx.logger
            .action(format!("run {} {}", program, display_args.join(" ")));
    }

    if ctx.dry_run {
        return Ok(());
    }

    let status = Command::new(program)
        .args(args_vec)
        .status()
        .with_context(|| format!("failed to spawn {}", program))?;

    if status.success() {
        Ok(())
    } else {
        Err(anyhow!("command {} exited with status {}", program, status))
    }
}
