# LiftRank website

The English showcase and scripted tour are a build-free static site in the
website directory. All images, CSS, and JavaScript are served locally. The demo
uses in-memory sample data; it has no backend connection, cookies, analytics,
or account storage. A refresh or **Reset the demo** clears sample progress.

## Preview and checks

From the repository root:

    python3 -m http.server 4173 --bind 127.0.0.1 --directory website
    python3 scripts/check_website.py
    node --check website/app.js
    python3 scripts/lint.py --swift

Open http://127.0.0.1:4173/ for the preview. For project-path testing, serve a
temporary parent directory containing a LiftRank symlink to the website
directory, then open /LiftRank/. All asset URLs are relative so both work.

Before publishing, check widths of 320, 390, 768, and 1440 pixels; complete the
sample workout; visit all nine ranks and six gym details; test reset, keyboard
tabs and dialogs, reduced motion, and JavaScript-disabled content. Demo
actions must make no service requests.

## Publish with GitHub Pages

1. In [repository settings](https://github.com/KENTRUAN/LiftRank/settings/pages),
   open **Pages → Build and deployment → Source** and select **GitHub Actions**.
   This one-time step requires repository admin or maintainer access.
2. Review and explicitly authorize merging the website feature branch into
   main. Do not merge app work as part of the website change.
3. The **Website checks and Pages** workflow validates the site and publishes
   only the website directory. Feature-branch pushes and pull requests run checks
   without deploying. Manual runs also deploy only when run on main.
4. After a successful deployment, verify
   [kentruan.github.io/LiftRank](https://kentruan.github.io/LiftRank/), including
   all three tour screens and loaded images.

No deploy secrets are required: the workflow uses GitHub's scoped Pages and
OIDC permissions. The existing iOS/backend workflow is unchanged. If Pages
has a protected environment, approve its deployment through GitHub as needed.
Hosting is not active merely because these files exist.

## Content and assets

- Content describes the app's current development state. Do not add store
  badges, release claims, testimonials, or a waitlist without real destinations.
- The rank explorer mirrors the nine names, ranges, and colors in
  LiftRank/Engine/RankTier.swift; it is not a strength calculator.
- The workout begins blank, requires an explicit sample routine, then follows
  Start set → End set → Confirm → Save → Finish. Only that sample set is counted.
- Gym members and messages are fictional; nothing is sent or reserved.
- Mascots and the app icon are resized copies of the existing asset catalog.
  Keep the originals in the app unchanged.
- Keep the HTML description, canonical URL, and social metadata in sync if the
  public address changes. The social preview asset is a static image.
- No Xcode source membership, native behavior, backend API, or data migration
  changes are needed for this website.
