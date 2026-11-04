# Trailblazer Dash

An original 3D endless runner for [Little Joy Arcade](https://littlejoyarcade.site).
You are a Trailblazer rebuilding the Wayfinder Network across Avelora, one trail at a time.

- **Engine:** Godot 4.7 (GL Compatibility renderer, Web export)
- **Platform:** portrait-first mobile browsers, tablet and desktop
- **Content:** 500 campaign levels across 20 regions, plus Endless Trail and a seeded Daily Route
- **Assets:** Blender-authored character and props (`Blender/*.blend`, exported to `Assets/Models`)

## Play

- **Live:** https://jd4rider.github.io/trailblazer-dash/
- **Arcade:** https://littlejoyarcade.site (listed in the catalogue)

## Controls

| Action | Touch | Keyboard |
| --- | --- | --- |
| Change lane | swipe left / right | ← → or A / D |
| Jump | swipe up or tap | ↑ / W / Space |
| Slide | swipe down | ↓ / S |
| Pause | HUD pause button | Esc |

## What is in the build

- Three-lane runner with buffered lane changes, jump/slide states and stumble recovery
- Streaming track assembled from validated campaign rows: hurdles, overhead bars, block walls and rolling boulders
- Sparks, power-up crates and hidden relics, each with pickup feedback
- 20 regions with their own ground colours, props and landmarks
- Living world map: region progress, level sheet with stars, route completion animation
- Trailblazer roster (tinting per character), collections, achievements and settings
- Local save with schema migration, plus optional cloud save through the Little Joy Arcade account client
- HUD, ready card, results panel, pause, and a per-region ambience/music bed

## Develop

```bash
godot --path .                       # run in the editor runtime
godot --headless --path . Tests/Tests.tscn   # campaign + save + run-scene checks
```

The tests replay every one of the 500 levels: lane openness, row spacing against the
level's speed, safe-lane reachability, and that each spark sits on the shipped route.
`Docs/CampaignValidation.md` describes the validator and its report.

## Build the web version

```bash
godot --headless --path . --export-release "Web" web/play/index.html
python3 Tools/patch_web.py     # title, viewport, portrait framing, arcade client
```

`Tools/patch_web.py` also writes `.nojekyll` so GitHub Pages serves the build as-is.
`node Tools/smoke.mjs http://127.0.0.1:4173/` boots the export in Chromium at two
portrait sizes, taps through to a run and writes screenshots to `/tmp/tb-shots`.

Pushing to `main` runs `.github/workflows/pages.yml`: it installs Godot 4.7.2 with the
Web export templates, runs the headless tests, exports, patches and deploys to Pages.

## Arcade integration

`web/play/arcade-bridge.js` is loaded before the drop-in `arcade-client.js`. It exposes
`window.TrailblazerArcade` (identity, status, save push/pull, achievements, analytics)
and teaches the client how to snapshot the Godot save through `LJA_SNAPSHOT` /
`LJA_APPLY_SNAPSHOT`. Everything degrades to local saving when the client is absent.

## Not there yet

Companions, cosmetic unlocks, global leaderboards and per-region music tracks are
stubbed or single-bed; the map covers region progress rather than the full illustrated
Avelora atlas. Save schema is versioned so those can land without breaking existing saves.
