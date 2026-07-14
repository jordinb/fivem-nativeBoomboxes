# Changelog

## 2.3.0

### Added

- Persistent player-assigned boombox labels with UTF-8, control-character, length, and server permission validation.
- Owner or ACE-authorized repositioning using the existing keyboard placement editor.
- Timed reposition edit locks with client keepalive, cancellation, disconnect cleanup, and final transform validation.
- Independent policy modes for control, pickup, reposition, rename, and world-radio control.
- Optional external permission resolver and audit exports without a framework dependency.
- Station allowlist and blocklist filtering shared by the client menu and server validator.
- ACE-restricted technical inspection and permanent deletion inside the target context.
- Server audit events for state changes, placement, pickup, rename, repositioning, deletion, and entity recovery.
- Server exports for serialized boombox state and access checks.
- Automatic database migration for the nullable `label` column.
- Resource-stop cleanup for nativeBoombox-owned context menus, rename input, confirmation dialogs, edit previews, and edit reservations.

### Changed

- Consolidated model interactions into one server-authorized context menu.
- Replaced the legacy `AllowAnyoneToControl` and `AllowAnyoneToPickup` booleans with action policies.
- Split the station list into a compact submenu.

## 2.2.1

### Fixed

- Prevented pickup, power, and station operations from overlapping on the same boombox.
- Preserved the original database ID and client state when a pickup inventory transfer fails.
- Separated configured world-radio control from player-placed ownership restrictions.
- Disabled world-radio target zones when `controllable = false`.
- Ensured the portable emitter is disabled during cleanup even if an earlier audio operation stopped before assigning a current ID.
- Preserved placement editor cleanup while exposing a single debug-only traceback when enabled.

### Added

- Automatic recovery for persistent boombox entities that fail to spawn or disappear.
- Rate-limited server error reporting.
- Startup validation for core configuration, editor tuning, audio settings, stations, and world radios.
- Explicit finite-number, coordinate-bound, and rotation normalization checks for placement payloads.
- Stable `license` and `license2` ownership resolution without falling back to an arbitrary identifier.
- Safer placement persistence and item refund handling around database failures.

## 2.2.0

- Replaced cursor placement with a keyboard editor.
- Added smooth held adjustment, precise nudges, movement spaces, Euler rotation, and configurable editor tuning.
- Changed the Move/Rotate toggle to H.
