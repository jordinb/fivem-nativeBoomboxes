Stations = {
    { value = 'RADIO_01_CLASS_ROCK', label = 'Los Santos Rock Radio' },
    { value = 'RADIO_02_POP', label = 'Non-Stop-Pop FM' },
    { value = 'RADIO_03_HIPHOP_NEW', label = 'Radio Los Santos' },
    { value = 'RADIO_04_PUNK', label = 'Channel X' },
    { value = 'RADIO_05_TALK_01', label = 'West Coast Talk Radio' },
    { value = 'RADIO_06_COUNTRY', label = 'Rebel Radio' },
    { value = 'RADIO_07_DANCE_01', label = 'Soulwax FM' },
    { value = 'RADIO_08_MEXICAN', label = 'East Los FM' },
    { value = 'RADIO_09_HIPHOP_OLD', label = 'West Coast Classics' },
    { value = 'RADIO_11_TALK_02', label = 'Blaine County Radio' },
    { value = 'RADIO_12_REGGAE', label = 'Blue Ark' },
    { value = 'RADIO_13_JAZZ', label = 'Worldwide FM' },
    { value = 'RADIO_14_DANCE_02', label = 'FlyLo FM' },
    { value = 'RADIO_15_MOTOWN', label = 'The Lowdown 91.1' },
    { value = 'RADIO_16_SILVERLAKE', label = 'Radio Mirror Park' },
    { value = 'RADIO_17_FUNK', label = 'Space 103.2' },
    { value = 'RADIO_18_90S_ROCK', label = 'Vinewood Boulevard Radio' },
    { value = 'RADIO_20_THELAB', label = 'The Lab' },
    { value = 'RADIO_21_DLC_XM17', label = 'Blonded Los Santos 97.8 FM' },
    { value = 'RADIO_22_DLC_BATTLE_MIX1_RADIO', label = 'Los Santos Underground Radio' },
    { value = 'RADIO_23_DLC_XM19_RADIO', label = 'iFruit Radio' },
    { value = 'RADIO_27_DLC_PRHEI4', label = 'Still Slipping Los Santos' },
    { value = 'RADIO_34_DLC_HEI4_KULT', label = 'Kult FM' },
    { value = 'RADIO_35_DLC_HEI4_MLR', label = 'The Music Locker' },
    { value = 'RADIO_37_MOTOMAMI', label = 'MOTOMAMI Los Santos' }
}

StationLookup = {}
for i = 1, #Stations do StationLookup[Stations[i].value] = Stations[i].label end

