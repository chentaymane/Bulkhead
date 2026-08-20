# Advanced network layer

Concrete configuration for the technologies in
[../docs/technology-stack.md](../docs/technology-stack.md). None of these raise your ban risk;
several lower it. This is where your remaining privacy gains actually live.

Run `scripts\Test-Advanced.ps1` to see which of these you already have.

---

## 1. ECH — close the last cleartext leak

**The problem.** You have HTTPS. You have a VPN. You have encrypted DNS. And your TLS handshake
*still* sends the hostname in cleartext, in the SNI field. Anyone watching the link past your
VPN exit — including your VPN provider — reads every site you visit.

**The fix.** Encrypted Client Hello encrypts SNI. Cloudflare enables it network-wide as of 2026;
Fastly and Akamai support it at origin.

**Two hard requirements, or it silently does nothing:**

1. **Encrypted DNS must be on.** ECH keys are delivered in DNS HTTPS/SVCB records. Plaintext DNS = no ECH, with no warning.
2. **The destination must publish ECH config.** Many still don't. Clients fall back to cleartext SNI silently.

**Enable in Brave/Chromium:** `brave://flags` → search *Encrypted ClientHello* → **Enabled**.
**Enable in Firefox:** `about:config` → `network.dns.echconfig.enabled` = `true` and
`network.dns.http3_echconfig.enabled` = `true`. Requires DoH mode 2 or 3.

**Verify:** [crypto.cloudflare.com/cdn-cgi/trace](https://crypto.cloudflare.com/cdn-cgi/trace) —
look for `sni=encrypted`. If it says `plaintext`, ECH isn't active.

> Honest limit: ECH is partial in 2026. It covers a large share of real traffic (anything behind
> Cloudflare) and costs nothing, but it is not yet universal.

---

## 2. DNS — pick one model and commit

Rule from [README.md](README.md): **one resolver, one story.** Two resolvers is how you get a
leak *and* an incoherence.

| Model | What it hides | From whom | Use when |
|---|---|---|---|
| **DoH / DoT** | query contents | your ISP | baseline — **required** |
| **DoQ** (DNS over QUIC) | same, lower latency | your ISP | if your resolver supports it |
| **DNSCrypt** | contents + authenticates the resolver | ISP + spoofers | alternative to DoH |
| **ODoH** (Oblivious DoH) | contents **and who asked** | ISP *and the resolver itself* | best available |
| **VPN-internal resolver** | everything | ISP | **simplest correct answer** |

**ODoH is the interesting one.** Normal DoH hides your queries from your ISP but hands them to
the resolver, who now knows every domain you look up *and* your IP. ODoH inserts a relay: the
relay knows who you are but not what you asked; the resolver knows what was asked but not who
asked. Neither can build your profile alone.

**Recommended for you:** VPN's own resolver, inside the tunnel. Simple, coherent, no leak. Set
`network.trr.mode = 5` in Firefox (already in the overrides) so the browser doesn't run a second
resolver behind your back.

**Without a VPN** (your situation today): enable Windows DoH —
Settings → Network → adapter → DNS server assignment → Manual → **DNS over HTTPS: On**.
Good resolvers: Quad9 `9.9.9.9`, Cloudflare `1.1.1.1`, Mullvad DNS.

**Still fix this either way:** Windows *Smart Multi-Homed Name Resolution* sends DNS out every
interface in parallel — the classic way queries escape a VPN. `scripts\Harden-Windows.ps1`
disables it.

---

## 3. Post-quantum tunnels — free, turn it on

**The threat is real and present:** *harvest now, decrypt later*. An adversary records your
encrypted traffic today and decrypts it when quantum computers arrive. Nothing you do later
helps — the recording already exists.

Mullvad's WireGuard tunnels use **Kyber-1024 (ML-KEM)** key encapsulation to defeat this.

- **Mullvad app:** Settings → VPN settings → **Quantum-resistant tunnel: On**
- **IVPN** offers equivalent PQ key exchange
- Costs: a slightly slower handshake. Nothing else.

There is no reason not to enable this.

---

## 4. DAITA — defeat traffic-analysis fingerprinting

Encryption hides *what* you send. It does not hide **packet sizes and timing**, and machine
learning models identify which website you're loading from that pattern alone, straight through
the tunnel.

**DAITA** (Defense Against AI-guided Traffic Analysis) injects padding and cover traffic to
break the pattern. Built on the open-source Maybenot framework, developed with Karlstad
University. **DAITA v2** negotiates the defense between client and relay rather than using fixed
client-side logic, which improved both performance and resistance.

- **Mullvad app:** Settings → VPN settings → **DAITA: On**
- Costs bandwidth (it's sending real cover traffic — that's the mechanism)
- Available on Windows, Linux and macOS

This is the closest thing to a Tor-grade defense available on a VPN. Turn it on.

---

## 5. Multihop — split the trust

Routes you through two servers in **different jurisdictions**, so no single server sees both
your IP and your destination.

- **Mullvad app:** Settings → VPN settings → **Multihop: On**, pick entry and exit
- Honest limit: usually the *same company* at both hops. It splits jurisdiction, not trust. Real
  distributed trust needs Tor — see [../docs/beyond-tor.md](../docs/beyond-tor.md).
- Costs latency. Worth it if your concern is legal jurisdiction; skip it otherwise.

---

## 6. Obfuscation — hide that you use a VPN at all

For networks that block or throttle VPNs.

| Method | Looks like | Use when |
|---|---|---|
| **Shadowsocks** (Mullvad bridge mode) | ordinary TLS | VPN protocol is blocked |
| **WireGuard obfuscation / udp2tcp** | generic TCP | UDP is blocked |
| **obfs4** (Tor) | random bytes | Tor is blocked |
| **WebTunnel** (Tor) | ordinary HTTPS/WebSocket | aggressive DPI |
| **Snowflake** (Tor) | WebRTC peer traffic | bridge addresses are blocked |

Only needed under censorship or restrictive networks. Adds latency. Skip unless you need it.

---

## 7. Your configuration checklist

Where you stand and what to do, in order:

| # | Item | Your status | Action |
|---|---|---|---|
| 1 | Full-disk encryption | check with `Test-Advanced.ps1` | **highest priority** |
| 2 | Multi-homed DNS off | ❌ not set | run `Harden-Windows.ps1 -Apply` |
| 3 | mDNS off | ❌ not set | same |
| 4 | Encrypted DNS | none (no VPN yet) | enable Windows DoH now |
| 5 | ECH | check flag | enable in Brave, needs #4 |
| 6 | VPN + kill switch | ❌ none | when you get an account |
| 7 | Post-quantum | n/a | toggle when VPN exists |
| 8 | DAITA | n/a | toggle when VPN exists |
| 9 | Multihop | n/a | optional |

Items 2–5 are free and available to you **today, without a VPN**. Do those now — they're the
difference between "hardened browser" and "hardened system".
