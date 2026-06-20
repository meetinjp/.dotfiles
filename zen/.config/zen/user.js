/****************************************************************************
 * user.js — Zen Browser profile overrides (Peskyfox subset of Betterfox).
 *
 * Zen is a Firefox fork; these Gecko prefs apply unchanged. The old Fastfox
 * perf block was intentionally NOT ported: its VA-API disable forced
 * software video decode (correct for the retired hybrid NVIDIA box, wrong
 * for the AMD-only Radeon 890M iGPU where renderD128 IS the AMD node).
 * Leaving VA-API at its default lets Zen use iGPU hardware video decode.
 *
 * Source: https://github.com/yokoffing/Betterfox (Peskyfox section).
 * The profile hash is per-install: install.sh resolves the active Zen
 * profile from ~/.config/zen/installs.ini + profiles.ini and symlinks the
 * stowed ~/.config/zen/user.js into <profile>/user.js (both Linux + macOS).
 ***************************************************************************/


/****************************************************************************
 * PESKYFOX — UI annoyances (verbatim from upstream)                        *
 ***************************************************************************/

// about:addons recommendations pane (uses Google Analytics).
user_pref("extensions.getAddons.showPane", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
user_pref("browser.discovery.enabled", false);

// Stop the browser asking to be default (xdg-settings already handles it).
user_pref("browser.shell.checkDefaultBrowser", false);

// Disable CFR ("Contextual Feature Recommender") extension/feature popups.
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);

// Hide "More from Mozilla" in Settings.
user_pref("browser.preferences.moreFromMozilla", false);

// Skip about:config warning.
user_pref("browser.aboutConfig.showWarning", false);

// Disable welcome screens after updates.
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);

// Theme — allow userChrome.css / userContent.css.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.compactmode.show", true);

// Match website color scheme to OS (instead of browser toolbar).
user_pref("layout.css.prefers-color-scheme.content-override", 2);

// Private windows in same taskbar group as normal windows.
user_pref("browser.privateWindowSeparation.enabled", false);

// Block all AI/ML features by default.
user_pref("browser.ai.control.default", "blocked");
user_pref("browser.ml.enable", false);
user_pref("browser.tabs.groups.smart.enabled", false);
user_pref("browser.ml.linkPreview.enabled", false);
user_pref("browser.ml.chat.enabled", false);
user_pref("browser.ml.chat.menu", false);

// Remove fullscreen transition delay.
user_pref("full-screen-api.transition-duration.enter", "0 0");
user_pref("full-screen-api.transition-duration.leave", "0 0");

// URL bar — drop search engine suggestions and trending searches.
user_pref("browser.urlbar.suggest.engines", false);
user_pref("browser.urlbar.trending.featureGate", false);

// New tab page — drop sponsored shortcuts, Pocket stories, sponsored stuff.
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredCheckboxes", false);
user_pref("browser.newtabpage.activity-stream.default.sites", "");

// Downloads — keep out of OS "recent documents".
user_pref("browser.download.manager.addToRecentDocs", false);

// Open PDF attachments inline.
user_pref("browser.download.open_pdf_attachments_inline", true);

// Bookmarks menu — don't close after selecting one.
user_pref("browser.bookmarks.openInTabClosesMenu", false);

// Restore "View image info" on right-click.
user_pref("browser.menu.showViewImageInfo", true);

// Find bar — highlight all matches.
user_pref("findbar.highlightAll", true);

// Don't gobble trailing whitespace on double-click word selection.
user_pref("layout.word_select.eat_space_to_next_word", false);

// Kill tab hover preview cards.
user_pref("browser.tabs.hoverPreview.enabled", false);
user_pref("browser.tabs.hoverPreview.showThumbnails", false);
user_pref("browser.tabs.cardPreview.enabled", false);
user_pref("browser.tabs.cardPreview.showThumbnails", false);

// Block meta-refresh / auto-reload ads.
user_pref("accessibility.blockautorefresh", true);

// Stop hoarding 15 bookmark backup copies.
user_pref("browser.bookmarks.max_backups", 1);

// Fewer URL bar dropdown results — less noise.
user_pref("browser.urlbar.maxRichResults", 5);

// Search box queries open in new tab instead of current.
user_pref("browser.search.openintab", true);
