#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
dart analyze --format machine lib test integration_test test_driver
if [[ -n "${1:-}" ]]; then
  flutter test integration_test/core_test.dart -d "$1" --reporter expanded
else
  flutter test --reporter expanded
fi
