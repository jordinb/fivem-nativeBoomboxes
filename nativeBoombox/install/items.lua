-- Add inside ox_inventory/data/items.lua. /// If boombox already exists, just add the export line to the client table.
['boombox'] = {
    label = 'Boombox',
    weight = 500,
    stack = false,
    close = true,
    client = {
        export = 'nativeBoombox.useBoombox'
    }
},

