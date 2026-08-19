# Antipatterns — the things that actually get you banned

Everything here is a popular "privacy tip" that makes your situation worse. Most bans and
CAPTCHA walls people blame on "the VPN" are actually caused by one of these.

## 1. User-agent switcher extensions

**The single worst thing on this list.** They change one string and leave behind:

- the whole `Sec-CH-UA` family still reporting the real browser and version
- `navigator.userAgentData` contradicting `navigator.userAgent`
- your **JA4 TLS fingerprint**, which the CDN read before your JS ran
- HTTP/2 SETTINGS frame order and header casing, which are engine-specific
- fonts, scrollbar width, and speech voices that belong to the real OS

Claiming to be Chrome-on-Windows while emitting a Firefox handshake from a Linux TCP stack is
about as subtle as it gets. **Never install one.**

## 2. Naive canvas / WebGL "blocker" extensions

They return random noise on *every read*. Two consequences:

- A hash that changes within a single page load is impossible for real hardware — it's a
  signature of the blocker, and a rarer one than your actual GPU.
- Sites that legitimately use canvas (maps, charts, image editors, PDF viewers, games) break.

Correct approach is per-session, per-origin *deterministic* noise — stable while you're on the
site, different across sites and sessions. Brave does this natively. Almost no extension does.

## 3. Spoofing WebGL but not WebGPU

The 2026 classic. Your WebGL says "Intel UHD 620", your WebGPU adapter says "NVIDIA RTX 4070".
One machine, two GPUs, instant flag. Handle both or neither.

## 4. Stacking twenty privacy extensions

Extensions are detectable — through `web_accessible_resources` probing, through timing how
quickly elements get hidden, through the DOM changes they make. Your specific *combination* of
extensions is high-entropy and stable: it is a fingerprint. Three well-chosen extensions beat
twenty, comfortably.

## 5. Using Tor or a rotating VPN for logged-in accounts

Location jumping between countries mid-session is the textbook account-takeover pattern. You
will get: step-up verification, SMS/2FA challenges, temporary locks, sometimes permanent bans.

**Sticky exits for anything logged in.** Rotation is for Lane 3, where you're logged into
nothing.

## 6. Timezone / locale that disagrees with your exit IP

Free, trivial, and the most common self-inflicted flag. IP says Frankfurt, browser says
`Africa/Casablanca`, `Accept-Language` says `en-US`. Pick a story and make all three tell it.

## 7. Customizing Mullvad Browser or Tor Browser

Their entire protection model is *everyone looks identical*. Install one extension, resize the
window off its letterbox bucket, change a font, switch the theme — and you are now the only
person on earth with that fingerprint, inside a browser that advertises "I care about privacy."

Strictly worse than not using it. **Leave them stock.**

## 8. Disabling JavaScript globally

Breaks most of the web, and the ~1% of users with JS off are trivially identifiable. Worse, a
site that can't fingerprint you often just defaults to treating you as a bot.

## 9. Blocking all cookies

Breaks logins, breaks carts, breaks checkout — and doesn't help, because fingerprinting exists
precisely to work without cookies. **Partition** cookies instead of blocking them: full
functionality, no cross-site linkage.

## 10. "Antidetect" browsers for normal browsing

Purpose-built for running many accounts on one machine. Consequences: their patched engines
have detectable inconsistencies, their bundled proxies have burned IP reputation, and using one
puts you in a population that anti-fraud vendors specifically profile. Being *in* that
population is itself the risk.

## 11. Cheap or free proxies and "residential" proxy pools

- Free proxies: frequently log, inject, or MITM you.
- Residential pools: often sourced from malware or dark-pattern SDKs on other people's devices;
  the IPs are shared with whatever those people are doing, so reputation is already burned, and
  when it burns further *your* account is the one holding it.

If you want clean IP reputation, use a reputable paid VPN or your own mobile connection.

## 12. Fresh browser profile per site visit

Feels private, reads as automation: no history, no cache, no cookies, no prior sessions — the
exact profile of a scraper. A little accumulated history makes you look like a person.

## 13. Chasing a "unique" score instead of a clean one

`amiunique.org` telling you you're 1-in-500,000 is not a win condition. What predicts bans is
CreepJS's **lies detected**. Optimize that to zero. A common, coherent fingerprint with no
detected lies beats a rare one with contradictions every single time.

## 14. Automating clicks in a lane that holds your identity

Behavioral signals (mouse curvature, keystroke cadence, scroll rhythm) are scored alongside the
static ones. A flawless fingerprint driving perfectly straight mouse paths still gets flagged.
Browse Lanes 1 and 2 by hand.

## 15. Building it once and never testing again

New vectors ship with every browser release. Re-run [the checklist](../testing/CHECKLIST.md)
after every major browser update, and any time a site suddenly starts challenging you.

---

## The short version

| Instead of… | Do this |
|---|---|
| lying about which browser you are | be a real browser, honestly |
| random noise every read | deterministic per-session, per-origin noise |
| twenty extensions | three: content blocker, cookie/state hygiene, HTTPS enforcement |
| blocking cookies | partitioning cookies |
| rotating IPs while logged in | one sticky exit per identity |
| customizing Tor/Mullvad Browser | leaving them exactly as shipped |
| minimizing your uniqueness score | minimizing your **detected lies** |
