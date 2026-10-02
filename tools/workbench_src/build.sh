#!/bin/sh
# Rebuilds sturmball_workbench.html from its parts. Run from this folder.
# THE ORDER MATTERS: later parts use names the earlier ones define, and
# part5_tail.js boots the page, so it must be last.
cat head.html part2.html part2b_seed.js part3_schema.js part4_engine.js \
    part6_guide.js part7_wizard.js part5_tail.js > ../../sturmball_workbench.html
echo "wrote ../../sturmball_workbench.html"
