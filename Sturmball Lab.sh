#!/bin/sh
# STURMBALL LAB - double-click to open it in your browser.
#
# The Lab runs the game's real rules code in the browser. Browsers refuse to
# start that from a double-clicked file, so this starts a tiny web server on
# this computer only (nothing goes on the internet), opens the page, and
# stops the server by itself after 8 hours.
#
# Rebuild the Lab after a round with:  sh tools/lab/build.sh   (needs Godot
# with the Web export templates).
HERE=$(cd "$(dirname "$0")" && pwd)
DIST="$HERE/tools/lab/dist"
PORT=8765
URL="http://127.0.0.1:$PORT/index.html"
if [ ! -f "$DIST/index.html" ]; then
  echo "The Lab is not built yet: run  sh tools/lab/build.sh"; sleep 10; exit 1
fi
# Already running from an earlier double-click? Then just open the page.
if ! python3 -c "import socket,sys;s=socket.socket();sys.exit(s.connect_ex(('127.0.0.1',$PORT)))" 2>/dev/null; then
  cd "$DIST" && nohup timeout 8h python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1 &
  sleep 1
fi
xdg-open "$URL" >/dev/null 2>&1 || open "$URL" >/dev/null 2>&1 || echo "Open $URL in your browser."
