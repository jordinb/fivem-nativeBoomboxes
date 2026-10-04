-- Generated catalog index for nativeBoombox mixtapes.
MixtapeTracks = {}
MixtapeTrackLookup = {}
MixtapeTracksByStation = {}

function RegisterMixtapeTrack(track)
    if MixtapeTrackLookup[track.id] then return end
    MixtapeTracks[#MixtapeTracks + 1] = track
    MixtapeTrackLookup[track.id] = track

    local stationTracks = MixtapeTracksByStation[track.station]
    if not stationTracks then
        stationTracks = {}
        MixtapeTracksByStation[track.station] = stationTracks
    end
    stationTracks[#stationTracks + 1] = track
end
