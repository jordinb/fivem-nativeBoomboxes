# Changelog

## 2.4.0

### Added

- Native GTA V mixtapes recorded onto a physical, tradeable `cassette_tape` inventory item.
- Generated 893-entry music catalog spanning 23 GTA V music stations while excluding adverts, idents, DJ-only segments, and talk-radio content.
- Searchable ox_lib mixtape recorder with title entry, station browsing, ordered playlists, runtime capacity, editing, and final recording confirmation.
- Persistent one-slot ox_inventory cassette bay for each placed boombox.
- Server-authoritative mixtape definitions and ordered track persistence in normalized MySQL tables.
- Previous, next, and restart controls for inserted mixtapes.
- Scoped `nativeBoomboxPlayback` entity state for track index, source audio, timing, pause state, and revision.
- Build-aware track filtering using `Config.Mixtapes.gameBuild` or `sv_enforceGameBuild`.
- Player-facing **Station/Channel: Mixtape** mode with scoped Now Playing / End of Mixtape status.

### Changed

- Portable audio now supports both normal radio and native exact-track mixtape playback.
- The mixtape scheduler tracks only actively playing boomboxes; idle placed boomboxes incur no per-tick mixtape scan.
- Recording updates the existing cassette item's metadata instead of removing and recreating the inventory item.
- Boombox pickup and administrative deletion require the cassette bay to be empty.

### Fixed

- Added the virtual **Mixtape** channel to the Station/Channel submenu whenever a recorded cassette is inserted.
- Normal Rockstar stations remain visible but disabled while Mixtape mode is active, making the active channel unambiguous without treating Mixtape as a real Rockstar radio station.
- The boombox menu can recognize Mixtape mode from the scoped playback state bag during a client state-update race after cassette insertion.

### Safety

- Mixtape playlists are validated server-side against the bundled catalog, configured build, capacity, track limit, inventory slot, and blank-tape state.
- Cassette-bay inventory moves require server-side proximity and boombox control permission.
- Inserted cassette IDs must resolve to an existing server-side mixtape before the move is accepted.
- Normal station changes are rejected while a mixtape is inserted.
- End-of-tape playback explicitly disables the portable emitter before Rockstar radio scheduling can continue into ordinary station audio.

## 2.3.1

### Fixed

- Prevented client F8 `GetNetworkObject: no object by ID` warning spam by checking whether a portable boombox network ID exists in the local client scope before resolving it.
- Guarded reposition fallback entity resolution against out-of-scope, stale, and reused network IDs.

### Changed

- Portable audio now performs a squared-distance prefilter using synchronized boombox coordinates before any network-entity lookup.
- Resolved portable entities are verified against the replicated `nativeBoomboxId` state value before the native emitter is attached.

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
