-- Infamous Development Studios: IDS Version Control
-- Drop this file into the FiveM resource you want to track.
-- It reads the resource version from fxmanifest.lua and compares it against a public GitHub JSON manifest.
-- If the resource is outdated, prints update information and a changelog if available.

local CONFIG = {
    manifestUrl = 'https://raw.githubusercontent.com/jordinb/ids-fivem-assets-version-control/main/versions.json',
    checkIntervalMinutes = 60,

    -- Leave nil to use the current resource name.
    -- Set this only if the GitHub manifest key differs from the resource folder name.
    resourceKey = nil,

    -- Used when the remote manifest only provides a version string instead of a full table.
    defaultDownload = 'https://portal.cfx.re/assets/granted-assets'
}

local RESOURCE_NAME = GetCurrentResourceName()
local RESOURCE_KEY = CONFIG.resourceKey or RESOURCE_NAME
local CHECK_INTERVAL_MS = math.max(1, tonumber(CONFIG.checkIntervalMinutes) or 60) * 60000

local PREFIX = '^5[IDS Version Control]^7'

local function log(message)
    print(('%s %s'):format(PREFIX, message))
end

local function normalizeVersion(version)
    return tostring(version or '')
        :gsub('^%s*[vV]', '')
        :gsub('%s+$', '')
end

local function versionParts(version)
    local parts = {}

    for part in normalizeVersion(version):gmatch('[^.]+') do
        parts[#parts + 1] = tonumber(part:match('^(%d+)')) or 0
    end

    return parts
end

local function compareVersions(current, latest)
    local currentParts = versionParts(current)
    local latestParts = versionParts(latest)
    local maxParts = math.max(#currentParts, #latestParts)

    for i = 1, maxParts do
        local currentPart = currentParts[i] or 0
        local latestPart = latestParts[i] or 0

        if currentPart < latestPart then
            return -1
        end

        if currentPart > latestPart then
            return 1
        end
    end

    return 0
end

local function getInstalledVersion()
    local version = GetResourceMetadata(RESOURCE_NAME, 'version', 0)

    if not version or version == '' then
        return nil
    end

    return tostring(version)
end

local function getRemoteEntry(manifest)
    local entry = manifest[RESOURCE_KEY]

    if type(entry) == 'string' then
        return {
            version = entry,
            download = CONFIG.defaultDownload,
            changes = ''
        }
    end

    if type(entry) ~= 'table' then
        return nil
    end

    return {
        version = tostring(entry.version or entry.NewestVersion or ''),
        download = tostring(entry.download or entry.DownloadLocation or CONFIG.defaultDownload),
        changes = tostring(entry.changes or entry.Changes or '')
    }
end

local function printOutdated(installedVersion, remote)
    log(('^1[%s] OUTDATED^7'):format(RESOURCE_NAME))
    print(('^7Installed: ^1%s^7'):format(installedVersion))
    print(('^7Latest: ^2%s^7'):format(remote.version))
    print(('^7Update at: ^5%s^7'):format(remote.download))

    if remote.changes ~= '' then
        print(('^7Changes: ^5%s^7'):format(remote.changes))
    end
end

local function checkVersion()
    local installedVersion = getInstalledVersion()

    if not installedVersion then
        log(('^1[%s]^7 No version metadata found in fxmanifest.lua. Add: ^5version "1.0.0"^7'):format(RESOURCE_NAME))
        return
    end

    PerformHttpRequest(CONFIG.manifestUrl, function(statusCode, body)
        if statusCode ~= 200 or not body or body == '' then
            log(('^1[%s]^7 Failed to fetch remote version data. HTTP status: %s'):format(
                RESOURCE_NAME,
                tostring(statusCode)
            ))
            return
        end

        local ok, manifest = pcall(json.decode, body)

        if not ok or type(manifest) ~= 'table' then
            log(('^1[%s]^7 Remote version manifest is not valid JSON.'):format(RESOURCE_NAME))
            return
        end

        local remote = getRemoteEntry(manifest)

        if not remote then
            log(('^3[%s]^7 No remote manifest entry found for key ^5%s^7.'):format(
                RESOURCE_NAME,
                RESOURCE_KEY
            ))
            return
        end

        if remote.version == '' then
            log(('^1[%s]^7 Remote manifest entry exists but has no valid version field.'):format(RESOURCE_NAME))
            return
        end

        if compareVersions(installedVersion, remote.version) < 0 then
            printOutdated(installedVersion, remote)
            return
        end

        log(('^2[%s] Up to date^7 (version %s)'):format(RESOURCE_NAME, installedVersion))
    end, 'GET')
end

CreateThread(function()
    Wait(2500)
    checkVersion()

    while true do
        Wait(CHECK_INTERVAL_MS)
        checkVersion()
    end
end)