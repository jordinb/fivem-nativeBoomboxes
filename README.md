# nativeBoombox 2.3.0

A clean rebuild of the persistent FiveM boombox resource using GTA V's native placed-prop radio emitter. It does not create hidden vehicles, play URLs, or use browser audio.

## Dependencies

- ox_lib
- oxmysql
- ox_inventory
- ox_target
- OneSync

## Installation

1. Install every dependency and add the item from `nativeBoombox/install/items.lua`.
2. The SQL table should be created and migrated automatically. The SQL file is included for manual installation.
3. Copy the `nativeBoombox` folder into your server resources directory.
4. Start the resources in this order:

```cfg
ensure ox_lib
ensure oxmysql
ensure ox_inventory
ensure ox_target
ensure nativeBoombox
```

### Upgrading from 2.2.1

Replace the resource files and merge the new configuration sections. The legacy `Config.AllowAnyoneToControl` and `Config.AllowAnyoneToPickup` values are no longer used. Recreate their behavior through `Config.Permissions.actions`. The nullable `label` column is added automatically on startup.

## Native audio design

GTA's freemode scripts link `SE_Script_Placed_Prop_Emitter_Boombox` to placed `prop_boombox_01` entities with `LINK_STATIC_EMITTER_TO_ENTITY`. This resource follows that base-game implementation and retunes it with `SET_EMITTER_RADIO_STATION`.

The game exposes one named script-placed boombox emitter. Consequently, each client hears the nearest powered portable boombox inside `Config.Audio.distance`. Different players may hear different nearby boomboxes. Map-authored radios use their own configured emitter names and are independent.

## Placement controls

| Control | Action |
| --- | --- |
| H | Switch between Move and Rotate |
| Left / Right Arrow | Select X, Y, or Z axis |
| Up / Down Arrow | Adjust the selected axis |
| L | Switch between world and local axes |
| Left Shift | Precision step |
| Left Ctrl | Fast step |
| G | Snap to ground |
| Enter | Finish and review placement |
| Backspace | Cancel placement |

Tap Up/Down for an exact nudge or hold it for smooth continuous adjustment. The precision, normal, and fast nudge sizes and hold speeds can be tuned under `Config.Placement.editor`.

Move and Rotate remember their own selected axes during a placement session. Rotate starts on Z for quick heading adjustment. Local/world space applies to movement; rotation uses the entity's Euler X/Y/Z values.

## Configuration

- `Config.Permissions.actions` independently controls playback, pickup, repositioning, renaming, and world-radio access.
- Supported permission modes are `everyone`, `owner`, `ace`, `owner_or_ace`, and `disabled`.
- `Config.Permissions.hook` can delegate the final decision to another server resource without adding a framework dependency.
- `Config.Permissions.adminAce` grants the contextual administrative inspector and permanent-delete action.
- `Config.StationFilter` provides station allowlists and blocklists. Blocked stations are rejected server-side and omitted from the menu.
- `Config.Labels` controls persistent player-assigned boombox names.
- `Config.Reposition` controls edit-lock duration and movement limits.
- Each `Config.WorldRadios` entry can set `controllable = false` without being affected by placed-boombox ownership rules.
- `Config.EntityRecovery` controls the low-frequency server watchdog for missing persistent entities.
- `Config.Validation.worldCoordinateLimit` rejects invalid or unreasonable placement coordinates.
- Placement responsiveness is configured under `Config.Placement.editor`.

### ACE example

```cfg
add_ace group.admin nativeBoombox.admin allow
add_ace group.boomboxmanager nativeBoombox.control allow
add_ace group.boomboxmanager nativeBoombox.pickup allow
add_ace group.boomboxmanager nativeBoombox.reposition allow
add_ace group.boomboxmanager nativeBoombox.rename allow
```

ACE entries only affect an action when its mode includes `ace`. Administrators can bypass ordinary action policies when `adminBypass = true`.

## Interaction

One target option opens a server-authorized menu. Depending on access, it can contain:

- Power and station controls.
- Persistent renaming.
- Keyboard-based repositioning using the same F8-safe editor as initial placement.
- Inventory pickup.
- ACE-restricted technical details and permanent deletion.

## Persistence and recovery

- Power, station, position, rotation, ownership, and custom label persist in MySQL.
- Power values returned as either booleans or `TINYINT(1)` numbers are normalized on startup.
- Pickup and state changes use a per-boombox operation lock.
- A failed pickup inventory transfer restores the original database row with the same ID and leaves the entity in place.
- Missing persistent entities are recreated automatically without requiring a resource restart.
- A placement saved during a temporary entity creation failure remains persisted and is recovered by the watchdog.
- Reposition sessions use a timed server edit lock with client keepalive and server-side final-transform validation.

## Safety

- The server owns all persistent props and validates distance, ownership, inventory, station, payload type, finite coordinates, coordinate bounds, and placement limits.
- Only stable Rockstar license identifiers are used for ownership.
- Model targeting uses a replicated state-bag ID, preventing unrelated boombox props from being controlled.
- Placement uses no cursor mode, NUI focus, commands, or permanent key mappings.
- ox_lib menus and dialogs are tracked and closed on resource stop only when nativeBoombox owns them.
- A failed audio worker stops and reports once. It cannot flood F8 in a retry loop.
- Server error reporting is rate-limited by failure scope.
- Placement, pickup, control, rename, reposition, deletion, and recovery emit server audit events.