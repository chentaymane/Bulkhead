# Bulkhead

**Four sealed browsing lanes. A breach in one doesn't sink the ship.**

```
  ██████╗ ██╗   ██╗██╗     ██╗  ██╗██╗  ██╗███████╗ █████╗ ██████╗
  ██╔══██╗██║   ██║██║     ██║ ██╔╝██║  ██║██╔════╝██╔══██╗██╔══██╗
  ██████╔╝██║   ██║██║     █████╔╝ ███████║█████╗  ███████║██║  ██║
  ██╔══██╗██║   ██║██║     ██╔═██╗ ██╔══██║██╔══╝  ██╔══██║██║  ██║
  ██████╔╝╚██████╔╝███████╗██║  ██╗██║  ██║███████╗██║  ██║██████╔╝
  ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝
```

A privacy toolkit for Windows that separates **anonymity** from **not getting banned** — because
they are different goals, and chasing both in one browser is why people fail at both.

One PowerShell script: leak checks, browser hardening, OS hardening, encrypted DNS, fresh
identities per launch, and a four-lane architecture that stops them contaminating each other.

A bulkhead is the watertight wall inside a ship's hull — flood one compartment and the rest stay
dry. That's the architecture.

---

## Why this exists

Most privacy guides tell you to spoof everything. That advice gets you banned.

| Goal | Wants you to look… |
|---|---|
| **Privacy from tracking** | unlinkable — identical to a huge crowd, or different every session |
| **Not getting banned** | unremarkable — a coherent, boring, consistent human |

Modern anti-bot stacks (Cloudflare, DataDome, Akamai, Imperva, F5) score roughly **40 signals
across three layers** and look for **contradictions**. A Chrome user-agent riding a Firefox TLS
handshake is a louder alarm than no spoofing at all.

**Bans come from incoherence, not from privacy.**

A user-agent switcher changes one string and leaves behind eight Client-Hint headers, your JA4
TLS fingerprint, your HTTP/2 frame order, your fonts and your speech-synthesis voices — all
still telling the truth. You didn't become anonymous. You became *suspicious*.

Bulkhead's answer is **compartmentalization, not disguise**: four environments with different
jobs that never share a profile, a cookie jar, a fingerprint, or an identity.

## The four lanes

| | Lane 1 — Identity | Lane 2 — Daily | Lane 3 — Anonymous | Lane 4 — Maximum |
|---|---|---|---|---|
| **For** | bank, government, work | shopping, social, forums | research, reading | serious threat models |
| **Browser** | stock Edge / Firefox | Brave (or Firefox + arkenfox) | Mullvad Browser | Tails / Whonix / Qubes |
| **Fingerprint** | **real — spoof nothing** | hardened, coherent, stable | identical to all users | Tor + VM isolation |
| **IP** | home or one fixed exit | one sticky exit, your country | any exit, rotate freely | Tor |
| **Ban risk** | ~zero | low | CAPTCHAs, by design | high friction |

**Lane 1 has almost no privacy, deliberately.** Those sites already know who you are; spoofing
only triggers fraud review. Its privacy comes from *isolation* — it touches nothing else, so
nothing else can be correlated back to your legal identity.

**Lane 3's rule is: change nothing.** Mullvad and Tor Browser protect you by making every user
byte-identical. Install one extension or resize the window and you become the single most
identifiable person on the network, inside a browser that advertises "this user cares about
privacy." Customizing it is strictly worse than not using it.

## Quick start

**Requirements**

- Windows 10 or 11
- PowerShell 5.1 (built in) or PowerShell 7+
- [Brave](https://brave.com/download/) for Lane 2, [Mullvad Browser](https://mullvad.net/en/browser) for Lane 3 — the script installs both via `winget`
- A VPN for Lanes 2–3 (any reputable provider)

**Install**

```bash
git clone https://github.com/YOUR-USERNAME/bulkhead.git
```

No build step, no dependencies. Two files do the work: `Bulkhead.ps1` and `BULKHEAD.cmd`.

**Run**

Double-click `BULKHEAD.cmd`, or:

```bash
powershell -ExecutionPolicy Bypass -File ".\Bulkhead.ps1"
```

First run: press `I` to install missing browsers, `H` to harden Windows, then `2` to browse.

## Usage

| Command | What it does |
|---|---|
| `BULKHEAD.cmd` | check everything, then open the browser |
| `BULKHEAD.cmd menu` | full menu |
| `Bulkhead.ps1 -Auto` | same as double-clicking |
| `Bulkhead.ps1 -Lane 2` | launch a lane directly (`1`–`4`) |
| `Bulkhead.ps1 -Audit` | read-only audit: disk, DNS, ECH, leaks |
| `Bulkhead.ps1 -Configure` | rebuild the Lane 2 profile and identity template |
| `Bulkhead.ps1 -Harden -Apply` | OS hardening (self-elevates) |
| `Bulkhead.ps1 -Revert -Apply` | undo the hardening |

**Menu keys:** `1`–`4` lanes · `V` VPN app · `A` audit · `H` harden · `C` configure · `I` install · `U` undo · `R` re-check · `Q` quit

### Elevation

Bulkhead runs **unelevated on purpose** — browsers must never launch as administrator. Only OS
hardening needs admin, and it spawns its own elevated child process. Nothing else asks for UAC.

Every registry change is recorded to `revert-state.json`, so `-Revert -Apply` undoes all of it.

### Identity modes

Set `$Config.IdentityMode` near the top of `Bulkhead.ps1`:

| Mode | Behavior |
|---|---|
| `Fresh` *(default)* | **New identity every launch.** A clean profile is stamped from a configured template; the previous one is deleted. No cookies, no history, no logins. |
| `Persistent` | One profile kept forever. Logins and history survive. Fingerprint randomization still reseeds each launch. |

> **Fresh mode does not change your IP.** Without a VPN it buys very little — sites link you by
> IP in one step. Zero history also reads as automation, so expect more CAPTCHAs. Lane 3 does
> this natively *and* gives you a uniform fingerprint, which Fresh mode can't.

Anything that must survive a launch belongs in the **template**
(`%LOCALAPPDATA%\Bulkhead\brave-template`), not in a session.

## What it actually configures

| Layer | Handled |
|---|---|
| **Network** | WebRTC sealed, IPv6 leak check, DNS leak paths, VPN + route verification, JA4 awareness |
| **DNS** | browser-level DoH (`secure` mode, Quad9) — which also enables **ECH / encrypted SNI** |
| **OS** | LLMNR, mDNS, NetBIOS, multi-homed DNS resolution, telemetry, advertising ID, hostname, MAC guidance |
| **Browser** | WebRTC policy, farbling left on Brave's Standard, telemetry off, autofill off, per-launch identities |
| **Not touched** | user-agent, canvas, WebGL — spoofing these breaks coherence. See [antipatterns](docs/antipatterns.md). |

### Two things worth knowing

**Your MAC address never reaches a website.** It's a layer-2 identifier, stripped at the first
router hop. It matters for Wi-Fi access points and captive portals — which Bulkhead covers — but
any guide selling "MAC spoofing to avoid website bans" is selling you nothing. Your **hostname**
leaks more on a local network, via DHCP option 12, mDNS and NetBIOS.

**JA4/TLS, HTTP/2 frame order and your TCP/IP stack cannot be changed from a browser.** They're
emitted before your JavaScript exists. This is exactly why Bulkhead says *be a real browser and
don't lie about which one it is* — a hardened Firefox has a Firefox JA4, which is true, so
nothing contradicts.

## Verification

The metric that predicts bans is not uniqueness — it's **detected lies**.

Run [CreepJS](https://abrahamjuliot.github.io/creepjs/) and read the *lies* section. **Target
zero, in every lane.** A common fingerprint with zero lies beats a rare one with contradictions
every time.

Full gauntlet in [testing/CHECKLIST.md](testing/CHECKLIST.md): CreepJS, JA4 vs claimed browser,
Client-Hint consistency, WebGL/WebGPU agreement, WebRTC, DNS, IPv6, and a "does it actually
work" pass.

## Documentation

| | |
|---|---|
| [docs/threat-model.md](docs/threat-model.md) | decide who you're hiding from before building anything |
| [docs/coherence-matrix.md](docs/coherence-matrix.md) | **the anti-ban engine** — start here |
| [docs/vector-reference.md](docs/vector-reference.md) | every fingerprinting vector, per lane |
| [docs/antipatterns.md](docs/antipatterns.md) | 15 popular "privacy tips" that get you banned |
| [docs/technology-stack.md](docs/technology-stack.md) | every technology, with a ban-risk column |
| [docs/beyond-tor.md](docs/beyond-tor.md) | what "better than Tor" honestly means |
| [lanes/](lanes/) | per-lane build guides + an arkenfox override file |
| [network/](network/) | IP strategy, ECH, oblivious DNS, post-quantum, DAITA, WireGuard |
| [testing/CHECKLIST.md](testing/CHECKLIST.md) | the verification gauntlet |

## Scope and limitations

Bulkhead protects **your own browsing** from commercial tracking, fingerprinting and profiling.
"Staying unbanned" here means not tripping bot heuristics as a legitimate human user. The
compartmentalization model is deliberately the opposite of multi-accounting, and this is not a
tool for evading bans you've earned.

Be honest with yourself about what it can't do:

- **Logging in de-anonymizes you.** No fingerprint defense survives typing your own username.
- **A VPN does not make you anonymous.** It moves the observer from your ISP to a company you chose.
- **Nothing here defends a compromised endpoint.** If there's malware on the machine, every layer below is theatre.
- **Your writing style is a fingerprint.** Stylometry is real and untouched by any of this.
- **Fingerprinting changes constantly.** WebGPU was the notable 2026 arrival. This is maintenance, not a one-time build.

## Contributing

Issues and pull requests welcome. Useful contributions:

- Non-Windows ports (the architecture is OS-agnostic; the script isn't)
- Firefox/arkenfox parity with the Brave path
- New fingerprinting vectors for the reference
- Corrections — **especially** to claims that have gone stale

Please verify behavioral claims against a real browser before submitting. Several bugs in this
project were found only by writing a setting, relaunching, and reading it back — browsers
silently discard settings they don't recognize, so writing one is not proof it applied.

## License

MIT — see [LICENSE](LICENSE).
