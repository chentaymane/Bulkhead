# Bulkhead

*Four sealed lanes. A breach in one doesn't sink the ship.*

> Maximum privacy **and** never getting banned are not the same goal. This plan gets you both
> by refusing to chase them in the same browser.

A bulkhead is the watertight wall inside a ship's hull: flood one compartment and the rest stay
dry, so the ship stays up. That is the whole architecture here — four isolated browsing lanes
that never share a profile, a cookie jar, a fingerprint, or an identity, so a compromise in one
can't reach the others.

## The core problem

You asked for everything: IP, MAC, WebGL, all of it — without getting banned. Those two
requirements pull in opposite directions, and that tension is the whole design problem:

| Goal | Wants you to look… |
|---|---|
| **Privacy from tracking** | unlinkable — either identical to a huge crowd, or different every session |
| **Not getting banned** | unremarkable — a coherent, boring, reputable, *consistent* human |

A browser that lies about everything is **more** likely to be banned, not less. Every modern
anti-bot stack (Cloudflare, DataDome, Akamai, Imperva, F5) scores ~40 signals across three
layers and looks for **contradictions**. A Chrome user-agent riding a Firefox TLS handshake is
a louder alarm than no spoofing at all. The bans come from *incoherence*, not from privacy.

## The resolution: compartmentalize, don't disguise

Do not build one super-browser. Build four environments with different jobs, and never cross
the streams.

```
┌─ LANE 1 ── IDENTITY ────────────────────────────────────────────────┐
│ Bank, government, work, anything KYC'd, anything with your real name │
│ Browser: stock Firefox or Edge, near-zero modification              │
│ IP: home connection, or ONE consistent VPN exit, forever            │
│ Fingerprint: REAL. Do not spoof anything.                           │
│ Privacy comes from ISOLATION — this profile touches nothing else.   │
│ Ban risk: ~zero. These sites already know who you are.              │
└─────────────────────────────────────────────────────────────────────┘

┌─ LANE 2 ── DAILY ───────────────────────────────────────────────────┐
│ Shopping, forums, social, news, pseudonymous logins                 │
│ Browser: Firefox + arkenfox (tuned for compat) — or Brave           │
│ IP: one sticky VPN exit in YOUR real country/city                   │
│ Fingerprint: hardened but internally coherent, stable per identity  │
│ Ban risk: low. This is where "modify a browser" actually lives.     │
└─────────────────────────────────────────────────────────────────────┘

┌─ LANE 3 ── ANONYMOUS ───────────────────────────────────────────────┐
│ Research, reading, anything you want unlinked from you              │
│ Browser: Mullvad Browser + VPN  (or Tor Browser for maximum)        │
│ IP: VPN, rotating exits fine — or Tor                               │
│ Fingerprint: IDENTICAL to every other user of that browser          │
│ RULE: never log into a Lane 1 or Lane 2 identity here. Ever.        │
│ Ban risk: moderate — accept some CAPTCHAs as the cost.              │
└─────────────────────────────────────────────────────────────────────┘
```

```
┌─ LANE 4 ── MAXIMUM ─────────────────────────────────────────────────┐
│ Serious threat model: journalism, whistleblowing, hostile research  │
│ Not a browser — an OS: Tails / Whonix / Qubes-Whonix                │
│ Tor, PLUS the isolation plain Tor Browser doesn't have              │
│ Build only if you can say who you're hiding from in one sentence.   │
└─────────────────────────────────────────────────────────────────────┘
```

**The counterintuitive rule that matters most:** in Lane 3, *do not customize anything*. No
extensions, no theme, no window resize, no settings changes. Mullvad and Tor Browser protect
you by making every user byte-identical. The moment you personalize one, you leave the crowd
and become the single most identifiable person on the network.

## What actually leaks (four layers)

| Layer | Vectors | Covered in |
|---|---|---|
| **L0 Behavior** | mouse curvature, scroll cadence, keystroke timing, session rhythm | [antipatterns.md](docs/antipatterns.md) |
| **L1 Network** | IP + reputation + geo, DNS, WebRTC, IPv6, **TLS/JA4**, HTTP/2 frame order, TCP/IP stack | [network/](network/README.md) |
| **L2 Machine** | **MAC**, hostname, Wi-Fi probes, clock skew, GPU, OS telemetry | [Bulkhead.ps1](Bulkhead.ps1) `-Harden` |
| **L3 Browser** | canvas, **WebGL**, **WebGPU**, audio, fonts, screen, timezone, UA-CH, speech voices, +30 more | [vector-reference.md](docs/vector-reference.md) |

### About the MAC address — an important correction

**Your MAC address never reaches a website.** It is a layer-2 identifier that is stripped and
replaced at the very first router hop. No site has ever seen it, and no site ever will.

It still matters, just to a different audience: your router, your ISP's equipment, every Wi-Fi
access point in range (your device broadcasts probe requests even when not connected), captive
portals, and network administrators. That's a real tracking surface — especially for physical
location history — and the plan covers it. But it is not a web-fingerprinting vector, and any
guide that sells you "MAC spoofing to avoid website bans" is selling you nothing.

In practice your **hostname** leaks more than your MAC on a local network (DHCP option 12,
mDNS, LLMNR, NetBIOS all broadcast it, and it's often literally `CHENT-LAPTOP`). Both are
handled in the hardening script.

## Run it

**One script does everything.** Double-click `BULKHEAD.cmd`, or:

```
powershell -ExecutionPolicy Bypass -File ".\Bulkhead.ps1"
```

| | |
|---|---|
| `BULKHEAD.cmd` | double-click — checks everything, then opens the browser |
| `BULKHEAD.cmd menu` | the full menu: lanes, audit, harden, VPN, install |
| `Bulkhead.ps1 -Audit` | read-only audit — disk, DNS, ECH, leaks |
| `Bulkhead.ps1 -Harden -Apply` | OS hardening (self-elevates) |
| `Bulkhead.ps1 -Revert -Apply` | undo the hardening |

It runs **unelevated on purpose** — browsers must never launch as administrator.
The only part needing admin (OS hardening) opens its own elevated window from
the menu, and everything it changes is recorded to `revert-state.json` so it can
be undone.

It refuses to open Lanes 2 and 3 while the tunnel is down, so you can't browse
"privately" over your real IP by accident.

### Identity mode

`$Config.IdentityMode` near the top of `Bulkhead.ps1`:

| Mode | Behavior |
|---|---|
| `Fresh` *(default)* | **New identity every launch.** A clean profile is stamped from a configured template; the previous one is deleted. No cookies, no history, no logins. |
| `Persistent` | One profile kept forever. Logins and history survive. Fingerprint randomization still reseeds each launch. |

**Fresh mode does not change your IP.** Without a VPN it buys very little — sites
link you by IP in one step. It also means zero history, which reads as automation
([antipattern #12](docs/antipatterns.md)), so expect more CAPTCHAs. Lane 3 does
this natively *and* gives you a uniform fingerprint, which Fresh mode can't.

Anything you want to survive a launch must go in the **template**
(`%LOCALAPPDATA%\Bulkhead\brave-template`), not in a session, or it dies with it.

## Start here

1. **[docs/threat-model.md](docs/threat-model.md)** — decide who you're actually hiding from. Ten minutes that saves you from doing the wrong work.
2. **[docs/coherence-matrix.md](docs/coherence-matrix.md)** — the anti-ban engine. The single most important file here.
3. **[lanes/lane1-identity.md](lanes/lane1-identity.md)** → **[lane2-daily.md](lanes/lane2-daily.md)** → **[lane3-anonymous.md](lanes/lane3-anonymous.md)** — build them in this order. **[lane4-maximum.md](lanes/lane4-maximum.md)** only if the threat model demands it.
4. **[network/README.md](network/README.md)** — IP, DNS, WireGuard, kill switch, TLS fingerprint.
5. **`Bulkhead.ps1 -Harden`** — OS layer. Dry-run by default; read it before you run it.
6. **[testing/CHECKLIST.md](testing/CHECKLIST.md)** — prove it works. Do not skip.

## Going further — and where the room actually is

> **Your browser layer is already near its safe maximum. Every remaining gain is BELOW it
> (network, OS, hardware) or ABOVE it (identity, payment, behavior).**

Adding more browser spoofing from here makes you *more* detectable and *more* banned. So the
upgrade path routes around the browser entirely — and none of it raises ban risk:

- **[docs/technology-stack.md](docs/technology-stack.md)** — every available technology by layer, with a *ban risk* column
- **[docs/beyond-tor.md](docs/beyond-tor.md)** — what "better than Tor" honestly means, and the setup that achieves it
- **[network/advanced.md](network/advanced.md)** — ECH, oblivious DNS, post-quantum tunnels, DAITA, multihop, obfuscation
- **[lanes/lane4-maximum.md](lanes/lane4-maximum.md)** — Tails / Whonix / Qubes-Whonix

Audit where you stand:

```bash
powershell -ExecutionPolicy Bypass -File ".Bulkhead.ps1 -Audit"
```

Two things most people miss: **full-disk encryption** (everything else is theatre if your laptop
is taken) and **email aliasing** (your address is a stronger cross-site key than any
fingerprint — it's exact and permanent).

## The one metric that predicts bans

Forget "uniqueness score." Run [CreepJS](https://abrahamjuliot.github.io/creepjs/) and look at
**"lies detected."** That number is what anti-bot systems are actually computing. A browser
with a common fingerprint and zero detected lies sails through everything. A browser with a
rare fingerprint and twelve detected lies gets challenged on every request.

**Target: lies = 0.** Even in Lane 3.

## Build order, realistically

| Phase | Work | Time |
|---|---|---|
| 1 | Threat model + read coherence matrix | 30 min |
| 2 | VPN + DNS + WebRTC/IPv6 leak seal, verified | 1 h |
| 3 | Lane 1 profile (stock, isolated) | 20 min |
| 4 | Lane 2 (arkenfox + overrides, tuned until sites work) | 2 h |
| 5 | Lane 3 (Mullvad Browser, unmodified) | 10 min |
| 6 | Windows hardening script (MAC, hostname, telemetry) | 30 min |
| 7 | Full verification gauntlet | 1 h |

Lane 5 takes ten minutes precisely because you don't touch it. That's the point.

---

*Scope note: this is a plan for protecting your own browsing from commercial tracking,
fingerprinting, and profiling. Staying unbanned here means not tripping bot heuristics as a
legitimate human user — it isn't a guide to evading bans you've actually earned, and the
compartmentalization model is deliberately the opposite of multi-accounting.*
