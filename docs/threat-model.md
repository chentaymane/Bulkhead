# Threat model — decide who you're hiding from

Ten minutes here saves you from doing the wrong work for a month. "Privacy" against an ad
network and "privacy" against your ISP are almost unrelated engineering problems.

## Pick your adversaries

| # | Adversary | Sees | Beaten by | Cost to you |
|---|---|---|---|---|
| 1 | **Ad/analytics networks** (Google, Meta, TikTok pixels, data brokers) | cross-site behavior, fingerprint, cookies | content blocking + state partitioning + fingerprint defense | ~none |
| 2 | **The site you're on** | your fingerprint, your account, your behavior | compartmentalization; not the same browser as everything else | low |
| 3 | **Anti-fraud vendors** (Cloudflare, DataDome, Akamai, Imperva, F5) | IP reputation, JA4, ~40 browser signals, behavior | **coherence** — this is the ban risk, and defense here means spoofing *less* | low |
| 4 | **Your ISP / network operator** | every domain you resolve and connect to, timing, volume | VPN + encrypted DNS | small $ |
| 5 | **Local network / Wi-Fi operators** | MAC, hostname, mDNS chatter, probe requests, device inventory | MAC + hostname randomization | ~none |
| 6 | **Your VPN provider** | what your ISP used to see | provider choice, audits, no-log, multihop, paying in cash/XMR | trust shift |
| 7 | **Global passive adversary / state** | correlation across the whole network | Tor, Whonix, Qubes, Tails — and real discipline | high, disruptive |

**Most people need 1–5.** They're cheap, they compose cleanly, and none of them require
giving up a usable web. Number 6 is a decision, not a configuration — a VPN doesn't delete the
observer, it *moves* it from your ISP to a company you chose. Number 7 changes how you live and
is out of scope here unless you say otherwise.

## Where your effort should actually go

Ranked by privacy gained per unit of pain, for a normal person on a normal Windows machine:

1. **Content blocking** — uBlock Origin in every lane. Kills the majority of vector 1 outright, costs nothing, breaks almost nothing.
2. **Compartmentalization** — the three lanes. Highest-value structural change in this plan.
3. **State partitioning** — cookies/cache/storage keyed per top-level site. Already default in modern Firefox (Total Cookie Protection) and Brave.
4. **VPN + encrypted DNS + leak sealing** — one evening, then permanent.
5. **Fingerprint defense** — necessary, but genuinely the *fourth* priority, and the one where overdoing it backfires.
6. **OS/local-network hardening** — MAC, hostname, telemetry. Cheap, do it once.
7. **Behavioral discipline** — free, and the one nobody does.

The common failure is starting at #5, installing fourteen anti-fingerprinting extensions,
skipping #1–#4, and ending up both *more* trackable and *more* banned.

## Things this plan will not do for you

Be honest with yourself about these:

- **Logging in de-anonymizes you.** No amount of fingerprint defense survives typing your own username. Compartmentalization is what protects you here, not obfuscation.
- **Payment de-anonymizes you.** A card number is a stronger identifier than any fingerprint.
- **Your writing style is a fingerprint.** Stylometry is real and this plan doesn't touch it.
- **Nothing here is a defense against malware on your machine.** If the endpoint is compromised, every layer below is theater.
- **A VPN does not make you anonymous.** It relocates trust and hides you from your ISP. That's it — and it's genuinely worth it, just don't buy the marketing.
- **Fingerprint defense is not permanent.** New vectors ship every browser release (WebGPU was the 2026 arrival). This is maintenance, not a one-time build.

## Your answers

Fill this in before building. It determines every choice downstream.

```
Primary adversaries (numbers from the table):  ______
Acceptable friction (none / some / high):      ______
Region my IP should appear to be in:           ______
Sites I cannot afford to be locked out of:     ______
Am I trying to hide from my ISP? (y/n)         ______
Am I trying to hide from a nation-state? (y/n) ______   <- if yes, this plan is not enough
```

If "sites I cannot afford to be locked out of" is a long list, weight everything toward Lane 1
discipline and keep Lane 2 conservative. If it's empty, you can push Lane 2 much harder.
