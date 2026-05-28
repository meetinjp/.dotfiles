/****************************************************************************
 * user.js — Firefox Developer Edition profile overrides
 *
 * Layout: Fastfox (perf, curated for Linux/gentle RAM) + Peskyfox (UI annoyances).
 * Source: https://github.com/yokoffing/Betterfox
 *
 * Profile hash `1oruemyl.dev-edition-default` is per-install. On a fresh
 * machine, locate the new hash via ~/.config/mozilla/firefox/profiles.ini
 * and rename this directory before re-stowing.
 ***************************************************************************/


/****************************************************************************
 * FASTFOX — perf prefs (Linux, gentle RAM)                                 *
 ***************************************************************************/

// GPU compositor — force WebRender for consistent GPU rendering.
user_pref("gfx.webrender.all", true);

// Hardware video decode on Linux (VA-API). Offloads video to GPU.
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);

// Memory cache — store more decoded pages/images for faster revisits.
// 128 MB (default ~32 MB on 8GB+ machines).
user_pref("browser.cache.memory.capacity", 131072);
user_pref("browser.cache.memory.max_entry_size", 20480);

// Faster TLS reconnects.
user_pref("network.ssl_tokens_cache_capacity", 10240);

// Larger DNS cache, longer expiration.
user_pref("network.dnsCacheEntries", 10000);
user_pref("network.dnsCacheExpiration", 3600);

// Tab unload on low memory (default true, enforce).
user_pref("browser.tabs.unloadOnLowMemory", true);

// Linux: unload tabs when free memory drops below 20% (default 5%).
// Gentle — only kicks in under real pressure, won't unload tabs casually.
user_pref("browser.low_commit_space_threshold_percent", 20);


/****************************************************************************
 * PESKYFOX — UI annoyances (verbatim from upstream)                        *
 ***************************************************************************/

// about:addons recommendations pane (uses Google Analytics).
user_pref("extensions.getAddons.showPane", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
user_pref("browser.discovery.enabled", false);

// Stop Firefox asking to be default browser.
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

// New profile switcher.
user_pref("browser.profiles.enabled", true);

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
