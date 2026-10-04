-- Add these entries inside ox_inventory/data/items.lua. If boombox already exists, merge the export into its existing client table.
['boombox'] = {
    label = 'Boombox',
    weight = 500,
    stack = false,
    close = true,
    client = {
        export = 'nativeBoombox.useBoombox'
    }
},


['cassette_tape'] = {
    label = 'Blank Cassette Tape',
    weight = 50,
    stack = false,
    close = true,
    client = {
        export = 'nativeBoombox.useCassette'
    }
},

