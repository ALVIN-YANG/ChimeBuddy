#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 Sources/ActionLibrary.swift Sources/VoicePreferences.swift Sources/TTSRequest.swift Sources/TTSStreamDecoder.swift Sources/PCMStreamPlayer.swift Sources/StreamingVoice.swift Sources/CompanionAvatarView.swift Sources/AvatarFrameRegistration.swift Sources/CompanionAnimation.swift Sources/CompanionPerformance.swift Sources/SessionStore.swift Sources/SessionReviews.swift Sources/RoastState.swift Sources/SharedMemory.swift Sources/ModelPreferences.swift Sources/CodexProcessEnvironment.swift Sources/CodexReviewer.swift scripts/ProbeActions.swift -framework AppKit -o .build/probe-actions
.build/probe-actions
