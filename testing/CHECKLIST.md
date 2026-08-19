# The verification gauntlet

A configuration you haven't tested is a guess. Run this after building each lane, after every
major browser update, and any time a site starts challenging you unexpectedly.

**Run it once per lane.** The pass criteria are different for each — that's the whole design.

---

## Stage 0 — Network layer (do this first)

Browser tests are meaningless if the tunnel leaks.

```powershell
.\scripts\Test-Leaks.ps1
```

Then externally:

| # | Test | URL | Pass criteria |
|---|---|---|---|
| 0.1 | Public IP | [ipleak.net](https://ipleak.net) | IPv4 **and** IPv6 both show the VPN, or IPv6 absent entirely |
| 0.2 | DNS leak | [dnsleaktest.com](https://dnsleaktest.com) → *Extended* | Only VPN resolvers. Your ISP's name must not appear |
| 0.3 | WebRTC | [browserleaks.com/webrtc](https://browserleaks.com/webrtc) | No `192.168.*` / `10.*` candidates, no public IP but the VPN's |
| 0.4 | Kill switch | disconnect VPN mid-download | Traffic **stops**. It does not fall back to your ISP |
| 0.5 | Geo | [cloudflare.com/cdn-cgi/trace](https://www.cloudflare.com/cdn-cgi/trace) | `loc=` is the country you intended |

**Any failure here stops the run.** Fix it before touching browser settings.

---

## Stage 1 — Coherence (the anti-ban stage)

This is the stage that predicts whether you get banned.

### 1.1 CreepJS — the single most important test

**[abrahamjuliot.github.io/creepjs](https://abrahamjuliot.github.io/creepjs/)**

Scroll to the **lies** section.

| Lane | Target |
|---|---|
| Lane 1 | 0 lies (trivially — you aren't lying) |
| Lane 2 | **0 lies** |
| Lane 3 | **0 lies** |

**Ignore the uniqueness/trust score.** Detected lies is what anti-fraud systems compute. A
common fingerprint with zero lies beats a rare one with contradictions, every time.

If you see lies, read which API is flagged and remove the thing causing it — usually an
extension, usually a UA switcher or a canvas blocker.

### 1.2 TLS fingerprint matches your claimed browser

**[tls.peet.ws/api/all](https://tls.peet.ws/api/all)** — check the `ja4` field and the parsed
user agent.

- [ ] The JA4 fingerprint corresponds to the browser you're actually running
- [ ] `user_agent` in the response matches what you expect
- [ ] They don't contradict each other

If your UA says Chrome and the JA4 says Firefox, you have a UA switcher installed. Remove it.
This check fires at the CDN edge before your JavaScript runs — nothing in the browser can fix it.

### 1.3 Client Hints match the User-Agent

**[browserleaks.com/client-hints](https://browserleaks.com/client-hints)**

- [ ] `Sec-CH-UA` brand and version == UA version
- [ ] `Sec-CH-UA-Platform` == `navigator.platform` == your real OS
- [ ] `Sec-CH-UA-Full-Version-List` consistent with the above
- [ ] `navigator.userAgentData` agrees with all of it

### 1.4 Graphics APIs agree

**[browserleaks.com/webgl](https://browserleaks.com/webgl)** and
**[browserleaks.com/webgpu](https://browserleaks.com/webgpu)**

- [ ] WebGL renderer and WebGPU adapter describe the **same** GPU
- [ ] Neither is masked while the other is real
- [ ] Lane 3: both uniform/absent

### 1.5 Locale chain agrees with the IP

- [ ] `Intl.DateTimeFormat().resolvedOptions().timeZone` matches exit country *(Lane 3 exception: UTC is correct)*
- [ ] `Accept-Language` header == `navigator.languages`
- [ ] Both plausible for the exit country

Quick console check:

```javascript
console.log({
  tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
  offset: new Date().getTimezoneOffset(),
  langs: navigator.languages,
  platform: navigator.platform,
  ua: navigator.userAgent,
  uaData: navigator.userAgentData,
  cores: navigator.hardwareConcurrency,
  mem: navigator.deviceMemory,
  screen: [screen.width, screen.height, devicePixelRatio],
  window: [innerWidth, innerHeight],
});
```

---

## Stage 2 — Fingerprint behavior

### 2.1 Stability within a session

Load [CreepJS](https://abrahamjuliot.github.io/creepjs/) **twice in the same window**.

| Lane | Canvas/WebGL/audio hashes should be… |
|---|---|
| Lane 1 | identical (real hardware) |
| Lane 2 | **identical** — farbling is per-session, not per-read |
| Lane 3 | identical (uniform values) |

**A hash that changes between two reads in one session is a bug, not privacy.** It marks you as
running a naive blocker, which is rarer and more suspicious than your real GPU.

### 2.2 Variation across sessions

Open a fresh private window (or restart) and reload.

| Lane | Expected |
|---|---|
| Lane 1 | same (that's fine, it's your real machine) |
| Lane 2 | **different** — new session, new farbling seed |
| Lane 3 | **same as every other user of this browser** |

### 2.3 Cross-site isolation

Load CreepJS, then a fingerprint demo on a different domain
([fingerprint.com/demo](https://fingerprint.com/demo)).

- [ ] Lane 2: canvas hashes **differ between the two origins** (per-origin farbling working)
- [ ] Lane 3: uniform values everywhere

### 2.4 Storage partitioning

- [ ] [browserleaks.com](https://browserleaks.com) → check for supercookie persistence
- [ ] Firefox: `about:preferences#privacy` → Total Cookie Protection active
- [ ] Brave: Shields report shows cross-site cookies blocked

---

## Stage 3 — Bot-risk reality check

Static tests say what you look like. These say how you're *scored*.

| Test | URL | Pass criteria |
|---|---|---|
| 3.1 Bot detection | [browserscan.net/bot-detection](https://www.browserscan.net/bot-detection) | "Normal browser", no automation flags |
| 3.2 Automation markers | [bot.sannysoft.com](https://bot.sannysoft.com) | all green; `webdriver` false |
| 3.3 Cloudflare challenge | any Cloudflare-fronted site | passes without an interactive challenge |
| 3.4 Uniqueness (context only) | [coveryourtracks.eff.org](https://coveryourtracks.eff.org) | read it, don't optimize it |

On 3.4: "randomized fingerprint" is a good result for Lane 2. "Nearly unique" for Lane 3 means
something is wrong — you should be blending in, so check you haven't customized it.

---

## Stage 4 — Does it actually work?

The test everyone skips and everyone should run. In each lane, do real things:

- [ ] Log in to your three most-used sites
- [ ] Add something to a cart and reach the payment page (don't buy)
- [ ] Play a video on a streaming site
- [ ] Load a site with an interactive map
- [ ] Use a site with SSO / "Sign in with…"
- [ ] Complete a form with a CAPTCHA
- [ ] Open a video call (tests WebRTC still works)
- [ ] Upload a file
- [ ] Print or export a PDF

**A lane that fails these isn't hardened, it's broken.** Back off one setting at a time,
retesting, until it passes. A configuration you disable in frustration protects nobody.

---

## Per-lane summary card

| Check | Lane 1 | Lane 2 | Lane 3 |
|---|---|---|---|
| CreepJS lies | 0 | **0** | **0** |
| Fingerprint stable in session | yes | **yes** | yes |
| Fingerprint varies across sessions | no | **yes** | no — matches all users |
| Varies across origins | no | **yes** | no |
| IP | home / 1 fixed | 1 sticky exit | any / Tor |
| Timezone == IP country | yes | **yes** | no — UTC, uniformly |
| WebRTC leak | none | none | none |
| DNS leak | none | none | none |
| JA4 == real browser | yes | yes | yes |
| Extensions | 1 | ≤3 | **exactly as shipped** |
| Logged into anything | yes, deliberately | yes, pseudonymous | **nothing** |
| Expected CAPTCHA rate | ~none | low | moderate, by design |

---

## Re-run triggers

- After any major browser version bump
- After changing VPN provider or exit country
- After installing or removing an extension
- Whenever a site suddenly starts challenging you
- Quarterly, regardless

New fingerprinting vectors ship continuously — WebGPU was the notable 2026 arrival. This is
maintenance, not a build-once project.
