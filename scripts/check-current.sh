#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 Sources/SessionStore.swift Sources/SessionReviews.swift Sources/RoastState.swift Sources/SessionTranscript.swift Sources/DesktopSelection.swift Sources/CodexThreadTitles.swift Sources/CodexAppServer.swift Sources/ModelPreferences.swift Sources/SharedMemory.swift Sources/CodexProcessEnvironment.swift Sources/CodexReviewer.swift scripts/ProbeCurrent.swift -framework AppKit -o .build/check-current
.build/check-current "$@"
