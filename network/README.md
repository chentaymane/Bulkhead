# Network layer — IP, DNS, leaks, and the fingerprints you can't change

This layer runs *underneath* every browser. Get it right once and all three lanes inherit it.

---

## 1. Choosing an exit IP

Your IP contributes two things: **location** and **reputation**. Reputation is what decides
whether you see a CAPTCHA on every page.

| Option | Anonymity | Reputation | Speed | Verdict |
|---|---|---|---|---|
| **Home ISP** | none | excellent | best | Lane 1 only |
| **Reputable paid VPN** (Mullvad, IVPN, Proton) | good — shared with thousands | good, occasional CAPTCHAs | good | **Lanes 2 and 3. The default answer.** |
| **Your own VPS + WireGuard** | poor — a crowd of one | clean but datacenter ASN | best | good against your ISP, bad for anonymity |
| **Mobile tether / CGNAT** | good — huge shared pool | excellent | variable | best reputation available; use when a site is stubborn |
| **Tor** | excellent | poor — many hard blocks | slow | Lane 3 escalation |
| **Free proxies** | negative | burned | bad | never |
| **Residential proxy pools** | apparent, not real | burned + ethically fraught | variable | see note below |

**Recommendation: one reputable paid VPN with WireGuard, sticky exit for Lane 2, free rotation
for Lane 3.** Pay with a method that isn't tied to your name if that's in your threat model;
pay however you like if it isn't.

**On residential proxy pools:** they're marketed as the answer to IP-reputation checks. In
practice much of that capacity comes from malware or dark-pattern SDKs running on other
people's devices, the IPs are shared with whatever those people are doing, and reputation is
frequently already burned. Pointing a logged-in account at one is a good way to lose the
account when the IP gets flagged. If you want clean reputation, tether to your phone.

**Why a VPS is worse than it sounds:** a dedicated IP means every request from that address is
you. You've traded "one of 5,000 Mullvad users in Frankfurt" for "the only person who has ever
used 203.0.113.44." Excellent against your ISP, useless against the sites themselves.

---

## 2. WireGuard setup

Use your provider's config generator (Mullvad, IVPN, and Proton all emit WireGuard configs
directly). [`wireguard-template.conf`](wireguard-template.conf) documents what each field does
and which ones matter for leak prevention.

Key points:

- **`AllowedIPs = 0.0.0.0/0, ::/0`** — route *everything*, including IPv6. If you route only
  IPv4, IPv6 traffic goes around the tunnel in the clear. This is the single most common leak.
- **`DNS = <provider resolver>`** — resolve inside the tunnel.
- **Pick one server and stay on it** for Lane 2.
- Multihop only if your threat model includes the VPN provider itself; it costs latency and
  doesn't help against fingerprinting at all.

---

## 3. Kill switch — non-negotiable

Without one, every VPN reconnect leaks your real IP for a few seconds — long enough for a
background tab to phone home from it.

Three ways, strongest last:

1. **Provider app kill switch** — easiest, usually sufficient, enable it.
2. **WireGuard `PostUp`/`PostDown` firewall rules** — see the template.
3. **Windows Firewall outbound block rules** — belt and braces. The
   [`../scripts/Harden-Windows.ps1`](../scripts/Harden-Windows.ps1) script can install rules
   that permit outbound traffic only on the WireGuard interface.

Test it by pulling the VPN mid-download. Traffic should **stop**, not fall back.

---

## 4. DNS

Rule: **one resolver, one story.** Two resolvers is how you get a DNS leak *and* a coherence
break.

**If you use a VPN (recommended):** let the VPN's resolver handle everything. Set
`network.trr.mode = 5` in Firefox (already in the Lane 2 overrides) and turn off Windows DoH.
Your DNS goes through the tunnel, which is exactly what you want.

**If you don't use a VPN:** use encrypted DNS at the OS level — Windows 11/10 supports DoH
natively (Settings → Network → your adapter → DNS server assignment → Manual → *DNS over HTTPS:
On*). Reasonable resolvers: Quad9 (`9.9.9.9`), Mullvad DNS, Cloudflare (`1.1.1.1`).

**Either way, disable these leak paths** (the hardening script does it):

- LLMNR — broadcasts your queries to the local network
- NetBIOS over TCP/IP — same, plus your hostname
- mDNS — same, plus a device inventory
- "Smart Multi-Homed Name Resolution" — sends queries out *every* interface in parallel, the classic Windows VPN leak

Verify at [dnsleaktest.com](https://dnsleaktest.com) (extended test) — you should see **only**
your VPN's resolver, never your ISP's.

---

## 5. IPv6 — the leak everyone forgets

If your ISP gives you IPv6 and your VPN doesn't carry it, sites reach you over IPv6 at your real
address while you admire your VPN's IPv4. Two acceptable outcomes:

- **Tunnel it:** `AllowedIPs` includes `::/0` and your provider assigns an IPv6 address. Best.
- **Disable it:** turn IPv6 off on the adapter. Fine, slightly unusual, harmless.

Unacceptable: IPv6 enabled and untunneled. Verify at [ipleak.net](https://ipleak.net) — the
IPv4 and IPv6 results must either match your VPN or the IPv6 must be absent.

---

## 6. WebRTC

WebRTC gathers ICE candidates by asking your OS for every local and public address it can find —
straight past the VPN, from inside the page. Handled per-lane:

- **Firefox (Lane 2):** `media.peerconnection.ice.no_host` + `default_address_only` — in the overrides file.
- **Brave:** Settings → WebRTC IP handling policy → **Disable non-proxied UDP**.
- **Mullvad/Tor Browser:** already handled.

Don't disable WebRTC outright — it breaks video calls and having it missing is its own signal.

Verify at [browserleaks.com/webrtc](https://browserleaks.com/webrtc): you should see **no**
local (`192.168.x`/`10.x`) candidates and no public IP other than the VPN's.

---

## 7. The fingerprints you cannot change

Honest limits. These are emitted by the OS network stack and the TLS library before any
browser code runs, and **nothing in userland fixes them**:

| Fingerprint | Reveals | Changeable? |
|---|---|---|
| **JA3 / JA4 TLS ClientHello** | true browser + version | No — it's your TLS stack |
| **HTTP/2 SETTINGS + frame order** | true browser engine | No |
| **HTTP header order and casing** | true browser engine | No |
| **TCP/IP stack (TTL, MSS, window scaling)** | true **OS** | Only by patching the kernel |
| **QUIC transport parameters** | true browser | No |

JA4 is the current standard and is used as a primary edge signal by Cloudflare, Akamai,
DataDome, Imperva, F5 and AWS WAF. It fires at the handshake — **before** your JavaScript
exists, before any extension can act.

**This is the technical reason the whole plan says "be a real browser, honestly."** You can
harden a real Firefox all you want and its JA4 still says "Firefox," which is true, so nothing
contradicts. Announce yourself as Chrome and the contradiction is visible at the edge, and no
amount of in-page spoofing can reach down and fix it.

Check yours: [tls.peet.ws/api/all](https://tls.peet.ws/api/all) or
[browserleaks.com/tls](https://browserleaks.com/tls). Confirm the reported browser matches the
browser you're actually running. It will, as long as you haven't installed a UA switcher.

---

## 8. Verification order

Run in this order — later checks are meaningless if earlier ones fail:

1. `curl https://ifconfig.me` → VPN IP?
2. [ipleak.net](https://ipleak.net) → IPv4 **and** IPv6 both VPN (or IPv6 absent)?
3. [dnsleaktest.com](https://dnsleaktest.com) extended → only VPN resolvers?
4. [browserleaks.com/webrtc](https://browserleaks.com/webrtc) → no local, no real public IP?
5. Kill the VPN mid-transfer → traffic stops?
6. [tls.peet.ws/api/all](https://tls.peet.ws/api/all) → JA4 matches your real browser?
7. [Cloudflare trace](https://www.cloudflare.com/cdn-cgi/trace) → `loc` matches your intended country?

Full browser-layer gauntlet in [`../testing/CHECKLIST.md`](../testing/CHECKLIST.md).
