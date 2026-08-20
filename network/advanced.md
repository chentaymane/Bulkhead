# Advanced network layer

Concrete configuration for the technologies in
[../docs/technology-stack.md](../docs/technology-stack.md). None of these raise your ban risk;
several lower it. This is where your remaining privacy gains actually live.

Run `Bulkhead.ps1 -Audit` to see which of these you already have.

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

**There is nothing to enable in Brave.** The `encrypted-client-hello` flag expired in Chromium
M122 and was removed — ECH graduated to **on by default**, and Brave shipped it by default ahead
of upstream Chromium. If you go looking for that flag and don't find it, that means it's already
on, not missing. (Writing the flag into `Local State` by hand doesn't work either — Brave
discards it on next launch. Verified.)

**Firefox:** `network.dns.echconfig.enabled` = `true`, requires DoH mode 2 or 3.

So the only thing standing between you and encrypted SNI is **requirement 1: turn on DoH.**

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

**Windows 10 has no DoH client.** The `*-DnsClientDohServerAddress` cmdlets and the
*DNS over HTTPS* toggle in Settings are **Windows 11 only** — on Windows 10 (any build, 22H2
included) there is no OS-level encrypted DNS to turn on. Don't go looking for it.

So on Windows 10 encrypted DNS comes from one of two places:

| Source | When |
|---|---|
| **The browser** | always — and it's what Chromium uses for ECH |
| The VPN tunnel | once a VPN is connected, it resolves inside the tunnel |

**Browser DoH is already configured** by `Bulkhead.ps1 -Configure`:

```
dns_over_https.mode      = secure
dns_over_https.templates = https://dns.quad9.net/dns-query
```

`secure` means DoH-only — no plaintext fallback, which is what ECH needs to work reliably. The
one downside: captive portals (hotel and café Wi-Fi sign-in pages) can fail to resolve until you
temporarily switch to `automatic`.

Other good resolvers if you'd rather not use Quad9: `https://cloudflare-dns.com/dns-query`,
`https://dns.mullvad.net/dns-query`.

**Still fix this either way:** Windows *Smart Multi-Homed Name Resolution* sends DNS out every
interface in parallel — the classic way queries escape a VPN. `Bulkhead.ps1 -Harden`
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

## 7. Priority order

Work down this list. Run `Bulkhead.ps1 -Audit` to see where you actually stand.

| # | Item | How |
|---|---|---|
| 1 | Full-disk encryption | BitLocker or VeraCrypt. Everything else is theatre if the disk is readable. |
| 2 | Browser encrypted DNS | `Bulkhead.ps1 -Configure` — sets `dns_over_https.mode = secure` |
| 3 | ECH / encrypted SNI | nothing to enable; it follows automatically from #2 |
| 4 | LLMNR, mDNS, multi-homed DNS off | `Bulkhead.ps1 -Harden -Apply` |
| 5 | VPN + kill switch | your provider's client |
| 6 | Post-quantum tunnel | free toggle in the VPN client |
| 7 | DAITA | free toggle in the VPN client |
| 8 | Email aliasing | SimpleLogin / addy.io — the biggest identity win available |
| 9 | Multihop | optional; splits jurisdiction, costs latency |

Items 2–4 are free and work without a VPN. Items 5–7 need one. Item 8 has nothing to do with
this tool and is probably the highest-leverage thing on the page after #1.
