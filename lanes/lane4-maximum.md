# Lane 4 — Maximum

**For:** situations where being wrong has serious consequences. Journalism, whistleblowing,
research on hostile subjects, evading a well-resourced adversary.

**Design principle: Tor, plus isolation Tor Browser doesn't have.**

Read [../docs/beyond-tor.md](../docs/beyond-tor.md) first if you haven't. Short version: plain
Tor Browser's weakness isn't the network, it's that **it's one process on your normal computer**.
A browser exploit escapes to your real OS, your real IP, your real disk. Lane 4 fixes exactly
that.

> **Do not build this because it sounds strong.** If your adversary is ad networks and your
> ISP, Lanes 1–3 already beat it and Lane 4 only adds friction you'll eventually abandon. Build
> it when the threat model calls for it — see the table at the end of beyond-tor.md.

---

## Choose one

| | **Tails** | **Whonix** | **Qubes-Whonix** |
|---|---|---|---|
| Form | live USB, amnesic | 2 VMs on a host | Whonix inside Qubes OS |
| Survives reboot | nothing, by design | yes | yes |
| Protects if browser is exploited | partial (amnesic) | **yes — VM boundary** | **yes — VM boundary + per-app VMs** |
| Forensic resistance on the machine | **best** | weak (host disk) | strong |
| Runs on a borrowed/untrusted PC | **yes** | no | no |
| Hardware demands | any PC + USB stick | 8 GB+ RAM | 16 GB+ RAM, specific hardware |
| Learning curve | low | medium | **high** |
| Overall strength | high | high | **highest available** |

**Pick Tails** if you need portability, amnesia, or to work on a computer you don't own.
**Pick Whonix** if you have one trusted machine and want persistent, strong isolation.
**Pick Qubes-Whonix** if you want the ceiling and will invest the time.

---

## Path A — Tails (start here)

The simplest real upgrade over Tor Browser, and it runs from a USB stick.

1. Download from [tails.net](https://tails.net) — **verify the signature**, don't skip it. The
   download page walks you through it.
2. Write to a USB stick (8 GB+). Tails' own installer handles this.
3. Boot from the stick. You may need to disable Secure Boot or pick the USB in your boot menu.
4. On the welcome screen, set an administration password only if you need one.
5. Everything routes through Tor automatically. There's no way to accidentally leak around it.

**What you get:** the whole OS is in RAM. Power off and it's gone — no disk artifacts, no
history, no forensic trace on the machine. This is what Tor Browser on Windows cannot give you.

**Persistent Storage** (optional): encrypted, on the same stick, for keys and documents. Turn
it on only if you need it — amnesia is the feature.

**Limits, honestly:** Tails runs on your hardware. It doesn't defend against firmware
implants, a hardware keylogger, or your ISP knowing you connected to Tor (use a bridge for
that). And it can't fix your behavior.

## Path B — Whonix

Two VMs, and the whole design rests on one fact: **the Workstation has no network route except
through the Gateway.** It doesn't *know* your real IP. Even a kernel exploit in the Workstation
can't leak what the VM can't see.

```
┌──────────────┐        ┌──────────────┐
│  Workstation │───────▶│   Gateway    │──▶ Tor ──▶ internet
│  (you browse)│  only  │  (runs Tor)  │
│  no real IP  │  path  │              │
└──────────────┘        └──────────────┘
```

1. Install a hypervisor — VirtualBox or KVM. (KVM is the better choice; VirtualBox is easier.)
2. Download both appliances from [whonix.org](https://www.whonix.org) — Gateway **and**
   Workstation. Verify signatures.
3. Import both. Start the Gateway first, always.
4. Browse only in the Workstation.

**Also gives you stream isolation** — different applications take different Tor circuits, so
your browsing can't be correlated with your messaging by circuit reuse.

**Do not** add a second network adapter to the Workstation. That defeats the entire design.

## Path C — Qubes-Whonix

Qubes runs every application in its own VM (a "qube") with an explicitly assigned network path.
Whonix ships as qubes. You get Tor isolation *and* per-application compartmentalization, so a
compromise in one qube can't reach another.

1. Check the [Qubes HCL](https://www.qubes-os.org/hcl/) **before** committing — hardware
   compatibility is genuinely restrictive.
2. Install Qubes OS ([qubes-os.org](https://www.qubes-os.org)). This replaces your OS. Use a
   dedicated machine.
3. Enable the Whonix qubes during setup (`sys-whonix` gateway + `anon-whonix` workstation).
4. Route sensitive qubes through `sys-whonix`; route everyday qubes through a normal VPN qube.

This is the ceiling. It's also a real commitment — budget a weekend, expect to break things.

---

## Network layer for Lane 4

- **Tor by default.** That's the point of the lane.
- **Use a bridge** if you need to hide *that you're using Tor* from your ISP or a censor:
  - **obfs4** — makes traffic look like random bytes. Fast, the usual default.
  - **WebTunnel** — wraps Tor in what looks like ordinary HTTPS/WebSocket traffic. Newest, best where deep packet inspection is aggressive.
  - **Snowflake** — peer-to-peer via WebRTC, no fixed bridge address to block.
  - Get bridges from [bridges.torproject.org](https://bridges.torproject.org).
- **VPN + Tor?** Only with a clear reason:
  - *Tor over VPN* (VPN first): your ISP sees a VPN, not Tor. Tor still can't see your real IP. Reasonable.
  - *VPN over Tor* (Tor first): complex, breaks Tor's anonymity assumptions, usually a mistake. Don't, unless you know exactly why.
- **No VPN at all** is a perfectly good Lane 4 answer — Tor alone is the designed configuration.

## The rules

Same discipline as Lane 3, harder:

- **Change nothing.** No extensions, no window resize, no settings.
- **Log into nothing** connected to any other lane. Ever.
- **No personal accounts, no personal email, no personal payment.** One login collapses everything.
- **Watch your writing.** Stylometry is real and no technology here touches it. Vary phrasing; don't reuse distinctive turns of phrase across identities.
- **Watch your clock.** Consistent posting hours reveal your timezone regardless of what the browser reports.
- **Strip metadata** from every file you share. EXIF carries GPS and device; documents carry author and revision history.
- **Never open a Lane 4 document in a Lane 1 application.** That's how people get caught.

## Verification

- [ ] [check.torproject.org](https://check.torproject.org) confirms Tor
- [ ] Whonix/Qubes: pull the Workstation's network — it must have **no** route except the Gateway
- [ ] Tails: reboot, confirm nothing persisted
- [ ] No DNS outside Tor
- [ ] Logged into nothing
- [ ] You can state, in one sentence, who you're hiding from and why this lane is the answer

That last item is the real check. If you can't answer it, you're building complexity you won't
maintain, and unmaintained complexity fails quietly.
