# Lane 2 — Daily (pseudonymous)

**For:** shopping, forums, social media, news, streaming, developer sites, pseudonymous logins
— everything that isn't your bank and isn't sensitive research.

**Design principle: hardened, but coherent and stable.** This is the lane where "modify a
browser" actually happens. It's also where most of your web life lives, so it has to survive
contact with real sites.

## Choose your browser

Two good answers. Pick by temperament.

| | **Firefox + arkenfox** | **Brave** |
|---|---|---|
| Strategy | reduce + partition + selectively uniform | per-session per-origin randomization (farbling) |
| Control | total, hundreds of prefs | shields UI, few knobs |
| Effort | ~2 h to tune, ongoing maintenance | ~10 min, done |
| Breakage | moderate, you tune it out | low |
| Crowd | Firefox users (~2–3%) | Brave users (large, growing) |
| Handles WebGPU | via FPP targets | yes, farbled natively |
| Blocks ads | via uBlock Origin | built in |
| Best if | you want to understand and control every layer | you want strong defaults with near-zero friction |

**Recommendation:** if this is your first serious privacy build, **use Brave** for Lane 2 and
spend your effort on the network layer and Lane 3 instead — you'll get 85% of the benefit for
10% of the work, and Brave's farbling is genuinely well-engineered (deterministic per session
and per origin, which is the hard part most tools get wrong).

Choose **Firefox + arkenfox** if you want full control, don't want a Chromium engine, or want
your Lane 2 and Lane 3 to share an engine family.

---

## Path A — Firefox + arkenfox

arkenfox is at **v144 (April 2026)** and actively maintained.

**1. Fresh profile**

```bash
firefox.exe -P
```

Create a profile named `daily`. Never reuse an existing one — you'd inherit its history and state.

**2. Install arkenfox**

Download `user.js` from [github.com/arkenfox/user.js](https://github.com/arkenfox/user.js) into
the profile folder (`about:profiles` → Root Directory), along with `updater.ps1` and
`prefsCleaner.ps1`.

**3. Drop in the overrides**

Copy [`user-overrides.js`](user-overrides.js) from this folder into the same directory, then run
`updater.ps1`. It merges arkenfox + your overrides into the final `user.js`.

The overrides file is tuned for **Lane 2 specifically**: it keeps the partitioning and
anti-tracking wins, and deliberately backs off the settings that break sites or make you *more*
identifiable. Read its comments — every deviation is explained.

**4. Key decisions baked into the overrides**

| Setting | Choice | Why |
|---|---|---|
| `privacy.resistFingerprinting` | **off** | RFP forces UTC timezone + letterboxing + a spoofed UA. In a lane with logged-in accounts and a real regional IP, that's a *coherence break* — it makes you look like a Tor user with a residential German IP. Save RFP for Lane 3, where the whole browser commits to it. |
| `privacy.fingerprintingProtection` (FPP) | **on** | Targeted per-vector protection without RFP's all-or-nothing side effects. This is the right tool for Lane 2. |
| `network.cookie.cookieBehavior` | **5** (dFPI) | Total Cookie Protection: full functionality, no cross-site linkage. Doing the heaviest lifting in this file. |
| `webgl.disabled` | **false** | Disabling WebGL is itself a rare, identifying signal and breaks maps/charts. FPP handles it. |
| Sanitize on shutdown | **on, history exempt** | Clears cookies/cache; keeps some history so you don't look like a fresh-profile bot. |
| `network.trr.mode` | **5** (off) | DNS handled at the OS/VPN layer instead — see [`../network/README.md`](../network/README.md). One resolver, one story. |

**5. Extensions — three, no more**

1. **uBlock Origin** — default lists, plus *Annoyances* if you want. Do not add exotic lists.
2. **Cookie AutoDelete** *or* rely on the sanitize-on-shutdown prefs (not both — pick one).
3. Optional: a password manager.

Nothing else. See [antipatterns #4](../docs/antipatterns.md).

---

## Path B — Brave

1. Install Brave. Create a **dedicated profile** for this lane.
2. Shields → **Aggressive** ad/tracker blocking.
3. Fingerprinting protection → **Strict** *(test it; if sites break, Standard is still good)*.
4. Settings → Privacy: disable Brave Rewards, Wallet, VPN, News, Leo — every one is attack
   surface and none is privacy.
5. Enable **"Prevent sites from fingerprinting me based on my language"**.
6. WebRTC IP handling policy → **Disable non-proxied UDP**.
7. Add uBlock Origin only if you want lists Brave doesn't ship. Usually unnecessary.
8. Verify farbling: reload CreepJS twice in one session — canvas hash should be **stable**;
   open it in a fresh private window — should **differ**. That's correct behavior.

---

## Network for this lane

- **One sticky VPN exit**, in your real country and ideally your real city.
- Timezone, `Accept-Language`, and locale must match that exit — see the
  [coherence matrix](../docs/coherence-matrix.md).
- Never rotate mid-session while logged into anything.
- Kill switch on. Setup in [`../network/README.md`](../network/README.md).

**Why your real country?** Because your accounts, your shipping addresses, your payment cards,
and your language all already say that country. An exit in Panama contradicts every one of
them. The VPN's job in this lane is hiding you from your *ISP* and from *cross-site correlation
by IP* — not from the sites themselves.

## Verification

- [ ] CreepJS lies detected = **0**
- [ ] Canvas/WebGL/audio hashes stable within a session, different across sessions
- [ ] WebGL renderer and WebGPU adapter agree
- [ ] `Sec-CH-UA` version == UA version
- [ ] Timezone == exit IP country; `Accept-Language` agrees
- [ ] No WebRTC leak; no DNS leak; IPv4 and IPv6 both show the VPN
- [ ] Your ten most-used sites all work — log in, add to cart, check out, watch a video

That last one is the real test. A Lane 2 that fails it isn't hardened, it's broken. Back off
one setting at a time until it passes.
