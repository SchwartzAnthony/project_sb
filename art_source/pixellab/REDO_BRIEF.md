# Redo every non-PixelLab picture with PixelLab (round AN)

Anthony's decision: ALL art in Sturmball is made with PixelLab, and every
picture stays in parts/layers so he can edit it in Aseprite. This brief is
for redoing the pictures he added himself (made with other tools).

## Rules for every picture

1. **Keep the original.** Before replacing a file, copy it to
   `art_source/legacy/<the same path>` (for example
   `assets/icons/coins.png` -> `art_source/legacy/assets/icons/coins.png`).
   Never delete one.
2. **Same file, same place.** The new picture replaces the old one at the
   same path and file name, so the game picks it up with no code change.
   Look at how the game uses it first (grep the path in `src/` and `data/`)
   to find the size it is shown at and whether it needs a transparent
   background. Make the new one at that size in game pixels, or the nearest
   size PixelLab allows, and keep the same shape (aspect ratio) as the
   original so nothing gets squashed.
3. **PixelLab only.** Tools: `create_image_pro` (best; up to 688x384,
   384x688, 512x512; 20-40 generations a call), `create_image_pixen` (clean
   small sprites, 1 generation), `create_ui_asset` (frames, panels,
   buttons). Poll with `get_image` / `get_ui_asset`. Download results with
   python3 `urllib.request` from the no-auth `download_url`.
4. **The prompt.** Build it with
   `~/Desktop/Godot_v4.7.1-stable_linux.x86_64 --headless --path . --script res://tools/art_prompt.gd -- pixellab "<SUBJECT>"`
   and use what it PRINTS (stdout). Do not read
   `art_source/prompts/last_pixellab.txt`: other workers write it at the
   same time. SUBJECT = what the original shows, described in plain words
   (look at the original with the Read tool first; keep its content, pose
   and colours, but in the new clean style).
5. **References.** You may pass the original as a reference for the
   content only (`reference_images` on `create_image_pro`, usage "the
   subject and composition only, not the art style"). PixelLab corrupts
   inline base64 above roughly 10,000 characters, so shrink it first (about
   128 px, JPEG quality 60, or PNG with few colours). For people and
   creatures also pass `art_source/style_refs/stammtisch/board_characters.png`
   as `style_image_base64`, shrunk the same way.
6. **Layers.** A scene (a background, a picture with a place AND things or
   people in it) is made as separate parts: the back layer, then each
   object or figure on a transparent background. Put them together for the
   game file, and also write a layered Aseprite file with
   `tools/make_aseprite.py`'s `write_aseprite(path, width, height, [(name,
   PIL RGBA image, x, y), ...])` (bottom layer first), saved as
   `art_source/aseprite/<group>/<file name>.aseprite`. A single object
   (an icon, one character) is one layer: its PNG is enough.
7. **PixelLab quirk:** background removal punches holes in big white or
   light areas inside an object. Check every cut-out on a magenta background
   and fix holes (fill them with the right colour in Python), or ask for a
   coloured fill instead of white.
8. Python with Pillow: `~/.venvs/sturmball/bin/python`.
9. Masters (what PixelLab returned, untouched) go in
   `art_source/pixellab/<group>/`.
10. Do NOT edit any CSV, guide, `CLAUDE.md` or code. Write what you did in
    `art_source/pixellab/<group>/REPORT.md`: one line per picture (file,
    tool, size, generations used, problems). Do not use git. Do not call any
    `mcp__hearthbot__` tools. Do not install anything.
11. Stay inside your generation budget (it is in your task). One generation
    per picture; one retry only if it is clearly broken. Use
    `mcp__pixellab__get_balance` at the start and the end and report both.
