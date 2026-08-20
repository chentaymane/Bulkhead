# The complete technology stack

Everything available, by layer, with the column that matters: **does adding this raise your ban
risk?**

Read the ban-risk column first. It's why this list is ordered the way it is — nearly every
remaining gain sits *below* the browser, where privacy is free. The browser layer is already at
its safe maximum.

Legend: **⬇ lowers** ban risk · **— neutral** · **⬆ raises** it

---

## Layer −1: Hardware

| Technology | What it buys | Ban risk | Priority |
|---|---|---|---|
| **Full-disk encryption** (BitLocker w/ TPM+PIN, or VeraCrypt) | everything below is theatre if the disk is readable | — | **do this first** |
| Secure Boot + TPM 2.0 | blocks bootkits and evil-maid persistence | — | high |
| Separate physical device for Lane 4 | strongest possible compartmentalization | — | if threat model warrants |
| Hardware kill switches / camera cover / mic disable | defeats endpoint capture | — | cheap, do it |
| Removing Intel ME / AMD PSP | closes a ring −3 blob | — | rarely practical |
| Faraday bag | defeats radio-based location | — | niche |

FDE is the highest-value item on this entire page and most people skip it. Everything else
assumes an adversary on the network. FDE is the only thing that helps when the adversary has
your laptop.

## Layer 0: Operating system

| Technology | What it buys | Ban risk | Priority |
|---|---|---|---|
| **MAC randomization** (per-network) | defeats Wi-Fi/venue tracking | — | done ✅ |
| **Neutral hostname** | stops broadcasting your name via DHCP/mDNS/NetBIOS | — | done ✅ |
| **LLMNR / mDNS / NetBIOS off** | stops LAN query broadcast | — | done ✅ |
| **Smart multi-homed DNS off** | closes the classic Windows VPN DNS leak | ⬇ | **do now** |
| Telemetry + advertising ID off | cuts OS-level cross-app tracking | — | done ✅ |
| **Amnesic OS** (Tails) | nothing survives reboot; forensics resistance | — | Lane 4 |
| **VM isolation** (Whonix, Qubes) | a browser exploit can't reach your real IP or disk | — | Lane 4 |
| RAM-only browsing / tmpfs profile | no disk artifacts | — | Lane 4 |
| Secure delete / SSD TRIM awareness | deleted ≠ gone on SSDs | — | medium |
| Sandboxing (WDAC, AppContainer) | limits exploit blast radius | — | medium |

## Layer 1: Network — where the remaining wins are

| Technology | What it buys | Ban risk | Priority |
|---|---|---|---|
| **VPN (WireGuard)** | hides you from your ISP; IP crowding | ⬇ vs Tor | **required** |
| **Kill switch** | no leak on reconnect | — | **required** |
| **IPv6 tunneled or disabled** | closes the leak that bypasses v4 tunnels | — | **required** |
| **Encrypted DNS** (DoH / DoT / DoQ) | your resolver stops seeing plaintext queries | — | **required** |
| **DNSCrypt** | authenticated resolver, anti-spoofing | — | alternative to DoH |
| **Oblivious DoH (ODoH)** | relay splits *who asked* from *what was asked* — resolver can't link queries to you | — | high, where supported |
| **ECH (Encrypted Client Hello)** | encrypts the SNI — **the last cleartext field in HTTPS**, the one that still tells your ISP every hostname you visit | — | **high — see below** |
| **Post-quantum tunnel** (ML-KEM/Kyber-1024) | defeats *harvest-now-decrypt-later* | — | high, free |
| **DAITA** (Mullvad) | injects cover traffic + padding to defeat ML traffic-analysis fingerprinting even under encryption | — | high, free |
| **Multihop** | splits trust across two jurisdictions | — | medium |
| **Obfuscation** (Shadowsocks, WireGuard obfs) | hides *that you're using a VPN* | — | if censored |
| **Tor bridges** (obfs4 / Snowflake / WebTunnel) | reaches Tor where it's blocked; WebTunnel mimics ordinary HTTPS | — | Lane 4, if censored |
| Own VPS exit | clean reputation, dedicated | ⬆ crowd of one | usually a mistake |
| Residential proxies | apparent residential reputation | ⬆⬆ burned IPs, dubious sourcing | **avoid** |

### ECH is the one most people are missing

Even with a VPN and encrypted DNS, the **SNI field in your TLS handshake still sends the
hostname in cleartext**. Your VPN provider — and anyone who taps the link past the exit — reads
every site you visit, despite the "encrypted" tunnel.

ECH closes it. As of 2026 Cloudflare enables ECH across its network, and Fastly and Akamai
support it at origin. Two hard requirements:

1. **Encrypted DNS must be on.** ECH keys arrive via DNS HTTPS/SVCB records. Plaintext DNS = no ECH, silently.
2. **The destination must publish ECH config.** Many still don't, and clients fall back to cleartext SNI without telling you.

So ECH is partial today — but free, and it covers a large share of real traffic.

## Layer 2: Browser — already at safe maximum

| Technology | Status | Ban risk if pushed further |
|---|---|---|
| Farbling (canvas/WebGL/WebGPU/audio/fonts) | ✅ Brave Standard | ⬆ Strict adds breakage |
| State partitioning | ✅ default | — |
| WebRTC sealed | ✅ configured | — |
| Content blocking | ✅ | — |
| Uniform fingerprint | ✅ Lane 3 | ⬆ if customized |
| UA spoofing | ❌ never | ⬆⬆⬆ contradicts JA4 |
| Canvas blocker extensions | ❌ never | ⬆⬆ per-read noise is a signature |
| More extensions | ❌ cap at 3 | ⬆ combination is a fingerprint |

**Nothing left to add here safely.** That's the finding, not a gap.

## Layer 3: Identity — usually the actual weakest link

| Technology | What it buys | Ban risk | Priority |
|---|---|---|---|
| **Email aliasing** (SimpleLogin, addy.io, Fastmail masked) | unique address per site; kills the email-as-identity join key | — | **very high** |
| **Separate email per lane** | breaks cross-lane correlation | — | **very high** |
| **Virtual / single-use cards** | payment stops being a global identifier | — | high |
| Monero, or cash-bought vouchers | unlinkable payment where accepted | — | Lane 4 |
| **Password manager, unique passwords** | credential stuffing + reuse correlation | ⬇ | **required** |
| Separate phone number / eSIM | SMS 2FA stops linking identities | — | medium |
| Private search (SearXNG, DuckDuckGo, Brave) | query history stops being profiled | — | high |
| Self-hosted SearXNG | removes even the search provider | — | advanced |

Your email address is the single strongest cross-site join key in existence — stronger than any
fingerprint, because it's exact and permanent. Aliasing is the highest-leverage thing on this
page after FDE, and it costs almost nothing.

## Layer 4: Behavior — free, and nobody does it

| Technology | What it buys | Priority |
|---|---|---|
| **Never cross lanes** | the whole architecture depends on it | **absolute** |
| Session discipline (one identity per session) | prevents fingerprint+cookie joins | high |
| **Stylometry awareness** | your writing identifies you; nothing technical touches this | high for Lane 4 |
| Timing discipline | posting hours leak your timezone regardless of settings | medium |
| Metadata scrubbing (EXIF, docs) | photos and documents carry GPS, device, author | high |
| No automation in Lanes 1–2 | mouse/keystroke cadence is scored | medium |

---

## What to do next, ranked by value per effort

1. **Full-disk encryption** — nothing else matters if the disk is readable
2. **Finish the DNS hardening** — multi-homed DNS off, the leak you still have
3. **Encrypted DNS + ECH** — closes the last cleartext hostname leak
4. **Email aliasing** — biggest identity win available, near-zero effort
5. **VPN with PQ + DAITA** — when you get an account; both are free toggles
6. **Lane 4** — only if your threat model genuinely calls for it

Concrete configuration for 2, 3 and 5 is in [../network/advanced.md](../network/advanced.md).
Lane 4 build guide is in [../lanes/lane4-maximum.md](../lanes/lane4-maximum.md).
