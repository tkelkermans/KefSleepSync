# Changelog

All notable changes to this project are documented in this file.

## v0.2.0 - 2026-04-20

- Added native keyboard volume control for KEF speakers over Optical.
- Added media-key interception for hardware volume up and volume down with KEF `player:volume` writes.
- Added route-aware volume-key handling so macOS keeps normal behavior when audio is routed to AirPods, Mac Speakers, or any non-Optical output.
- Added Core Audio monitoring of the current default macOS output device and surfaced that state in the UI.
- Added unit coverage for volume payload encoding/decoding, media-key parsing, and macOS output-route matching.

## v0.1.0 - 2026-04-20

- Initial public release of the native macOS menu bar app.
- Added KEF discovery, authenticated local API writes, and sleep/wake automation for lock, display sleep, and full system sleep.
- Added login-item support, public README documentation, CI, screenshots, and the first GitHub release.
