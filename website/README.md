# Dromo landing page — dromo.fit

A dependency-free static marketing site for Dromo. No build step, no framework —
just `index.html`, `styles.css`, `script.js`, and `favicon.svg`. Branding mirrors
the iOS app's design tokens (dark `#080A0E`, aqua accent `#22D3EE`).

## Preview locally

```bash
cd website
python3 -m http.server 8000
# open http://localhost:8000
```

(Any static server works — opening `index.html` directly is fine too.)

## Deploy to dromo.fit (Vercel)

The GitHub repo is connected to a Vercel project, and `dromo.fit` (registered at
GoDaddy) is added as a custom domain. Vercel auto-deploys on push to `main`.

**Critical setting:** the site lives in this `website/` subfolder, so the Vercel
project's **Root Directory must be `website`** (Project → Settings → Build &
Deployment → Root Directory). Otherwise Vercel serves the repo root and 404s.
`vercel.json` (in this folder) sets clean URLs + security/cache headers; no build step.

**DNS at GoDaddy** (apex + www), as Vercel instructs:
- `A` record, host `@` → `76.76.21.21`
- `CNAME` record, host `www` → `cname.vercel-dns.com`

Vercel provisions the HTTPS cert automatically once DNS resolves.

## Remaining TODO

**Waitlist destination.** In `script.js`, `WAITLIST_ENDPOINT` is empty, so sign-ups are
validated and stored in `localStorage` (nothing is lost, but nothing is sent). Set it
to a POST endpoint that accepts `{ email }` — e.g. Formspree/Buttondown — or wire it to
Supabase (project `prftbirfbzhdacuenatw`): create a `waitlist` table with an INSERT-only
anon RLS policy and POST to its REST endpoint with the anon key.

(The `og:image` is in place — `og-image.png`, 1200×630.)

## Copy notes

Copy is deliberately honest about what ships today: pace-adaptive matching against the
user's **own** library, on-device analysis, numbers-only privacy. It avoids promising
tempo-matching for DRM streaming (a known limitation) and there's no App Store link yet
— the CTA is the waitlist, since the app is pre-launch.
