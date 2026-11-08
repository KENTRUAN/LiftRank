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

Before publishing, check widths of 320, 390, 768, and 1440 pixels, including
equipment labels and dialog controls. Exercise these paths:

- Strength: choose a preset or keep the workout blank and add an exercise;
  start, end, confirm, and save a set. Switch to Community and continue the
  same session. Check all three leave choices, including saving an unlogged
  set (zero completed sets) and discarding a logged set.
- Cardio: select indoor/outdoor, start, pause, resume, and end. Paused time
  must not advance. The two visible clocks must agree. Switching tabs must
  keep the timer; ending, discarding, or resetting must stop it.
- Ranks: visit all nine tiers in both mascot families. Toggle the crown and
  backdrop. Check 30/90/365-day and all-history ranges, keyboard date changes,
  and scores carrying forward between recorded sample days.
- Community: open all eight equipment/member details, close them by button
  and Escape, and verify focus returns to the trigger.
- Check reset, keyboard tabs and dialog focus, reduced motion, section links,
  FAQ disclosures, and JavaScript-disabled content. Demo actions must make no
  service requests; local image requests are expected when changing mascots.

## Publish with GitHub Pages

1. In [repository settings](https://github.com/NaiLongRankLift/LiftRank/settings/pages),
   open **Pages → Build and deployment → Source** and select **GitHub Actions**.
   This one-time step requires repository admin or maintainer access.
2. Review and explicitly authorize merging the website feature branch into
   main. Keep unrelated app changes out of the website pull request.
3. The **Website checks and Pages** workflow validates the site and publishes
   only the website directory. Feature-branch pushes and pull requests run checks
   without deploying. Manual runs also deploy only when run on main.
4. After a successful deployment, verify
   [nailongranklift.github.io/LiftRank](https://nailongranklift.github.io/LiftRank/), including
   all three tour screens and loaded images.

No deploy secrets are required: the workflow uses GitHub's scoped Pages and
OIDC permissions. The existing iOS/backend workflow is unchanged. If Pages
has a protected environment, approve its deployment through GitHub as needed.
The repository already uses GitHub Actions as its Pages source. Future website
updates publish after an explicitly authorized merge to main succeeds in CI.

## Content and assets

- Content describes the app's current development state. Do not add store
  badges, release claims, testimonials, or a waitlist without real destinations.
- The rank explorer mirrors the nine names, ranges, and colors in
  LiftRank/Engine/RankTier.swift; it is not a strength calculator.
- The current content was checked against main at c36ca44, including the
  unified workout flow, workout exit decisions, persisted cardio timeline,
  Live Activities, trainer identity, rank history, and gym artwork.
- The strength demo begins blank, offers an optional routine, then follows
  Start set → End set → Confirm → Save → Finish. Only completed, logged sets
  count. Save and leave excludes unfinished plans; discard clears the session.
- The cardio clock measures active browser time with a monotonic clock.
  Its route is a fixed illustration, with no geolocation or Apple connection.
  Strength elapsed/rest values and the supporting Live Activity card are
  explicitly labeled illustrations, not running native activities.
- Rank history is fictional, fixed through November 8, 2026, and independent
  of the workout demo. It carries forward the latest recorded sample score.
- NaiLong and Doubao each have nine tier images. Crown/backdrop choices are
  local previews; they spend no Eggs and do not edit the visitor's app profile.
- Gym members and messages are fictional; nothing is sent or reserved.
- Mascots, gym artwork, crown, backdrop, and app icon are optimized copies
  of the existing asset catalog. Keep the originals in the app unchanged.
- Keep the HTML description, canonical URL, and social metadata in sync if the
  public address changes. The social preview asset is a static image.
- No Xcode source membership, native behavior, backend API, or data migration
  changes are needed for this website.
