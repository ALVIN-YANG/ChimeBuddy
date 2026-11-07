#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 Sources/SessionStore.swift Sources/SessionReviews.swift Sources/RoastState.swift Sources/SharedMemory.swift Sources/ModelPreferences.swift Sources/CodexProcessEnvironment.swift Sources/CodexReviewer.swift scripts/ProbeBuddy.swift -o .build/probe-buddy
.build/probe-buddy
