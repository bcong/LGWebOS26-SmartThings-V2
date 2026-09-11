param(
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolsDir = Join-Path $Root '.tools'
$WorkDir = Join-Path $Root 'work'
$DriverRoot = Join-Path $WorkDir 'LGWebOS26'
$DriverDir = Join-Path $DriverRoot 'hubpackage'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Header([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

function Get-SmartThingsCli {
    $existing = Get-Command smartthings -ErrorAction SilentlyContinue
    if ($existing) {
        return $existing.Source
    }

    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    $localExe = Get-ChildItem -Path $ToolsDir -Filter 'smartthings.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($localExe) {
        return $localExe.FullName
    }

    Header 'Download SmartThings CLI'
    Write-Host 'Downloading the latest official Windows x64 standalone CLI from GitHub.'
    $headers = @{ 'User-Agent' = 'LGWebOS26-SmartThings-Installer' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/SmartThingsCommunity/smartthings-cli/releases/latest' -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -eq 'smartthings-windows-x64.zip' } | Select-Object -First 1
    if (-not $asset) {
        $asset = $release.assets | Where-Object { $_.name -match 'windows.*x64.*\.zip$' } | Select-Object -First 1
    }
    if (-not $asset) {
        throw 'Could not find the SmartThings CLI Windows x64 ZIP asset.'
    }

    $zip = Join-Path $ToolsDir 'smartthings-cli.zip'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $ToolsDir -Force
    Remove-Item $zip -Force

    $exe = Get-ChildItem -Path $ToolsDir -Filter 'smartthings.exe' -Recurse | Select-Object -First 1
    if (-not $exe) {
        throw 'smartthings.exe was not found after extraction.'
    }
    return $exe.FullName
}

function Prepare-Driver {
    Header 'Download Todd LGTV source and apply webOS 26 compatibility patch'

    if (Test-Path $WorkDir) {
        Remove-Item $WorkDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

    $srcZip = Join-Path $WorkDir 'LGTV-main.zip'
    Invoke-WebRequest -Uri 'https://github.com/toddaustin07/LGTV/archive/refs/heads/main.zip' -OutFile $srcZip -UseBasicParsing
    Expand-Archive -Path $srcZip -DestinationPath $WorkDir -Force

    $srcRoot = Join-Path $WorkDir 'LGTV-main'
    if (-not (Test-Path $srcRoot)) {
        throw 'Could not find the extracted Todd LGTV source directory.'
    }

    New-Item -ItemType Directory -Force -Path $DriverRoot | Out-Null
    Copy-Item (Join-Path $srcRoot 'hubpackage') $DriverRoot -Recurse -Force
    Copy-Item (Join-Path $srcRoot 'LICENSE') (Join-Path $DriverRoot 'LICENSE-TODD-AUSTIN.txt') -Force

    # Use a separate package key so this driver does not overwrite LG TV V1.1.
    $config = @"
name: 'LG webOS TV V2 - webOS26'
packageKey: 'cmx.lgtv.webos26.v2'
permissions:
  lan: {}
  discovery: {}
"@
    Write-Utf8NoBom (Join-Path $DriverDir 'config.yml') ($config.TrimStart())

    # webOS 26 fallback manifest.
    # Follow the lgtv2 2.0.1/2.0.2 compatibility approach: clone the legacy signed manifest,
    # remove the signed section, and add the permissions needed by the unsigned fallback.
    $unsignedModule = @'
-- webOS 26 pairing fallback for Todd Austin LGTV Edge driver.
-- Based on the compatibility strategy used by lgtv2 2.0.1/2.0.2.

local signed_request = require "authreq"

local function deepcopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end

  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[deepcopy(k, seen)] = deepcopy(v, seen)
  end
  return copy
end

local request = deepcopy(signed_request)
local manifest = request.payload.manifest

-- webOS 26 may reject the old com.lge.test signed manifest as a blacklisted certificate.
manifest.signed = nil
manifest.appVersion = "1.0"

-- These were previously supplied through manifest.signed.permissions.
-- They must also be requested by the unsigned fallback.
table.insert(manifest.permissions, "CONTROL_INPUT_TEXT")
table.insert(manifest.permissions, "CONTROL_MOUSE_AND_KEYBOARD")

return request
'@
    Write-Utf8NoBom (Join-Path $DriverDir 'src\authreq_unsigned.lua') $unsignedModule

    # init.lua compatibility patch
    $initPath = Join-Path $DriverDir 'src\init.lua'
    $init = [System.IO.File]::ReadAllText($initPath).Replace("`r`n", "`n")

    $oldRequire = 'local authdata = require "authreq"'
    $newRequire = "local authdata = require `"authreq`"`nlocal authdata_unsigned = require `"authreq_unsigned`""
    if (-not $init.Contains($oldRequire)) { throw 'init.lua: could not find authreq require patch location.' }
    $init = $init.Replace($oldRequire, $newRequire)

    # Deep-copy handshake data per TV so registration keys cannot leak between multiple TVs.
    $cloneCode = @'
local WSSPORT = 3001

local function clone_table(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end

  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[clone_table(k, seen)] = clone_table(v, seen)
  end
  return copy
end
'@
    if (-not $init.Contains('local WSSPORT = 3001')) { throw 'init.lua: could not find WSSPORT patch location.' }
    $init = $init.Replace('local WSSPORT = 3001', $cloneCode.TrimEnd())

    if (-not $init.Contains('  local handshake = authdata')) { throw 'init.lua: could not find handshake patch location.' }
    $init = $init.Replace('  local handshake = authdata', '  local handshake = clone_table(authdata)')

    $connectionOld = @'
function init_connection(device)

  local wssaddr = device:get_field('WSSaddr')
'@
    $connectionNew = @'
function init_connection(device)

  if not device:get_field('lg_registration_key') then
    device:set_field('unsigned_pairing_attempted', false)
  end

  local wssaddr = device:get_field('WSSaddr')
'@
    if (-not $init.Contains($connectionOld)) { throw 'init.lua: could not find connection patch location.' }
    $init = $init.Replace($connectionOld, $connectionNew)

    $registeredOld = @'
    device:emit_event(cap_status.status('Registered'))
    init_device(device)
'@
    $registeredNew = @'
    device:emit_event(cap_status.status('Registered'))
    device:set_field('unsigned_pairing_attempted', false)
    init_device(device)
'@
    if (-not $init.Contains($registeredOld)) { throw 'init.lua: could not find registered-handler patch location.' }
    $init = $init.Replace($registeredOld, $registeredNew)

    $errorOld = @'
  elseif response_table.type == 'error' then
    log.error(string.format('Error reported in response: %s - %s', response_table.error, response_table.payload.errorText))
'@
    $errorNew = @'
  elseif response_table.type == 'error' then
    local payload_error = ''
    if response_table.payload and response_table.payload.errorText then
      payload_error = tostring(response_table.payload.errorText)
    end
    local error_text = tostring(response_table.error or '') .. ' ' .. payload_error
    local normalized_error = string.lower(error_text)

    -- webOS 26 compatibility:
    -- New firmware can reject the legacy com.lge.test certificate with
    -- "403 Pairing rejected: blacklisted certificate detected".
    -- Retry once with an unsigned manifest, matching lgtv2 2.0.1+ behavior.
    if string.find(normalized_error, 'blacklisted certificate', 1, true)
       and not device:get_field('unsigned_pairing_attempted') then
      log.warn('Legacy signed pairing rejected by webOS; retrying unsigned pairing manifest')
      device:set_field('unsigned_pairing_attempted', true)
      device:emit_event(cap_status.status('Pairing (webOS 26 fallback)'))

      local fallback = clone_table(authdata_unsigned)
      if device:get_field('lg_registration_key') then
        fallback.payload['client-key'] = device:get_field('lg_registration_key')
      end
      send_command(device, cx.encode_json(fallback))
    else
      log.error(string.format('Error reported in response: %s - %s', tostring(response_table.error), payload_error))
    end
'@
    if (-not $init.Contains($errorOld)) { throw 'init.lua: could not find error-handler patch location.' }
    $init = $init.Replace($errorOld, $errorNew)

    Write-Utf8NoBom $initPath $init

    # Discovery modernization: query all SSDP records and accept modern LG webOS markers,
    # instead of requiring the old DLNADEVICENAME header to exactly match one format.
    $discoveryPath = Join-Path $DriverDir 'src\discovery.lua'
    $discovery = [System.IO.File]::ReadAllText($discoveryPath).Replace("`r`n", "`n")
    if (-not $discovery.Contains("'ST: urn:schemas-upnp-org:device:MediaRenderer:1',")) {
        throw 'discovery.lua: could not find SSDP ST patch location.'
    }
    $discovery = $discovery.Replace("'ST: urn:schemas-upnp-org:device:MediaRenderer:1',", "'ST: ssdp:all',")

    $newParser = @'
local function parse_response(val)

  local lginfo = {}
  local headers = process_response(val)

  if not headers.usn or not headers.location then
    return
  end

  local st = string.lower(headers.st or '')
  local server = string.lower(headers.server or '')
  local dlna_name = headers["dlnadevicename.lge.com"]
  local decoded_name = dlna_name and decode(dlna_name) or nil
  local decoded_lower = string.lower(decoded_name or '')

  -- Modern webOS firmware does not always expose exactly the same DLNA name header.
  -- Accept explicit LG/webOS service/server/name markers while still rejecting unrelated renderers.
  local is_lg_webos = false
  if st:find('lge-com', 1, true) or st:find('webos', 1, true) then
    is_lg_webos = true
  elseif server:find('webos', 1, true) or server:find('lge', 1, true) or server:find('lg electronics', 1, true) then
    is_lg_webos = true
  elseif decoded_lower:find('[lg]', 1, true) or decoded_lower:find('webos', 1, true) then
    is_lg_webos = true
  end

  if not is_lg_webos then
    log.debug(string.format('[disco] Responding device at %s is not an LG webOS TV: USN=%s', tostring(headers.location), tostring(headers.usn)))
    return
  end

  lginfo.usn = headers.usn
  lginfo.uuid = headers.usn:match('uuid:(.+)::.+$') or headers.usn:match('uuid:([^:]+)')
  lginfo.ip, lginfo.port = headers.location:match('https?://([^,/]+):([^/]+)')
  lginfo.port = tonumber(lginfo.port)

  if not lginfo.ip then
    local host = headers.location:match('https?://([^/]+)')
    if host then
      lginfo.ip = host:gsub(':.*$', '')
    end
  end

  if decoded_name and decoded_name ~= '' then
    lginfo.name = decoded_name
    local _, model = decoded_name:match('%[LG%]%s+([%a% ]+)%s+([%w%-_]+)$')
    lginfo.model = model or 'LGE webOS TV'
  else
    lginfo.name = 'LG webOS TV'
    lginfo.model = 'LGE webOS TV'
  end

  if lginfo.uuid and lginfo.ip then
    return lginfo
  end
end

function Discovery.run_discovery_task()
'@

    $parserPattern = '(?s)local function parse_response\(val\).*?\nend\n\nfunction Discovery\.run_discovery_task\(\)'
    $patchedDiscovery = [regex]::Replace($discovery, $parserPattern, $newParser.TrimEnd(), 1)
    if ($patchedDiscovery -eq $discovery) {
        throw 'discovery.lua: failed to replace the response parser.'
    }
    Write-Utf8NoBom $discoveryPath $patchedDiscovery

    $init = $init.Replace('string.format("Discovered already known device %s", id)', 'string.format("Discovered already known device %s", uuid)')
    Write-Utf8NoBom $initPath $init

    $notes = @'
LG webOS TV V2 - compatibility patch

Changes applied on top of toddaustin07/LGTV:
- Separate packageKey so it does not overwrite LG TV V1.1.
- webOS 26 pairing fallback for legacy com.lge.test blacklisted-certificate rejection.
- Adds CONTROL_INPUT_TEXT and CONTROL_MOUSE_AND_KEYBOARD to unsigned fallback manifest.
- Per-device handshake table cloning for safer multi-TV registration.
- SSDP discovery broadened beyond the legacy DLNADEVICENAME exact format.
- Uses ssdp:all and filters responses for LG/webOS markers.

Upstream code remains under the Apache-2.0 license. See LICENSE-TODD-AUSTIN.txt.
'@
    Write-Utf8NoBom (Join-Path $DriverRoot 'PATCH-NOTES.txt') $notes

    Write-Host "Patch complete: $DriverDir" -ForegroundColor Green
}

try {
    Prepare-Driver

    if ($BuildOnly) {
        Header 'Driver source prepared'
        Write-Host "Driver directory: $DriverDir"
        exit 0
    }

    $cli = Get-SmartThingsCli

    Header 'Check SmartThings CLI'
    & $cli --version
    if ($LASTEXITCODE -ne 0) { throw 'SmartThings CLI failed to start.' }

    Header 'SmartThings sign-in / account check'
    Write-Host 'If browser sign-in is requested, follow the SmartThings CLI instructions.'
    & $cli locations
    if ($LASTEXITCODE -ne 0) { throw 'SmartThings sign-in or locations query failed.' }

    Header 'Prepare Edge Driver channel'
    Write-Host 'If you already own a driver channel and your Hub is enrolled in it, choose N.'
    $first = Read-Host 'Create a new private channel and enroll the Hub? (Y/N)'
    if ($first -match '^[Yy]') {
        Write-Host ''
        Write-Host '[1/2] Create a new channel - answer the CLI prompts.' -ForegroundColor Yellow
        & $cli edge:channels:create
        if ($LASTEXITCODE -ne 0) { throw 'Edge channel creation failed.' }

        Write-Host ''
        Write-Host '[2/2] Enroll the Hub in the new channel - select the Hub and Channel.' -ForegroundColor Yellow
        & $cli edge:channels:enroll
        if ($LASTEXITCODE -ne 0) { throw 'Hub channel enrollment failed.' }
    }

    Header 'Package Driver + assign Channel + install to Hub'
    Write-Host 'When prompted, select your private channel and SmartThings Hub.'
    Write-Host "Packaging: $DriverDir"
    & $cli edge:drivers:package $DriverDir --install
    if ($LASTEXITCODE -ne 0) {
        throw 'Driver package/install failed. Review the CLI error shown above before using logcat.'
    }

    Header 'Installation complete'
    Write-Host '1) Turn on the LG TV.' -ForegroundColor Green
    Write-Host '2) In SmartThings: Add device -> Scan nearby.' -ForegroundColor Green
    Write-Host '3) Approve the connection prompt shown on the TV.' -ForegroundColor Green
    Write-Host '4) For power-on, enter the TV MAC address in the device WOL MAC Address preference.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'If something fails, run RUN_LOGCAT.cmd and send the output.' -ForegroundColor Yellow
}
catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Installation stopped.' -ForegroundColor Red
    exit 1
}
