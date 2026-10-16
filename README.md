# Nova Systems LLC — Website files

*Future, Reimagined*

> **Not open source.** © 2026 Nova Systems LLC. All rights reserved. The apps, name and logo
> are proprietary. You may download and use the apps, but not copy, modify or redistribute them.
> See [LICENSE](LICENSE).

- `downloads/` — app installers (.apk and .exe) linked from the website's download buttons.
- `assets/nova-logo.png` — company logo.
- `iron-atlas/` — source of **Iron Atlas**, a satellite-map conquest game for Android (`downloads/IronAtlas.apk`). See [iron-atlas/README.md](iron-atlas/README.md).
- `wordpress/homepage.html` — the homepage, in WordPress block format.

## Add the homepage to WordPress (novasystemsllc.wordpress.com)

1. In WordPress, go to **Pages → Add New Page**.
2. Open the **⋮** menu (top right) → **Code editor**.
3. Paste the whole contents of `wordpress/homepage.html`.
4. Switch back with **⋮ → Visual editor**, check it, then **Publish**.
5. To make it your homepage: **Settings → Reading → Your homepage displays → A static page**, and pick this page.

The download buttons point to the files in this repository, so keep it public
and don't delete the `ccr-7f9fef13-0ixe1p` branch (or update the links if the files move).
