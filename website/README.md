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

## Deploy to dromo.fit

Because it's plain static files, any static host serves it. The whole site is this
folder; point the host's root/publish directory at `website/`.

- **Vercel / Netlify / Cloudflare Pages:** new project from this repo, set the
  output/publish directory to `website`, no build command. Then add `dromo.fit` as a
  custom domain and follow the DNS instructions (usually a CNAME / A record).
- **GitHub Pages:** publish the `website/` folder and add a `CNAME` file containing
  `dromo.fit`, then set the apex/`www` DNS records per GitHub's docs.

## Before launch — two TODOs

1. **Waitlist destination.** In `script.js`, `WAITLIST_ENDPOINT` is empty, so sign-ups
   are validated and stored in `localStorage` (nothing is lost, but nothing is sent).
   Set it to a POST endpoint that accepts `{ email }` — e.g. Formspree/Buttondown — or
   wire it to Supabase (project `prftbirfbzhdacuenatw`): create a `waitlist` table with
   an INSERT-only anon RLS policy and POST to its REST endpoint with the anon key.
2. **Social image.** The `og:image` / `twitter:image` tags point at
   `https://dromo.fit/og-image.png`. Drop a 1200×630 PNG named `og-image.png` in this
   folder so link previews render.

## Copy notes

Copy is deliberately honest about what ships today: pace-adaptive matching against the
user's **own** library, on-device analysis, numbers-only privacy. It avoids promising
tempo-matching for DRM streaming (a known limitation) and there's no App Store link yet
— the CTA is the waitlist, since the app is pre-launch.
