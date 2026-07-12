// ---------------------------------------------------------------------------
// Zen (Firefox) user.js  —  declarative, reproducible settings
// ---------------------------------------------------------------------------
// This file is READ at startup and applied into prefs.js. Zen never writes
// back to it, so it is safe to symlink from dotfiles.
//
// Distilled from prefs.js on 2026-07-05. Only genuine, hand-picked settings
// live here — telemetry IDs, sync state, timestamps, build IDs, per-profile
// extension UUIDs, and machine-specific values (device name, CPU ABIs) were
// intentionally excluded. The full original dump is in prefs.reference.js.
//
// NOTE: a pref set here is FORCED on every launch. Changing it via the Zen UI
// won't stick across restarts — edit it here instead. Several of these also
// ride Firefox Sync already; user.js just makes them reproducible on a fresh
// profile too.
// ---------------------------------------------------------------------------

// --- Startup / new tab -----------------------------------------------------
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtabpage.activity-stream.showSearch", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.pinned", "[{\"url\":\"https://www.youtube.com/\",\"label\":\"youtube\"},{\"url\":\"https://chatgpt.com/\"},{\"url\":\"https://monkeytype.com/\"},null,{\"url\":\"https://pomofocus.io/\",\"label\":\"pomofocus\"},{\"url\":\"https://www.chess.com/\",\"label\":\"chess\"}]");

// --- Tabs ------------------------------------------------------------------
user_pref("browser.ctrlTab.sortByRecentlyUsed", true);
user_pref("browser.tabs.loadInBackground", false);
user_pref("browser.warnOnQuitShortcut", false);

// --- URL bar (all suggestions off) -----------------------------------------
user_pref("browser.urlbar.suggest.bookmark", false);
user_pref("browser.urlbar.suggest.engines", false);
user_pref("browser.urlbar.suggest.history", false);
user_pref("browser.urlbar.suggest.openpage", false);
user_pref("browser.urlbar.suggest.searches", false);

// --- Language / translations -----------------------------------------------
user_pref("intl.accept_languages", "en-us,en,ru,uk");
user_pref("browser.translations.automaticallyPopup", false);
user_pref("browser.translations.neverTranslateLanguages", "uk");

// --- Fonts -----------------------------------------------------------------
user_pref("font.name.serif.x-western", "JetBrainsMono Nerd Font Mono");

// --- Passwords / autofill / privacy ----------------------------------------
user_pref("signon.rememberSignons", false);
user_pref("signon.management.page.breach-alerts.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);
user_pref("privacy.donottrackheader.enabled", true);
user_pref("privacy.clearOnShutdown_v2.cache", false);
user_pref("privacy.clearOnShutdown_v2.cookiesAndStorage", false);
user_pref("privacy.clearOnShutdown_v2.downloads", false);
user_pref("privacy.clearOnShutdown_v2.formdata", true);

// --- Network (perf / privacy) ----------------------------------------------
user_pref("network.dns.disablePrefetch", true);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.prefetch-next", false);

// --- Misc ------------------------------------------------------------------
user_pref("accessibility.typeaheadfind.flashBar", 0);
user_pref("ui.osk.enabled", false);

// --- DevTools --------------------------------------------------------------
user_pref("devtools.toolbox.host", "right");
user_pref("devtools.inspector.three-pane-enabled", false);
user_pref("devtools.responsive.touchSimulation.enabled", true);

// --- Chrome customization --------------------------------------------------
// Load chrome/userChrome.css (dark tint over the transparent window).
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// --- Zen: view & behavior --------------------------------------------------
user_pref("zen.glance.enabled", false);
user_pref("zen.view.compact.enable-at-startup", false);
user_pref("zen.view.compact.hide-toolbar", true);
user_pref("zen.view.show-newtab-button-top", false);
user_pref("zen.view.sidebar-expanded", false);
user_pref("zen.view.use-single-toolbar", false);
user_pref("zen.swipe.is-fast-swipe", false);
user_pref("zen.workspaces.continue-where-left-off", true);
