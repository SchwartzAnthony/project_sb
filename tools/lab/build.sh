#!/bin/sh
# Builds Sturmball Lab: the game's rules code, exported to the web.
#
#   sh tools/lab/build.sh            (from the project folder)
#
# It copies only the code and the spreadsheets (src/, data/, tools/lab/)
# into a scratch project whose main scene is the lab, exports that with the
# "Web" template (no threads), and writes tools/lab/dist/:
#   index.html   the page (tools/lab/web/index.html with the build stamped in)
#   lab.js       Godot's loader
#   lab.engine.wasm  the engine, gzipped (the page unzips it in the browser)
#   lab.rules.wasm   the .pck: the rules code and the CSVs
# Needs: godot 4.7 on the PATH with the Web export templates installed.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WORK=${LAB_WORK:-/tmp/sturmball_lab_build}
GODOT=${GODOT:-godot}
rm -rf "$WORK"
mkdir -p "$WORK/tools"
cp -r "$ROOT/src" "$ROOT/data" "$WORK/"
cp -r "$HERE" "$WORK/tools/lab"
rm -rf "$WORK/tools/lab/dist" "$WORK/data/goalies" "$WORK/data/songs" "$WORK/data/tutorial"
cp "$ROOT/icon.svg" "$WORK/" 2>/dev/null || true
# The game's project file, with the lab as the main scene and no editor plugins.
sed -e 's#^run/main_scene=.*#run/main_scene="res://tools/lab/lab.tscn"#' \
    -e '/^\[editor_plugins\]/,/^enabled=/d' \
    "$ROOT/project.godot" > "$WORK/project.godot"
cp "$HERE/export_presets.cfg" "$WORK/"
cd "$WORK"
"$GODOT" --headless --path . --import > import.log 2>&1 || true
mkdir -p out
"$GODOT" --headless --path . --export-release "Web Lab" out/index.html > export.log 2>&1 || { tail -30 export.log; exit 1; }
DIST="$HERE/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
# Published under .wasm names: the artifact host only serves known file types.
gzip -9 -c out/index.wasm > "$DIST/lab.engine.wasm"
cp out/index.pck "$DIST/lab.rules.wasm"
cp out/index.js "$DIST/lab.js"
STAMP=$(python3 -c "import csv,sys;r=[x for x in csv.reader(open(sys.argv[1],encoding='utf-8')) if x and x[0].strip().lower()=='build_stamp'];s=r[0][1] if r else '?';print(s.split('(')[0].strip().replace('#',''))" "$ROOT/data/Tuning.csv")
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "?")
BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
sed -e "s#__BUILD__#$BRANCH @ $COMMIT#" -e "s#__STAMP__#$STAMP#" -e "s#__DATE__#$(date -u +%Y-%m-%d)#" \
    "$HERE/web/index.html" > "$DIST/index.html"
ls -la "$DIST"
