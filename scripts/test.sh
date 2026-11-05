#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 Sources/SessionStore.swift Tests/SessionStoreTests.swift -o .build/session-tests
.build/session-tests
