use owo_colors::OwoColorize;

#[derive(Debug, Clone)]
pub struct Logger {
    verbose: bool,
    dry_run: bool,
}

impl Logger {
    pub fn new(verbose: bool, dry_run: bool) -> Self {
        Self { verbose, dry_run }
    }

    pub fn info(&self, message: impl AsRef<str>) {
        println!("{} {}", "==>".green().bold(), message.as_ref());
    }

    pub fn warn(&self, message: impl AsRef<str>) {
        eprintln!("{} {}", "⚠".yellow().bold(), message.as_ref());
    }

    pub fn error(&self, message: impl AsRef<str>) {
        eprintln!("{} {}", "✖".red().bold(), message.as_ref());
    }

    pub fn action(&self, message: impl AsRef<str>) {
        if self.dry_run {
            println!(
                "{} {}",
                "⤷".cyan().bold(),
                format!("[dry-run] {}", message.as_ref())
            );
        } else {
            println!("{} {}", "⤷".cyan().bold(), message.as_ref());
        }
    }

    pub fn verbose(&self, message: impl AsRef<str>) {
        if self.verbose {
            println!("{} {}", "..".dimmed(), message.as_ref());
        }
    }
}
