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

## Waitlist

Sign-ups POST into the `waitlist` table of Supabase project `prftbirfbzhdacuenatw`
(`script.js` → `submit()`). RLS is **insert-only** for the public: the publishable key
embedded in the page can add a row but cannot read the list, so emails can't be scraped.
Duplicate emails return 409 and are treated as success. **Read sign-ups in the Supabase
dashboard → Table editor → `waitlist`** (or via a service key).

(The `og:image` is in place — `og-image.png`, 1200×630.)

## Copy notes

Copy is deliberately honest about what ships today: pace-adaptive matching against the
user's **own** library, on-device analysis, numbers-only privacy. It avoids promising
tempo-matching for DRM streaming (a known limitation) and there's no App Store link yet
— the CTA is the waitlist, since the app is pre-launch.
