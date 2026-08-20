# Lane 1 — Identity

**For:** banking, government portals, tax, insurance, healthcare, employer systems, anything
KYC'd, anything tied to your legal name, anything where a lockout is genuinely expensive.

**Design principle: do not hide. Isolate.**

These sites already know exactly who you are. Fingerprint defense buys you nothing here and
costs you a great deal — mismatched signals on a bank login look like account takeover, and the
response is a lock, a step-up challenge, or a fraud review. The privacy win in this lane is
that this browser touches *nothing else*, so nothing else can correlate with it.

## Build

**Browser:** stock Firefox (recommended) or stock Edge. Use a browser you do **not** use for
anything else. If you daily-drive Firefox in Lane 2, make Lane 1 Edge, so profile confusion is
physically impossible.

**Profile isolation** — pick one, strongest last:

| Method | Isolation | Effort |
|---|---|---|
| Separate browser application | good | none |
| Separate Firefox profile (`firefox.exe -P`) | good | 5 min |
| Separate Windows user account | strong | 15 min |
| Dedicated VM | strongest | 1 h |

For most people a **separate application plus a dedicated desktop shortcut** is the right
trade. A VM is warranted only if your threat model includes serious malware risk.

**Settings — deliberately minimal:**

- HTTPS-Only Mode: **on**
- Enhanced Tracking Protection: **Standard** (not Strict — Strict breaks bank widgets and 3-D Secure flows)
- Telemetry: off
- Password manager: use a real one (Bitwarden/KeePassXC), not the browser's
- Search: whatever you like, it doesn't matter in this lane
- **Do not** enable `privacy.resistFingerprinting`
- **Do not** install any anti-fingerprinting extension
- **Do not** spoof user-agent, canvas, WebGL, timezone, or anything else

**Extensions — exactly one:**

- uBlock Origin, default lists, no custom filters

That's it. Every additional extension is a detectable signal on a site that will act on it.

**Network:**

- Home connection, **or** one VPN exit that you never change. Both are fine; consistency is what matters.
- Never Tor.
- Never a rotating exit.
- If you use a VPN here, use the *same server* every time, forever. A bank seeing you log in
  from Amsterdam for two years is fine. A bank seeing Amsterdam → Singapore → Frankfurt in one
  week is a fraud alert.

**Discipline:**

- No other browsing in this profile. No search, no news, no links from email.
- Open links from emails by copying the URL into Lane 2 or 3 — never click through in Lane 1.
- Log out when done.
- Bookmark your banks and navigate from bookmarks only. This also kills phishing, which is a
  far more likely threat to you than fingerprinting.

## Why this looks like a contradiction and isn't

This lane has almost no privacy, by design — and that's exactly what makes the
*other* two lanes safe to push hard. Because Lane 1 is quarantined, nothing you do in Lanes 2
and 3 can ever be correlated back to your legal identity through a shared browser profile,
shared cache, shared cookie jar, or shared fingerprint.

Compartmentalization means each lane does one job well. This one's job is: never get locked
out, and never contaminate the others.

## Verification

- [ ] This browser is a different application (or profile) from Lane 2
- [ ] Exactly one extension installed
- [ ] `about:config` unmodified except telemetry
- [ ] Zero non-banking history in it
- [ ] Same exit IP every session
- [ ] CreepJS: lies detected = **0** (trivially true — you aren't lying about anything)
