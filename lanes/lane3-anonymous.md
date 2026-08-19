# Lane 3 — Anonymous

**For:** research, reading, anything you want unlinked from you, anything you'd rather your ISP
and the site both stayed ignorant of.

**Design principle: join a crowd. Change nothing.**

This is the easiest lane to build and the easiest to ruin.

## Build (ten minutes, and most of it is downloading)

1. Download **[Mullvad Browser](https://mullvad.net/en/browser)** — a Firefox fork built by the
   Tor Project with Mullvad, carrying Tor Browser's anti-fingerprinting stack without Tor's
   latency. It is designed to be paired with a VPN.
2. Start your VPN. Any reputable provider; you don't need Mullvad's.
3. Open the browser.
4. **Stop. You're done.**

That is the entire configuration.

## The one rule

> **Do not customize anything.**

No extensions. No theme. No new tab page. No changed search engine. No resized window. No
`about:config`. No signing into a Mozilla account. No adding a font. No changing the security
slider unless you're raising it.

Mullvad Browser protects you by making every user byte-identical: same UA, same screen buckets,
same fonts, same canvas output, same timezone (UTC), same everything. Your anonymity *is* the
uniformity. The moment you personalize it, you're the only person on earth with that
fingerprint — inside a browser that loudly advertises "this user cares about privacy."

Customizing it is strictly worse than not using it at all.

### What that means in practice

| You want to… | Don't | Instead |
|---|---|---|
| block ads | install uBlock | it ships with uBlock Origin already configured — leave it |
| maximize the window | drag/maximize | leave it at its letterbox size; the margins are the point |
| use dark mode | switch the theme | accept light mode here, use dark in Lane 2 |
| stay logged in | log in at all | don't. That's Lane 2's job |
| add a password manager | install one | copy-paste from a desktop manager |
| use a different search | change it | it's DuckDuckGo; fine |

## The other rule

> **Never log into a Lane 1 or Lane 2 identity here.**

One login collapses the entire lane. Every page you visited in that session becomes attributable
— fingerprint uniformity does nothing once you've typed your own username. If you need to log
in, you're in the wrong lane.

## Window size and letterboxing

Mullvad Browser rounds your window to fixed dimension buckets and pads the difference with grey
margins. Those margins look like a bug. They are the feature: without them your exact window
size is a near-unique, always-available identifier that needs no permission and no API.

Resize freely — it snaps to the nearest bucket, which is correct. Just don't try to defeat it.

## Expect some friction, and don't fix it

- Occasional CAPTCHAs
- Some sites requiring a challenge page
- Rare hard blocks

This is the cost of looking like everyone else in a privacy-conscious crowd, and it is the
correct trade in this lane. **Do not "fix" it by customizing the browser** — that trades a
CAPTCHA for a unique fingerprint. If a site is unusable, open it in Lane 2 and accept that
you're being pseudonymous rather than anonymous there.

## VPN pairing

- Any reputable provider. Rotate exits freely — nothing here is logged in, so location jumping
  costs you nothing.
- Do **not** run Tor through your VPN and also use Mullvad Browser expecting Tor Browser's
  protection — Mullvad Browser is not Tor, and its threat model assumes a VPN, not onion routing.
- Leave the timezone alone. It reports UTC. That's uniform, and correct even though it won't
  match your exit IP — because every other user of this browser has the same mismatch. Uniform
  beats coherent *only* when the uniformity is large and well-known, which is exactly the case
  here.

## When to escalate to Tor Browser instead

Use **[Tor Browser](https://www.torproject.org/download/)** rather than Mullvad Browser when:

- You need to hide your activity from the VPN provider too
- You need to hide the fact that you're using a VPN from the destination
- Your adversary can observe network traffic at scale (threat model #7)
- You're doing anything where being wrong has serious consequences

Cost: much slower, far more CAPTCHAs, more hard blocks. Same rule applies — **don't customize
it**, and use the built-in security slider rather than `about:config`.

## Verification

- [ ] CreepJS lies detected = **0**
- [ ] Your fingerprint hash **matches other Mullvad Browser users** (that's the win condition here — not uniqueness)
- [ ] Timezone reports **UTC**
- [ ] Window shows letterbox margins at non-bucket sizes
- [ ] No WebRTC leak, no DNS leak
- [ ] Extensions list == exactly what shipped, nothing added
- [ ] You are logged into **nothing**
