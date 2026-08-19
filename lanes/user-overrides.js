/******************************************************************************
 * user-overrides.js  —  Lane 2 "Daily" overrides for arkenfox user.js
 *
 * Target: arkenfox v144 (April 2026) or later.
 * Install: place next to user.js in your Firefox profile root, run updater.ps1.
 *
 * PHILOSOPHY
 *   arkenfox defaults aim at "as private as possible". Lane 2 aims at
 *   "as private as possible WHILE staying coherent and unbanned".
 *   Every deviation below is deliberate and explained. If a comment doesn't
 *   convince you, change it back — but change one thing at a time and re-test.
 *
 *   See ../docs/coherence-matrix.md for why coherence beats maximal spoofing.
 ******************************************************************************/

/* ===========================================================================
 * 1. FINGERPRINTING — the central decision of this file
 * ===========================================================================
 * RFP (resistFingerprinting) is Tor Browser's engine: it forces UTC timezone,
 * a spoofed generic user-agent, letterboxed window dimensions, and a uniform
 * font set. That is EXACTLY RIGHT for Lane 3, and exactly wrong here.
 *
 * In Lane 2 you have logged-in accounts and a VPN exit in your real country.
 * RFP would make you present: a German residential IP + UTC clock + a Tor-ish
 * UA + letterboxed 1000x900 window. Those facts contradict each other, and
 * contradiction is what gets scored as fraud. See docs/coherence-matrix.md.
 *
 * So: RFP OFF, FPP ON. FPP (fingerprintingProtection) applies targeted
 * per-vector defenses without the all-or-nothing identity spoofing.        */

user_pref("privacy.resistFingerprinting", false);            // arkenfox: true
user_pref("privacy.resistFingerprinting.pbmode", false);     // arkenfox: true
user_pref("privacy.resistFingerprinting.letterboxing", false);

/* FPP on in both normal and private windows. This covers canvas randomization,
 * font visibility, hardware concurrency, WebGL render info, and more — as a
 * curated target list rather than a sledgehammer.                          */
user_pref("privacy.fingerprintingProtection", true);
user_pref("privacy.fingerprintingProtection.pbmode", true);

/* Per-target tuning. Leave unset to use Mozilla's default target list, which
 * is well-chosen and updated with the browser — that is the recommendation.
 *
 * Only set this if a specific site breaks and you've identified the target.
 * Syntax: "+Target1,-Target2". The authoritative list of target names lives in
 * the Firefox source (RFPTargets.inc) — check it rather than trusting any
 * hardcoded string, including this one, since names change between releases.
 *
 * Example (commented out — a starting point, not a recommendation):
 * user_pref("privacy.fingerprintingProtection.overrides", "+AllTargets,-CSSPrefersColorScheme,-JSDateTimeUTC");
 */

/* WebGL stays ENABLED. Disabling it breaks maps, charts, and 3D, and puts you
 * in the ~0.3% of users with no WebGL at all — absence is data. FPP masks the
 * renderer string instead, which is the better trade.                       */
user_pref("webgl.disabled", false);
user_pref("webgl.enable-debug-renderer-info", false);   // hide exact GPU string

/* ===========================================================================
 * 2. STATE PARTITIONING — the highest-value setting in this whole file
 * ===========================================================================
 * dFPI / Total Cookie Protection: every site gets its own cookie jar, cache,
 * storage, and network partition. Kills cross-site linkage while keeping
 * logins and carts working. This does more for your privacy than every
 * fingerprint tweak combined.                                              */

user_pref("network.cookie.cookieBehavior", 5);
user_pref("privacy.partition.network_state", true);
user_pref("privacy.partition.serviceWorkers", true);
user_pref("privacy.partition.always_partition_third_party_non_cookie_storage", true);

/* FPI is the OLD mechanism and conflicts with dFPI. Keep it off.           */
user_pref("privacy.firstparty.isolate", false);

/* ===========================================================================
 * 3. DATA ON SHUTDOWN — clear state, but keep SOME history
 * ===========================================================================
 * A profile with zero history reads as a freshly-spawned automation profile.
 * A little accumulated browsing makes you look like a person. We clear the
 * linkable state (cookies, cache, storage) and keep history locally — history
 * never leaves your machine anyway.                                        */

user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("privacy.clearOnShutdown_v2.cookiesAndStorage", true);
user_pref("privacy.clearOnShutdown_v2.cache", true);
user_pref("privacy.clearOnShutdown_v2.formdata", true);
user_pref("privacy.clearOnShutdown_v2.browsingHistoryAndDownloads", false);  // keep

/* Keep logins for sites you allow via Firefox's "Exceptions" — set those in
 * Settings > Privacy > Cookies and Site Data > Manage Exceptions.          */

/* ===========================================================================
 * 4. WEBRTC — must not leak around the VPN
 * ===========================================================================
 * WebRTC ICE candidate gathering will happily report your real public IP and
 * your LAN IP even with a VPN up. Do NOT disable WebRTC entirely — that
 * breaks video calls and is itself a signal. Restrict it instead.          */

user_pref("media.peerconnection.enabled", true);              // keep calls working
user_pref("media.peerconnection.ice.default_address_only", true);
user_pref("media.peerconnection.ice.no_host", true);          // no LAN IPs
user_pref("media.peerconnection.ice.proxy_only_if_behind_proxy", true);

/* ===========================================================================
 * 5. DNS — resolved at the OS/VPN layer, not here
 * ===========================================================================
 * Running DoH in Firefox while your OS resolves through the VPN gives you two
 * resolvers telling two stories, and can route DNS outside the tunnel.
 * One resolver, one story. See ../network/README.md.
 *
 * mode 5 = explicitly off. If you are NOT using a VPN with its own resolver,
 * set mode 3 (DoH only) and pick a trr.uri instead.                        */

user_pref("network.trr.mode", 5);

/* Prefetch and speculative connections leak intent and bypass proxy rules.  */
user_pref("network.dns.disablePrefetch", true);
user_pref("network.prefetch-next", false);
user_pref("network.predictor.enabled", false);
user_pref("browser.urlbar.speculativeConnect.enabled", false);

/* ===========================================================================
 * 6. COMPATIBILITY BACK-OFFS — arkenfox settings that break real sites
 * ===========================================================================
 * These are arkenfox [SETUP-WEB] items. Each one is a real-world breakage in
 * a lane that has to actually work. Re-enable any you find you don't need. */

user_pref("security.ssl.require_safe_negotiation", false);  // breaks older enterprise/gov TLS
user_pref("security.cert_pinning.enforcement_level", 1);    // 2 breaks corporate MITM proxies
user_pref("dom.security.https_only_mode", true);            // keep; use the per-site bypass UI
user_pref("network.http.referer.XOriginTrimmingPolicy", 0); // 2 breaks some checkout + SSO flows

/* Keep autoplay blocking, but allow audio-less video so sites don't loop
 * "click to play" dialogs that some bot checks watch for.                  */
user_pref("media.autoplay.default", 5);

/* ===========================================================================
 * 7. TELEMETRY, ANNOYANCES, MOZILLA CALLBACKS
 * =========================================================================== */

user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("browser.contentblocking.report.lockwise.enabled", false);
user_pref("browser.contentblocking.report.monitor.enabled", false);

/* ===========================================================================
 * 8. SEARCH & UI
 * =========================================================================== */

user_pref("browser.search.suggest.enabled", false);         // don't stream keystrokes
user_pref("browser.urlbar.suggest.searches", false);
user_pref("keyword.enabled", true);                          // keep urlbar search working
user_pref("browser.formfill.enable", false);
user_pref("signon.rememberSignons", false);                  // use a real password manager

/* ===========================================================================
 * 9. THINGS DELIBERATELY *NOT* SET — and why
 * ===========================================================================
 *   general.useragent.override        -> never. Breaks coherence with JA4 and
 *                                        Client Hints. See docs/antipatterns.md #1
 *   privacy.window.maxInner*          -> letterboxing is Lane 3's job
 *   javascript.enabled = false        -> breaks the web, marks you as a bot
 *   media.peerconnection.enabled=false-> breaks calls, is itself a signal
 *   network.cookie.cookieBehavior = 1 -> blocking beats nothing; partitioning wins
 *   privacy.resistFingerprinting=true -> see section 1
 *
 * After installing: run the full gauntlet in ../testing/CHECKLIST.md.
 * Target is CreepJS "lies detected = 0", not a high uniqueness score.
 ******************************************************************************/
