#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 Sources/SessionStore.swift Tests/SessionStoreTests.swift -o .build/session-tests
.build/session-tests
swiftc -swift-version 5 Sources/CompanionAnimation.swift Tests/CompanionAnimationTests.swift -o .build/animation-tests
.build/animation-tests
swiftc -swift-version 5 Sources/SessionReviews.swift Tests/SessionReviewsTests.swift -o .build/review-tests
.build/review-tests
swiftc -swift-version 5 Sources/SessionStore.swift Sources/SessionTranscript.swift Sources/DesktopSelection.swift Tests/ObservationTests.swift -o .build/observation-tests
.build/observation-tests
swiftc -swift-version 5 Sources/SessionStore.swift Sources/SessionReviews.swift Sources/RoastState.swift Tests/RoastStateTests.swift -o .build/roast-state-tests
.build/roast-state-tests
