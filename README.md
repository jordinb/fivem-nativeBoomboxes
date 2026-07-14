# nativeBoombox

A clean rebuild of the persistent FiveM boombox resource using GTA V's native placed-prop radio emitter. It does not create hidden vehicles, play URLs, or use browser audio.

## Dependencies

- ox_lib
- oxmysql
- ox_inventory
- ox_target
- OneSync

## Installation

1. Install every dependency and add the item from `install/items.lua`.
2. The SQL table should be created and migrated automatically. The SQL file is included for manual installation.
3. Start the resources in this order:

```cfg
ensure ox_lib
ensure oxmysql
ensure ox_inventory
ensure ox_target
ensure nativeBoombox
```

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
- A failed audio worker stops and reports once; it cannot flood F8 in a retry loop.
