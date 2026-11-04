#!/usr/bin/env python3
"""Post-process the Godot Web export.

Godot's default shell is a bare canvas. This script adds the arcade bridge, the
portrait framing CSS, a mobile viewport and the game's own title, and copies the
drop-in arcade client next to the build.

    python3 Tools/patch_web.py
"""

from __future__ import annotations

import pathlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLAY = ROOT / "web" / "play"
CLIENT = ROOT.parent / "littlejoyarcade" / "packages" / "sdk" / "desktop" / "arcade-client.js"

HEAD_INJECT = """\t<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover" />
\t<meta name="theme-color" content="#0b1c20" />
\t<meta name="apple-mobile-web-app-capable" content="yes" />
\t<meta name="mobile-web-app-capable" content="yes" />
\t<meta name="description" content="Trailblazer Dash — an original 3D endless-runner adventure across Avelora, a Little Joy Arcade original." />
\t<link rel="stylesheet" href="./frame.css" />
\t<script src="./arcade-bridge.js"></script>
\t<script src="./arcade-client.js" data-game-id="trailblazer-dash"></script>
"""


def main() -> int:
    index = PLAY / "index.html"
    if not index.exists():
        print("web/play/index.html is missing — run the Godot Web export first.")
        return 1

    html = index.read_text(encoding="utf-8")
    html = re.sub(r"<title>.*?</title>", "<title>Trailblazer Dash</title>", html, flags=re.S)
    if "arcade-bridge.js" not in html:
        html = html.replace("</head>", HEAD_INJECT + "</head>")
    index.write_text(html, encoding="utf-8")

    if CLIENT.exists():
        target = PLAY / "arcade-client.js"
        shutil.copyfile(CLIENT, target)
        # The public anon key is safe to ship; RLS protects every row.
        text = target.read_text(encoding="utf-8")
        if "__LJA_ANON_KEY__" in text:
            print("warning: arcade-client.js still has the anon-key placeholder")
    else:
        print("warning: arcade client not found at", CLIENT)

    (PLAY / ".nojekyll").write_text("", encoding="utf-8")
    print("patched", index.relative_to(ROOT))
    for path in sorted(PLAY.iterdir()):
        print(f"  {path.name:28s} {path.stat().st_size/1024/1024:6.2f} MiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
