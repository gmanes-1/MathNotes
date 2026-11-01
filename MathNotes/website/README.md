# OwlLuna website

The site for [OwlLuna](https://github.com/owaisazmal/OwlLuna): what the app does, a note from its developer, the [screenshots from its making](app/prototypes/page.tsx), the [Privacy Policy](app/privacy/page.tsx) and the [Support](app/support/page.tsx) page. It is a static site: Next.js exports plain HTML, and nothing runs on a server.

## Running it

```bash
cd website
```

```bash
npm install
```

```bash
npm run dev
```

`npm run build` writes the finished site to `website/out`.

## What to change when

Everything that varies is in [lib/site.ts](lib/site.ts):

- `appStoreUrl`: the App Store page. While it is empty the site says "Coming soon to the App Store"; once set, the buttons link to it.
- `contactEmail`: an address for privacy and support questions. While it is empty the pages point to GitHub Issues alone.
- `policyUpdated`: the date printed on the Privacy Policy. Change it whenever the policy's wording changes.

The Privacy Policy describes what the app's code does. If a change to the app touches what is stored, synced, read or shared, update [app/privacy/page.tsx](app/privacy/page.tsx) in the same pull request.

## How it is put together

- `app/`: the pages (home, `prototypes/`, `privacy/`, `support/`), the root layout and the design tokens in `globals.css`.
- `components/ui/`: the app's own pieces rebuilt for the web: cloth and plate buttons, the Card panel, the Ledger, the Stamp, index cards, cloth covers, study tape and the splash's hand lettering.
- `components/hero/`: the launch splash as the page's opening. The tiles, their artwork and their timings are taken from `OwlLuna/Launch/` in the app.
- `components/sections/`: the parts of the home page.
- `components/prototypes/`: the screenshots saved while the app was being finished. `shots.ts` holds their order, captions and layout; the rest is the log on `/prototypes/`, the loose pile on the home page and the viewer both open. The pictures are in `public/prototypes/`, each as WebP in three sizes: `name.webp` (full size), `name-m.webp` (up to 1100 px wide, for the log) and `name-t.webp` (up to 640 px wide, for the pile).
- `lib/`: site settings and the motion curves.

The look follows [docs/DESIGN.md](../docs/DESIGN.md): paper, ink, moon yellow and tomato, flat ink-outlined rectangles with the app's corner scale, and cobalt cloth for the one action that finishes a task. Printed matter (tiles, covers, index cards) keeps its colours at night; everything else follows the light and dark tokens. Animation is done with [Motion](https://motion.dev). With Reduce Motion nothing moves, the button on the hero's ticker pauses what loops, and a visitor whose scripts are off or slow to arrive is shown the finished scene still.

## Fonts

Fraunces, Archivo and Bricolage Grotesque, the same three the app bundles, come from the `@fontsource-variable` packages and are served from the site itself. All three are under the SIL Open Font License; the licence texts are in [OwlLuna/Resources/Fonts](../OwlLuna/Resources/Fonts).

## Publishing

[.github/workflows/website.yml](../.github/workflows/website.yml) builds the site and publishes it to GitHub Pages whenever `website/` changes on `main`. It needs one setting, once: in the repository's Settings › Pages, set Source to "GitHub Actions". The site then lives at `https://owaisazmal.github.io/OwlLuna/`, with the policy at `/privacy/` and support at `/support/`. The workflow reads the address from Pages, so a custom domain needs no change here.
