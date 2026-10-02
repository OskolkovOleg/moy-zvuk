#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
python3 tool/prepare_signing.py
flutter pub get
flutter build apk --release
