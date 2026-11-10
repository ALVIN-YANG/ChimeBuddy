#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
.build/ChimeBuddy.app/Contents/MacOS/ChimeBuddy --export-settings .build/settings-media
cp .build/settings-media/settings-voice-light.png docs/media/
cp .build/settings-media/settings-voice-dark.png docs/media/
