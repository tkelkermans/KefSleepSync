#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/docs/images"
RENDERER_BIN="$ROOT_DIR/.build/readme-asset-renderer"

mkdir -p "$OUTPUT_DIR"

/usr/bin/swiftc \
  -o "$RENDERER_BIN" \
  "$ROOT_DIR/script/render_readme_assets.swift" \
  "$ROOT_DIR/App/AppDelegate.swift" \
  "$ROOT_DIR/Models/DomainModels.swift" \
  "$ROOT_DIR/Models/NSDKValue.swift" \
  "$ROOT_DIR/Services/SpeakerDiscoveryService.swift" \
  "$ROOT_DIR/Services/KefAPIClient.swift" \
  "$ROOT_DIR/Services/KeyboardVolumeController.swift" \
  "$ROOT_DIR/Services/KefRequestSecurity.swift" \
  "$ROOT_DIR/Services/LoginItemService.swift" \
  "$ROOT_DIR/Services/MediaKeyMonitor.swift" \
  "$ROOT_DIR/Stores/AppModel.swift" \
  "$ROOT_DIR/Services/SystemAudioOutputMonitor.swift" \
  "$ROOT_DIR/Support/AppLogger.swift" \
  "$ROOT_DIR/Views/MenuBarContentView.swift" \
  "$ROOT_DIR/Views/SettingsView.swift"

"$RENDERER_BIN" "$OUTPUT_DIR"

echo "Generated README screenshots in $OUTPUT_DIR"
