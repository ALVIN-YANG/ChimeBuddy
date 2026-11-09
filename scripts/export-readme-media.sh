#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
mkdir -p docs/media
.build/ChimeBuddy.app/Contents/MacOS/ChimeBuddy --export-readme .build/readme-media
cp .build/readme-media/companion-light.png docs/media/
cp .build/readme-media/companion-dark.png docs/media/
ffmpeg -hide_banner -loglevel error -y -framerate 10 -i .build/readme-media/frames/%03d.png \
  -filter_complex '[0:v]split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle' \
  -loop 0 docs/media/companion-demo.gif
