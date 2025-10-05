### How to set this shit up?

1. Install librewolf
2. Install extensions
    - Bitwarden
    - Ublock origin (install by default)
    - Privacy Badger
    - Sidebery
    - Improved Youtube
    - Unhook
    - Userchrome Toggle Extended
    - Tridactyl (or vimium)
    - Stylus
3. Import data for:
    - Stylus
    - Sidebery
4. Put the chrome directory and user.js file in your active profile directory
5. Reload librewolf
6. To set up userstyles go set up catppuccin userstyles, and then take each userstyle from userstyles directory and replace the code in the stylus extension settings.

### right now there is a problem with the user.js file so i'll just give you all the changed preferences so you can fuck around with it as much as you want

so there is some normal data that lives in user.js but there is not everything some of it you'll have to extract from here. But for the most part there is a pic of all the setting you need to fuck around with

[[!2025-06-15-133532_hyprshot.png]]

app.update.lastUpdateTime.addon-background-update-timer	1749911616	
app.update.lastUpdateTime.browser-cleanup-thumbnails	1749981125	
app.update.lastUpdateTime.services-settings-poll-changes	1749911616	
app.update.lastUpdateTime.xpi-signature-verification	1749911616	
browser.aboutConfig.showWarning	false	
browser.bookmarks.addedImportButton	true	
browser.bookmarks.editDialog.confirmationHintShowCount	2	
browser.bookmarks.restore_default_bookmarks	false	
browser.contentblocking.category	strict	
browser.ctrlTab.sortByRecentlyUsed	true	
browser.dom.window.dump.enabled	false	
browser.download.autohideButton	true	
browser.download.panel.shown	true	
browser.download.useDownloadDir	true	
browser.download.viewableInternally.typeWasRegistered.avif	true	
browser.download.viewableInternally.typeWasRegistered.webp	true	
browser.engagement.downloads-button.has-used	true	
browser.engagement.sidebar-button.has-used	true	
browser.migration.version	155	
browser.newtab.extensionControlled	true	
browser.newtab.privateAllowed	false	
browser.newtabpage.activity-stream.impressionId	{7006642a-0ee8-496e-be6d-4a12e6958ad9}	
browser.newtabpage.storageVersion	1	
browser.pageActions.persistedActions	{"ids":["bookmark","_3c078156-979c-498b-8990-85f7987dd929_"],"idsInUrlbar":["_3c078156-979c-498b-8990-85f7987dd929_","bookmark"],"idsInUrlbarPreProton":[],"version":1}	
browser.pagethumbnails.storage_version	3	
browser.policies.applied	true	
browser.policies.runOncePerModification.extensionsInstall	["https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"]	
browser.policies.runOncePerModification.extensionsUninstall	["google@search.mozilla.org","bing@search.mozilla.org","amazondotcom@search.mozilla.org","ebay@search.mozilla.org","twitter@search.mozilla.org"]	
browser.policies.runOncePerModification.removeSearchEngines	["Google","Bing","Amazon.com","eBay","Twitter"]	
browser.policies.runOncePerModification.setDefaultSearchEngine	DuckDuckGo	
browser.preferences.experimental.hidden	true	
browser.profiles.enabled	true	
browser.protections_panel.infoMessage.seen	true	
browser.proton.toolbar.version	3	
browser.region.network.url		
browser.region.update.enabled	false	
browser.safebrowsing.downloads.remote.block_potentially_unwanted	false	
browser.safebrowsing.downloads.remote.block_uncommon	false	
browser.safebrowsing.downloads.remote.enabled	false	
browser.safebrowsing.downloads.remote.url		
browser.safebrowsing.provider.google4.dataSharingURL		
browser.safebrowsing.provider.mozilla.lastupdatetime	1749981096493	
browser.safebrowsing.provider.mozilla.nextupdatetime	1750002696493	
browser.search.separatePrivateDefault	false	
browser.search.totalSearches	3	
browser.sessionstore.upgradeBackup.latestBuildID	20250612160025	
browser.shell.mostRecentDateSetAsDefault	1749981096	
browser.startup.couldRestoreSession.count	1	
browser.startup.lastColdStartupCheck	1749981097	
browser.startup.page	3	
browser.tabs.allow_transparent_browser	true	
browser.theme.content-theme	0	
browser.theme.toolbar-theme	0	
browser.toolbarbuttons.introduced.sidebar-button	true	
browser.toolbars.bookmarks.visibility	never	
browser.uiCustomization.horizontalTabsBackup	{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["_7a7a4a92-a2a0-41d1-9fd7-1e92480d612d_-browser-action","_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"],"nav-bar":["sidebar-button","back-button","forward-button","stop-reload-button","customizableui-special-spring1","vertical-spacer","urlbar-container","customizableui-special-spring2","save-to-pocket-button","downloads-button","fxa-toolbar-menu-button","unified-extensions-button","ublock0_raymondhill_net-browser-action","_3c078156-979c-498b-8990-85f7987dd929_-browser-action","jid1-mnnxcxisbpnsxq_jetpack-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["tabbrowser-tabs","new-tab-button","alltabs-button"],"vertical-tabs":[],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["developer-button","ublock0_raymondhill_net-browser-action","_3c078156-979c-498b-8990-85f7987dd929_-browser-action","jid1-mnnxcxisbpnsxq_jetpack-browser-action","_7a7a4a92-a2a0-41d1-9fd7-1e92480d612d_-browser-action","_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"],"dirtyAreaCache":["nav-bar","vertical-tabs","PersonalToolbar","toolbar-menubar","TabsToolbar","unified-extensions-area"],"currentVersion":22,"newElementCount":2}	
browser.uiCustomization.navBarWhenVerticalTabs	["sidebar-button","back-button","forward-button","stop-reload-button","customizableui-special-spring1","vertical-spacer","urlbar-container","customizableui-special-spring2","save-to-pocket-button","downloads-button","fxa-toolbar-menu-button","unified-extensions-button","ublock0_raymondhill_net-browser-action","_3c078156-979c-498b-8990-85f7987dd929_-browser-action","jid1-mnnxcxisbpnsxq_jetpack-browser-action","alltabs-button"]	
browser.uiCustomization.state	{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["_3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf_-browser-action","jid1-mnnxcxisbpnsxq_jetpack-browser-action","_7a7a4a92-a2a0-41d1-9fd7-1e92480d612d_-browser-action","myallychou_gmail_com-browser-action"],"nav-bar":["back-button","forward-button","customizableui-special-spring1","customizableui-special-spring5","vertical-spacer","urlbar-container","customizableui-special-spring4","customizableui-special-spring2","save-to-pocket-button","fxa-toolbar-menu-button","ublock0_raymondhill_net-browser-action","_3c078156-979c-498b-8990-85f7987dd929_-browser-action","_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action","userchrome-toggle-extended_n2ezr_ru-browser-action","downloads-button","unified-extensions-button"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["tabbrowser-tabs","new-tab-button","alltabs-button"],"vertical-tabs":[],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["developer-button","ublock0_raymondhill_net-browser-action","_3c078156-979c-498b-8990-85f7987dd929_-browser-action","jid1-mnnxcxisbpnsxq_jetpack-browser-action","_7a7a4a92-a2a0-41d1-9fd7-1e92480d612d_-browser-action","_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action","userchrome-toggle-extended_n2ezr_ru-browser-action","_3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf_-browser-action","myallychou_gmail_com-browser-action"],"dirtyAreaCache":["nav-bar","vertical-tabs","PersonalToolbar","toolbar-menubar","TabsToolbar","unified-extensions-area"],"currentVersion":22,"newElementCount":6}	
browser.urlbar.placeholderName	DuckDuckGo	
browser.urlbar.suggest.calculator	true	
browser.urlbar.suggest.engines	false	
browser.urlbar.trimHttps	true	
browser.urlbar.trimURLs	true	
browser.urlbar.unitConversion.enabled	true	
captchadetection.lastSubmission	1749911	
captivedetect.canonicalURL		
datareporting.dau.cachedUsageProfileGroupID	b0bacafe-b0ba-cafe-b0ba-cafeb0bacafe	
datareporting.dau.cachedUsageProfileID	beefbeef-beef-beef-beef-beeefbeefbee	
devtools.console.stdout.chrome	false	
devtools.debugger.remote-enabled	false	
devtools.everOpened	true	
devtools.netmonitor.columnsData	[{"name":"override","minWidth":20,"width":2},{"name":"status","minWidth":30,"width":5.56},{"name":"method","minWidth":30,"width":5.56},{"name":"domain","minWidth":30,"width":11.11},{"name":"file","minWidth":30,"width":27.78},{"name":"url","minWidth":30,"width":25},{"name":"initiator","minWidth":30,"width":11.11},{"name":"type","minWidth":30,"width":5.56},{"name":"transferred","minWidth":30,"width":11.11},{"name":"contentSize","minWidth":30,"width":5.56},{"name":"waterfall","minWidth":150,"width":16.67}]	
devtools.netmonitor.msg.visibleColumns	["data","time"]	
devtools.toolbox.footer.height	689	
devtools.toolbox.splitconsoleHeight	283	
devtools.toolsidebar-height.inspector	350	
devtools.toolsidebar-width.inspector	700	
devtools.toolsidebar-width.inspector.splitsidebar	350	
distribution.iniFile.exists.appversion	139.0.4-1	
distribution.iniFile.exists.value	true	
distribution.io.gitlab.librewolf-community.bookmarksProcessed	true	
dom.forms.autocomplete.formautofill	true	
dom.private-attribution.submission.enabled	false	
dom.push.userAgentID	4a964e6631f748c1abdf84ae0210962b	
dom.security.https_only_mode_ever_enabled	true	
extensions.activeThemeID	{8446b178-c865-4f5c-8ccc-1d7887811ae3}	
extensions.blocklist.pingCountVersion	0	
extensions.colorway-builtin-themes-cleanup	1	
extensions.databaseSchema	37	
extensions.formautofill.creditCards.reauth.optout	MDIEEPgAAAAAAAAAAAAAAAAAAAEwFAYIKoZIhvcNAwcECKcIXK/KBhRjBAiQBe9jTdZVVg==	
extensions.getAddons.cache.lastUpdate	1749911616	
extensions.getAddons.databaseSchema	6	
extensions.lastAppBuildId	20250612160025	
extensions.lastAppVersion	139.0.4-1	
extensions.lastPlatformVersion	139.0.4	
extensions.pendingOperations	false	
extensions.pictureinpicture.enable_picture_in_picture_overrides	true	
extensions.signatureCheckpoint	1	
extensions.systemAddonSet	{"schema":1,"addons":{}}	
extensions.ui.dictionary.hidden	true	
extensions.ui.extension.hidden	false	
extensions.ui.lastCategory	addons://list/extension	
extensions.ui.locale.hidden	true	
extensions.ui.sitepermission.hidden	true	
extensions.ui.theme.hidden	false	
extensions.webcompat.enable_shims	true	
extensions.webcompat.perform_injections	true	
extensions.webextensions.ExtensionStorageIDB.migrated.jid1-MnnxcxisBPnSXQ@jetpack	true	
extensions.webextensions.ExtensionStorageIDB.migrated.myallychou@gmail.com	true	
extensions.webextensions.ExtensionStorageIDB.migrated.tridactyl.vim@cmcaine.co.uk	true	
extensions.webextensions.ExtensionStorageIDB.migrated.uBlock0@raymondhill.net	true	
extensions.webextensions.ExtensionStorageIDB.migrated.userchrome-toggle-extended@n2ezr.ru	true	
extensions.webextensions.ExtensionStorageIDB.migrated.{3c078156-979c-498b-8990-85f7987dd929}	true	
extensions.webextensions.ExtensionStorageIDB.migrated.{3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf}	true	
extensions.webextensions.ExtensionStorageIDB.migrated.{446900e4-71c2-419f-a6a7-df9c091e268b}	true	
extensions.webextensions.ExtensionStorageIDB.migrated.{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}	true	
extensions.webextensions.uuids	{"formautofill@mozilla.org":"f4975ebb-d37b-4df9-88df-76e6a719639d","pictureinpicture@mozilla.org":"b3466f80-ff19-4cf3-a767-e3577c396fcb","addons-search-detection@mozilla.com":"d511d916-2ec8-43f1-93d9-1101e02b560a","webcompat@mozilla.org":"eba5c1eb-5481-4aa9-91f0-235c1bd226e1","default-theme@mozilla.org":"b44f98d7-fd41-4537-b2a1-62168c42410c","uBlock0@raymondhill.net":"7dbb44b4-ddeb-4afb-a916-7568aa9de6a6","{3c078156-979c-498b-8990-85f7987dd929}":"4e0857e3-a239-4851-9d42-b86a6cf9e615","jid1-MnnxcxisBPnSXQ@jetpack":"0c8c99ff-6b3e-4048-a679-b164d01b48d8","{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}":"fa026235-afd4-4a58-a13e-ae8b98d716be","tridactyl.vim@cmcaine.co.uk":"8536a553-a46d-4276-902f-ff801ce1e477","{8446b178-c865-4f5c-8ccc-1d7887811ae3}":"91e93b92-09d0-4ba4-8346-d27927b8fafc","{446900e4-71c2-419f-a6a7-df9c091e268b}":"ba515213-4b7d-472b-b2eb-289b94255f54","userchrome-toggle-extended@n2ezr.ru":"4225548e-7634-4e72-a434-7e425496fdee","{3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf}":"d32bd173-75e9-4910-a412-f6e84f51ffec","myallychou@gmail.com":"06cb2337-c4fd-4adb-b934-c99e8699746b"}	
font.name.serif.x-western	JetBrainsMono Nerd Font Mono	
gecko.handlerService.defaultHandlersVersion	1	
idle.lastDailyNotification	1749931236	
layout.css.has-selector.enabled	true	
media.gmp-manager.buildID	20250612160025	
media.gmp-manager.lastCheck	1749911858	
media.gmp-manager.lastEmptyCheck	1749911858	
media.gmp.storage.version.observed	1	
media.videocontrols.picture-in-picture.video-toggle.first-seen-secs	1749913652	
network.captive-portal-service.enabled	false	
network.connectivity-service.enabled	false	
network.http.referer.disallowCrossSiteRelaxingDefault.top_navigation	true	
network.http.speculative-parallel-limit	0	
network.predictor.enabled	false	
network.prefetch-next	false	
pdfjs.enabledCache.state	true	
pdfjs.migrationVersion	2	
permissions.delegation.enabled	false	
permissions.manager.defaultsUrl		
places.database.lastMaintenance	1749931236	
privacy.annotate_channels.strict_list.enabled	true	
privacy.bounceTrackingProtection.hasMigratedUserActivationData	true	
privacy.bounceTrackingProtection.mode	1	
privacy.clearOnShutdown_v2.browsingHistoryAndDownloads	false	
privacy.clearOnShutdown_v2.cache	false	
privacy.clearOnShutdown_v2.cookiesAndStorage	false	
privacy.fingerprintingProtection	true	
privacy.globalprivacycontrol.was_ever_enabled	true	
privacy.history.custom	true	
privacy.purge_trackers.date_in_cookie_database	0	
privacy.purge_trackers.last_purge	1749931236588	
privacy.query_stripping.enabled	true	
privacy.query_stripping.enabled.pbmode	true	
privacy.resistFingerprinting	false	
privacy.sanitize.clearOnShutdown.hasMigratedToNewPrefs3	true	
privacy.sanitize.pending	[{"id":"newtab-container","itemsToClear":[],"options":{}}]	
privacy.sanitize.sanitizeOnShutdown	false	
privacy.trackingprotection.consentmanager.skip.pbmode.enabled	false	
privacy.trackingprotection.emailtracking.enabled	true	
privacy.trackingprotection.enabled	true	
privacy.trackingprotection.socialtracking.enabled	true	
privacy.userContext.extension	tridactyl.vim@cmcaine.co.uk	
security.tls.enable_0rtt_data	false	
services.settings.clock_skew_seconds	1	
services.settings.last_etag	"1749956231754"	
services.settings.last_update_seconds	1749981096	
services.settings.main.tracking-protection-lists.last_check	1749981096	
services.settings.main.translations-models.last_check	1749981096	
services.settings.main.translations-wasm.last_check	1749981096	
services.sync.engine.addresses.available	true	
sidebar.backupState	{"command":"_3c078156-979c-498b-8990-85f7987dd929_-sidebar-action","panelOpen":true,"launcherWidth":55,"launcherExpanded":false,"launcherVisible":false}	
sidebar.new-sidebar.has-used	true	
sidebar.old-sidebar.has-used	true	
sidebar.revamp	false	
sidebar.verticalTabs	false	
sidebar.visibility	hide-sidebar	
signon.management.page.os-auth.optout	MDIEEPgAAAAAAAAAAAAAAAAAAAEwFAYIKoZIhvcNAwcECPLUpMqNsL/WBAhX3+I76muWyw==	
storage.vacuum.last.index	0	
storage.vacuum.last.places.sqlite	1749931236	
svg.context-properties.content.enabled	true	
toolkit.legacyUserProfileCustomizations.stylesheets	true	
toolkit.profiles.storeID	d963f9ba	
toolkit.startup.last_success	1749981095	
toolkit.telemetry.cachedClientID		
toolkit.telemetry.cachedProfileGroupID	ea17d95c-f415-4643-9c9a-7ded9aac0992	
toolkit.telemetry.reportingpolicy.firstRun	false	
toolkit.winRegisterApplicationRestart	false	
uc.tweak.borderless	true	
uc.tweak.no-animations	false	
uc.tweak.no-panel-hint	true	
uc.tweak.no-window-controls	true	
uc.tweak.sidebar.header	false	
uc.tweak.sidebar.wide	true	
uc.tweak.translucency	true	
uc.tweak.urlbar.not-floating	false	
webchannel.allowObject.urlWhitelist		
widget.gtk.ignore-bogus-leave-notify	1	
widget.gtk.rounded-bottom-corners.enabled	true	
widget.macos.titlebar-blend-mode.behind-window	true
Here's all the modified data
