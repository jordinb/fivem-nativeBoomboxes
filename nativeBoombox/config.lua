Config = {}

Config.Debug = false
Config.ItemName = 'boombox'
Config.PropModel = `prop_boombox_01`
Config.InteractDistance = 2.0

Config.Placement = {
    initialDistance = 1.5,
    maximumDistance = 8.0,
    editor = {
        holdDelay = 180,
        moveNudge = { precision = 0.01, normal = 0.05, fast = 0.25 },
        moveSpeed = { precision = 0.12, normal = 0.65, fast = 2.00 },
        rotateNudge = { precision = 1.0, normal = 5.0, fast = 15.0 },
        rotateSpeed = { precision = 20.0, normal = 65.0, fast = 160.0 }
    }
}

Config.Audio = {
    emitter = 'SE_Script_Placed_Prop_Emitter_Boombox',
    scene = 'MP_Reduce_Score_For_Emitters_Scene',
    distance = 50.0,
    scanInterval = 500
}

Config.DefaultStation = 'RADIO_01_CLASS_ROCK'
Config.AllowAnyoneToControl = true
Config.AllowAnyoneToPickup = false
Config.MaximumOwned = 10

-- Configure map-authored radios only when their real Rockstar emitter name is known.
-- These entries use their own fixed emitter and do not consume the portable emitter.
Config.WorldRadios = {
    -- {
    --     id = 'mission_row_lobby',
    --     label = 'Mission Row Radio',
    --     coords = vec3(441.15, -981.95, 30.69),
    --     emitter = 'REAL_STATIC_EMITTER_NAME',
    --     defaultStation = 'RADIO_01_CLASS_ROCK',
    --     powered = true
    -- }
}
