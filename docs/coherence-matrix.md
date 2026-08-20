# The Coherence Matrix — the anti-ban engine

**One rule: every signal must tell the same story.**

Anti-bot systems rarely ban you for having an unusual value. They ban you for having two values
that cannot both be true. Detection is a contradiction search, not a rarity search. This file is
the checklist that keeps your story straight.

## The dependency graph

If you change anything in the left column, you must change everything in the right column to match.

| If you change… | You MUST also change | Why it burns you |
|---|---|---|
| **Exit IP country** | timezone, `Accept-Language`, `navigator.language`, `Intl` locale, currency prefs | An IP in Lisbon with an `America/New_York` clock is the oldest tell in the book |
| **User-Agent** | `Sec-CH-UA`, `Sec-CH-UA-Platform`, `Sec-CH-UA-Full-Version-List`, `Sec-CH-UA-Arch`, `Sec-CH-UA-Bitness`, `Sec-CH-UA-Platform-Version`, `Sec-CH-UA-Mobile`, **JA4 TLS fingerprint**, HTTP/2 SETTINGS + header order | UA switchers change one string and leave nine others. Client-Hint/UA mismatch is described by vendors as a *highly reliable* spoof signal |
| **Claimed browser engine** | the actual TLS ClientHello (cipher order, extensions, ALPN, GREASE) | You cannot fake JA4 from inside the page. Chrome UA + Firefox JA4 = caught at the edge, before a single line of your JS runs |
| **`navigator.platform` / OS** | installed font set, scrollbar width, `speechSynthesis` voice list, `navigator.oscpu`, path separators in file inputs, `Sec-CH-UA-Platform` | Windows UA with no Segoe UI / Calibri, or macOS UA serving Windows SAPI voices, is self-refuting |
| **WebGL vendor/renderer** | **WebGPU adapter info**, `hardwareConcurrency`, `deviceMemory`, canvas raster output, video decode capabilities | Spoofing WebGL but leaving WebGPU real is the #1 mistake of 2026. They must agree |
| **Screen resolution** | `window.inner*`/`outer*`, `devicePixelRatio`, `screen.availWidth/Height`, CSS media queries | `screen.width` 1920 with a 3000px window is impossible |
| **Timezone** | `Date.getTimezoneOffset()`, `Intl.DateTimeFormat().resolvedOptions().timeZone`, **and the actual system clock skew** | JS timezone spoofs that leave real NTP skew visible are detectable by timing correlation |
| **Language** | `Accept-Language` header, `navigator.language`, `navigator.languages`, `Intl` collation | Header and JS values disagreeing is a two-line check any vendor runs |

## The five contradictions that get you flagged fastest

1. **UA ≠ JA4.** Network-layer TLS says Firefox, page says Chrome. Fires before your JS loads. Unfixable from an extension.
2. **UA ≠ Client Hints.** `Sec-CH-UA` still reporting the version you were on before you spoofed.
3. **WebGL spoofed, WebGPU untouched.** Two GPUs on one machine.
4. **IP geo ≠ timezone ≠ locale.** The classic VPN-plus-nothing signature.
5. **Platform ≠ fonts / voices / scrollbars.** OS claims that the OS itself contradicts.

## The counterintuitive corollaries

**More spoofing ≠ more safety.** Each spoofed value is another opportunity to contradict
yourself. Every vector you fake, you now owe consistency on. This is why a stock browser behind
a good VPN often scores *better* on bot-risk than a heavily patched one.

**Randomization is dangerous if it's per-request instead of per-session.** A canvas hash that
changes between two reads *on the same page load* is not "private," it's a signature of a
naive canvas blocker — and it is itself a stable, rare fingerprint. Brave gets this right
(per-session, per-origin farbling). Most extensions get it wrong.

**Blocking a vector is a value.** `webgl.disabled = true` doesn't make you invisible; it makes
you one of the ~0.3% of users with no WebGL. Absence is data. Uniform-but-plausible beats
absent.

**Stability matters as much as content.** For any identity that persists (a logged-in account),
its fingerprint should persist too. A returning user whose fingerprint changed completely looks
like a stolen session. Randomize *across* identities, never *within* one.

## Per-lane coherence policy

| | Lane 1 Identity | Lane 2 Daily | Lane 3 Anonymous |
|---|---|---|---|
| Story told | your real machine | one consistent plausible machine | "I am a Mullvad/Tor user" |
| Spoofing | none | minimal, coherent, stable | none — handled by the browser |
| Fingerprint stability | permanent | permanent per identity | identical to all other users |
| IP | home or 1 fixed exit | 1 sticky exit, real country | any exit / Tor |
| Timezone | real | matches exit country | UTC (browser default — don't touch) |
| Expected bot score | clean | clean | occasional CAPTCHA, by design |

## Pre-flight check

Before trusting a lane, confirm on [CreepJS](https://abrahamjuliot.github.io/creepjs/):

- [ ] **Lies detected: 0**
- [ ] Canvas/WebGL/audio hashes **stable across reloads** within a session
- [ ] `Sec-CH-UA` version == UA version == `navigator.userAgentData`
- [ ] WebGL renderer and WebGPU adapter describe the *same* GPU
- [ ] Timezone == exit-IP country, and `Accept-Language` agrees
- [ ] JA4 on [tls.peet.ws/api/all](https://tls.peet.ws/api/all) matches your claimed browser
- [ ] No WebRTC candidates outside the VPN interface
- [ ] Same public IP on IPv4 **and** IPv6, or IPv6 fully disabled

Full procedure in [../testing/CHECKLIST.md](../testing/CHECKLIST.md).
