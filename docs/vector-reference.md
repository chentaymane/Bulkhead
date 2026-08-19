# Vector reference — everything that identifies you

Complete surface, layer by layer. Columns: what it leaks → how each lane handles it.
`REAL` = pass through untouched. `UNIFORM` = same value as all other users of that browser.
`FARBLE` = per-session, per-origin deterministic noise. `SEAL` = blocked at a lower layer.

---

## L1 — Network

| Vector | What it leaks | Lane 1 | Lane 2 | Lane 3 |
|---|---|---|---|---|
| **Public IPv4** | identity, ISP, city, ASN reputation | home / 1 fixed exit | sticky VPN exit | VPN or Tor |
| **Public IPv6** | same, and *leaks around* IPv4-only VPNs | disable or tunnel | disable or tunnel | disable |
| **IP reputation** | datacenter vs residential vs mobile ASN → CAPTCHA rate | residential | VPN (shared crowd) | any |
| **rDNS / ASN** | "this is a VPN" to any vendor with a list | — | expected, fine | expected |
| **DNS resolver** | every domain you visit, to whoever runs it | DoH/DoT | DoH via VPN | VPN-internal only |
| **DNS leak** | real ISP resolver despite VPN | SEAL | SEAL | SEAL |
| **WebRTC ICE** | real public **and LAN** IP, straight past the VPN | SEAL | SEAL | SEAL |
| **TLS ClientHello → JA3/JA4** | true browser+version, at the edge, pre-JS | REAL | REAL | REAL (Firefox-uniform) |
| **HTTP/2 SETTINGS + frame order** | true browser engine | REAL | REAL | REAL |
| **HTTP header order & casing** | true browser engine | REAL | REAL | REAL |
| **TCP/IP stack (TTL, MSS, window)** | true **OS**, regardless of UA | REAL | REAL | REAL |
| **QUIC/HTTP3 fingerprint** | true browser | REAL | REAL | REAL |
| **TLS session resumption tickets** | cross-site linkage | partition | partition | disabled |
| **Clock skew vs NTP** | machine identity, survives timezone spoofing | REAL | REAL | REAL |

> **JA4, HTTP/2 and TCP fingerprints cannot be changed from inside the browser.** No extension,
> no user.js, no flag. They are emitted by the network stack before your JS exists. This is
> exactly why the plan says *use a real browser and don't lie about which one it is*.

## L2 — Machine / OS / local network

| Vector | What it leaks | Handling |
|---|---|---|
| **MAC address** | device identity **to your LAN only — never to websites** | Windows random hardware addresses, per-network |
| **Wi-Fi probe requests** | your saved-SSID list → your location history | disable auto-connect, forget stale networks |
| **Hostname** | often your literal name, via DHCP opt-12 / mDNS / LLMNR / NetBIOS | rename to a neutral string; disable LLMNR/NetBIOS |
| **Bluetooth MAC + name** | device identity, proximity tracking | off when unused |
| **Windows telemetry / advertising ID** | usage, device ID, cross-app tracking | disabled in hardening script |
| **GPU model** | strong, near-permanent hardware ID via WebGL/WebGPU | see L3 |
| **Installed fonts** | OS + locale + installed software (very high entropy) | see L3 |
| **Battery / charging state** | short-term cross-site linkage | API absent in Firefox |

## L3 — Browser

### Graphics — the heaviest hitters

| Vector | What it leaks | Lane 1 | Lane 2 | Lane 3 |
|---|---|---|---|---|
| **Canvas 2D readback** | GPU + driver + font rasterizer, very stable | REAL | FARBLE | UNIFORM |
| **WebGL vendor/renderer** | exact GPU string, e.g. ANGLE (NVIDIA RTX 4070...) | REAL | FARBLE/mask | UNIFORM |
| **WebGL parameters + extensions** | driver version, capability set | REAL | FARBLE | UNIFORM |
| **WebGPU adapter + limits** | *the 2026 vector* — finer-grained than WebGL | REAL | FARBLE | disabled |
| **WebGPU shader compile timing** | real GPU, even when adapter info is masked | REAL | noise | disabled |
| **ClientRects / text metrics** | font rendering + DPI | REAL | FARBLE | UNIFORM |
| **Video decode capabilities** | hardware codec support → GPU class | REAL | REAL | UNIFORM |

> **Spoof WebGL and WebGPU together or neither.** Masking one while the other reports your real
> adapter is a self-contradiction — see [coherence-matrix.md](coherence-matrix.md).

### Audio

| Vector | What it leaks | Lane 1 | Lane 2 | Lane 3 |
|---|---|---|---|---|
| **AudioContext / OfflineAudioContext** | audio stack + floating-point behavior | REAL | FARBLE | UNIFORM |
| **speechSynthesis.getVoices()** | **OS and installed language packs** | REAL | trimmed | UNIFORM |
| **Speech synthesis *timing*** | the real TTS engine, even when the voice list is faked | REAL | REAL | disabled |
| **enumerateDevices()** | count of mics/cams/speakers | REAL | count only | UNIFORM |

### Display & environment

| Vector | Lane 1 | Lane 2 | Lane 3 |
|---|---|---|---|
| screen.width/height, availWidth/Height, colorDepth | REAL | REAL | UNIFORM |
| window.inner* / outer* | REAL | REAL | **letterboxed to buckets** |
| devicePixelRatio | REAL | REAL | 1 |
| prefers-color-scheme, prefers-reduced-motion, forced-colors | REAL | REAL | UNIFORM (light) |
| **scrollbar width** (leaks OS + theme) | REAL | REAL | UNIFORM |
| navigator.hardwareConcurrency | REAL | capped | 2 |
| navigator.deviceMemory | REAL | capped | undefined |

### Identity strings

| Vector | Note |
|---|---|
| User-Agent | change it and you owe the whole Client-Hints family + JA4 |
| **Sec-CH-UA family (8 headers)** | the part every naive spoofer forgets |
| navigator.userAgentData | JS mirror of the above; must agree |
| navigator.platform / oscpu | must agree with fonts, voices, scrollbars |
| Accept-Language / navigator.languages | must agree with each other **and your exit IP** |
| **Timezone** (Intl, getTimezoneOffset) | must agree with exit IP |
| navigator.plugins / mimeTypes | mostly legacy, still checked as a bot tell |

### Fonts

| Vector | What it leaks | Lane 1 | Lane 2 | Lane 3 |
|---|---|---|---|---|
| Font enumeration (Local Font Access) | installed software + OS + locale | REAL | blocked | blocked |
| **Font metric probing** (measure a string in font X) | the same list, without any API | REAL | allowlist | bundled set only |
| System font settings / default sizes | OS theme | REAL | REAL | UNIFORM |

Metric probing is the one that matters — it works with pure CSS and needs no permission. Lane 3
answers it by shipping its own font set and refusing all local fonts.

### Storage & state (linkage, not fingerprinting)

| Vector | Handling |
|---|---|
| Cookies, localStorage, sessionStorage, IndexedDB | partitioned per top-level site (dFPI / Total Cookie Protection) |
| HTTP cache, image cache, favicon cache | partitioned |
| **ETag / Last-Modified supercookies** | partitioned |
| **HSTS supercookies** | partitioned / cleared |
| Service workers, CacheStorage, BFCache | partitioned |
| TLS + HTTP/3 session resumption | partitioned |
| window.name | cleared on navigation |
| Blob / BroadcastChannel / SharedWorker cross-tab | partitioned |
| **storage.estimate() quota** | leaks disk size → capped/quantized |

Partitioning is doing more work for your privacy than any fingerprint tweak. It is on by default
in modern Firefox and Brave; verify it, don't rebuild it.

### Misc / high-entropy leftovers

navigator.connection (network type + downlink) · Gamepad API · getInstalledRelatedApps() ·
Permissions API state (notifications:denied is itself a signal) · WebAssembly feature set ·
Math / Intl implementation quirks · performance.now() resolution · requestAnimationFrame
cadence (**leaks true refresh rate**) · CSS @supports feature probing · PDF viewer presence ·
autofill + keyboard layout · Notification.permission · Web Share / Bluetooth / Serial / HID
presence · **extension detection** (probing web_accessible_resources, or timing how fast
elements get hidden — *your ad blocker is itself a fingerprint*)

## L0 — Behavior

Rarely discussed, increasingly the deciding signal once the static layers look clean.

| Signal | Human | Bot |
|---|---|---|
| Mouse path | curved, jittery, overshoots and corrects | straight lines, exact endpoints |
| Click timing | variable, with pre-click hover | uniform intervals |
| Keystrokes | variable dwell/flight, typos, backspaces | perfect, constant cadence |
| Scroll | uneven, momentum, over/under-shoot | fixed pixel deltas |
| Navigation | reads, pauses, backtracks | instant, optimal path |
| Focus events | tab-outs, window blur | never |

If you browse by hand you pass this for free. It is listed because it is the reason "perfect"
automated setups still get flagged with a spotless static fingerprint — and the reason you
should never let a tool click through pages for you in Lane 1 or Lane 2.

---

## Reality check on entropy

Rough real-world contribution to uniqueness, highest first:

1. Canvas + WebGL + WebGPU (your GPU is nearly a serial number)
2. Font list
3. UA + version + platform
4. Screen geometry + devicePixelRatio
5. Timezone + language
6. Audio stack
7. Hardware concurrency + memory
8. Everything else, individually small — collectively decisive

You cannot reach zero. **Uniform** and **coherent** are achievable; **invisible** is not. This
plan optimizes for the two that exist.
