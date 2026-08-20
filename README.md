# The Three-Lane Privacy Browser Plan

> Maximum privacy **and** never getting banned are not the same goal. This plan gets you both
> by refusing to chase them in the same browser.

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

Do not build one super-browser. Build three environments with different jobs, and never cross
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

**The counterintuitive rule that matters most:** in Lane 3, *do not customize anything*. No
extensions, no theme, no window resize, no settings changes. Mullvad and Tor Browser protect
you by making every user byte-identical. The moment you personalize one, you leave the crowd
and become the single most identifiable person on the network.

## What actually leaks (four layers)

| Layer | Vectors | Covered in |
|---|---|---|
| **L0 Behavior** | mouse curvature, scroll cadence, keystroke timing, session rhythm | [antipatterns.md](docs/antipatterns.md) |
| **L1 Network** | IP + reputation + geo, DNS, WebRTC, IPv6, **TLS/JA4**, HTTP/2 frame order, TCP/IP stack | [network/](network/README.md) |
| **L2 Machine** | **MAC**, hostname, Wi-Fi probes, clock skew, GPU, OS telemetry | [scripts/Harden-Windows.ps1](scripts/Harden-Windows.ps1) |
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

One file drives everything — preflight leak checks, then launches the right browser in the
right lane:

```
powershell -ExecutionPolicy Bypass -File ".\Start-Privacy.ps1"
```

It refuses to open Lanes 2 and 3 while the tunnel is down, so you can't browse "privately" over
your real IP by accident. `-Lane 3` skips the menu.

Menu keys worth knowing: `I` installs missing browsers via winget · `F` explains fingerprint
rotation · `T` runs the leak test · `H` dry-runs the Windows hardening.

Lane 2 self-configures on first launch — if the Brave profile hasn't been hardened yet, the
launcher runs [scripts/Configure-Brave.ps1](scripts/Configure-Brave.ps1) before opening it, so
the lane is never used unhardened.

Edit the `$Config` block at the top once: your expected exit country and whether Lane 2 is
Firefox or Brave.

## Start here

1. **[docs/threat-model.md](docs/threat-model.md)** — decide who you're actually hiding from. Ten minutes that saves you from doing the wrong work.
2. **[docs/coherence-matrix.md](docs/coherence-matrix.md)** — the anti-ban engine. The single most important file here.
3. **[lanes/lane1-identity.md](lanes/lane1-identity.md)** → **[lane2-daily.md](lanes/lane2-daily.md)** → **[lane3-anonymous.md](lanes/lane3-anonymous.md)** — build them in this order.
4. **[network/README.md](network/README.md)** — IP, DNS, WireGuard, kill switch, TLS fingerprint.
5. **[scripts/Harden-Windows.ps1](scripts/Harden-Windows.ps1)** — OS layer. Dry-run by default; read it before you run it.
6. **[testing/CHECKLIST.md](testing/CHECKLIST.md)** — prove it works. Do not skip.

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
