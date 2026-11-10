--[[
  Copyright 2023 Todd Austin

  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
  except in compliance with the License. You may obtain a copy of the License at:

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the
  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  either express or implied. See the License for the specific language governing permissions
  and limitations under the License.


  DESCRIPTION
  
  LG TV Driver

  Reference:  https://github.com/klattimer/LGWebOSRemote/tree/master/LGTV

--]]

-- Edge libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local cosock = require "cosock"
local socket = require "cosock.socket"                                  -- for time only
local log = require "log"
local utils = require "st.utils"

-- Driver modules
local ws = require 'websocket'
local discovery = require "discovery"
local semaphore = require "semaphore"
local authdata = require "authreq"
local authdata_unsigned = require "authreq_unsigned"
local cx = require "common"
local wol = require "wakeonlan"

newly_added = {}
found_hubs = {}
local applists = {}

-- Device Capabilities

cap_lgmsg = capabilities["partyvoice23922.lgmessage"]
cap_lginput = capabilities["partyvoice23922.lgmediainputsource"]
cap_status = capabilities["partyvoice23922.status"]
cap_power_state = capabilities["mirrordouble43237.lgpowerstate"]
cap_screen_state = capabilities["mirrordouble43237.lgscreenstate"]
cap_channel = capabilities["partyvoice23922.lgcurrentchannel"]
cap_app = capabilities["partyvoice23922.lgcurrentapp"]
cap_channel_number = capabilities["partyvoice23922.lgchannelnumber"]
cap_volup = capabilities["partyvoice23922.lgvolumeup"]
cap_voldown = capabilities["partyvoice23922.lgvolumedown"]
cap_remote = capabilities["mirrordouble43237.lgTvRemote"]

local REMOTE_BUTTONS = {
  LEFT = true,
  RIGHT = true,
  UP = true,
  DOWN = true,
  RED = true,
  GREEN = true,
  YELLOW = true,
  BLUE = true,
  CHANNELUP = true,
  CHANNELDOWN = true,
  VOLUMEUP = true,
  VOLUMEDOWN = true,
  PLAY = true,
  PAUSE = true,
  STOP = true,
  REWIND = true,
  FASTFORWARD = true,
  ASTERISK = true,
  BACK = true,
  EXIT = true,
  ENTER = true,
  AMAZON = true,
  NETFLIX = true,
  DISNEY_PLUS = true,
  COUPANG_PLAY = true,
  TVING = true,
  LAFTEL = true,
  ["3D_MODE"] = true,
  AD = true,
  ASPECT_RATIO = true,
  CC = true,
  DASH = true,
  GUIDE = true,
  HOME = true,
  INFO = true,
  INPUT_HUB = true,
  LIST = true,
  LIVE_ZOOM = true,
  MAGNIFIER_ZOOM = true,
  MENU = true,
  MUTE = true,
  MYAPPS = true,
  POWER = true,
  PROGRAM = true,
  QMENU = true,
  RECENT = true,
  RECORD = true,
  SAP = true,
  SCREEN_REMOTE = true,
  TELETEXT = true,
  TEXTOPTION = true,
  ["0"] = true,
  ["1"] = true,
  ["2"] = true,
  ["3"] = true,
  ["4"] = true,
  ["5"] = true,
  ["6"] = true,
  ["7"] = true,
  ["8"] = true,
  ["9"] = true
}

local STREAMING_APP_SHORTCUTS = {
  AMAZON = { "amazon", "primevideo", "아마존", "프라임비디오" },
  DISNEY_PLUS = { "disney", "디즈니" },
  COUPANG_PLAY = { "coupang", "쿠팡" },
  TVING = { "tving", "티빙" },
  LAFTEL = { "laftel", "라프텔" }
}

local INPUT_SOURCE_LABELS_BY_APP = {
  ["com.webos.app.hdmi1"] = "HDMI 1",
  ["com.webos.app.hdmi2"] = "HDMI 2",
  ["com.webos.app.hdmi3"] = "HDMI 3",
  ["com.webos.app.hdmi4"] = "HDMI 4",
  ["com.webos.app.externalinput.av1"] = "AV",
  ["com.webos.app.externalinput.component"] = "Component",
  ["com.webos.app.livetv"] = "LIVE TV"
}

-- Global variables
thisDriver = {}
hubs_auto_discovered = 0
disco_sem = {}

-- Module variables
local initialized = false
local devices_inited = 0

-- WebSocket OpCodes
local CONTINUE_FRAME = 0
local TEXT_FRAME = 1
local BINARY_FRAME = 2
local CONNECTED_CLOSE_FRAME = 8
local PING_FRAME = 9
local PONG_FRAME = 10

-- WebSocket Constants
local SSL_PARMS = {
                    mode = "client",
                    protocol = "any",
                    verify = "none",
                    options = "all"
                  }

-- CONSTANTS
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

local MAXCMDIDS = 99
local MAX_CMD_AGE = 30000    -- (milliseconds) if sent cmds old, they'll be deleted (assume they were ignored by hub)

local REMOTE_INPUT_TIMEOUT = 5
local TV_SELECTOR_SCAN_INTERVAL = 5
local TV_SELECTOR_CANDIDATE_TIMEOUT = 30

DEVICE_PROFILE = 'lgtv.v2d'
local TV_SELECTOR_DEVICE_NETWORK_ID = 'lgtv-tv-selector'
local TV_SELECTOR_PROFILE = 'lgtv.selector'

local function is_tv_selector(device)
  return device.device_network_id == TV_SELECTOR_DEVICE_NETWORK_ID
end

local function is_remote_control_enabled(device)
  return device.preferences.enableRemoteControl == true
end

------------------------------------------------------------------------

local clear_connection
local schedule_reconnect
local clear_remote_input


function send_command(device, msgdata)
  
  local client = device:get_field('ws_client')
  if client then
  
    local ok, close_was_clean, close_code, close_reason = client:send(msgdata)

    if not ok then
      log.error ('Websocket Send failed:')
      log.error (close_was_clean, close_code, close_reason)
      local sock = device:get_field('ws_sock')
      clear_connection(device, sock, true)
      device:offline()
      device:emit_event(cap_status.status('Connect retry...'))
      schedule_reconnect(device)
      return false
    else
      log.info ('Message sent')
      return true
    end

  else
    log.warn ('Cannot send message; not connected', msgdata)
    schedule_reconnect(device)
    return false
  end

end


local wsmsgid = 0

local function gen_msgid(prefix)

  wsmsgid = wsmsgid + 1
  
  if wsmsgid > 999 then; wsmsgid = 1; end

  if prefix then
    return prefix .. '_' .. tostring(wsmsgid)
  else
    return tostring(wsmsgid)
  end
  
end

local function build_messsage(msgtype, uri, payload, prefix)

  local msgobj = {}
  
  msgobj.type = msgtype
  msgobj.id = gen_msgid(prefix)
  msgobj.uri = uri
  if payload then
    msgobj.payload = payload
  end
  
  return cx.encode_json(msgobj), msgobj.id

end


local function reset_remote_input_request(device, clear_pending)

  local timer = device:get_field('remote_input_request_timer')
  if timer then
    thisDriver:cancel_timer(timer)
  end

  device:set_field('remote_input_request_id', nil)
  device:set_field('remote_input_request_timer', nil)
  device:set_field('remote_input_connecting', false)
  if clear_pending then
    device:set_field('remote_input_pending_buttons', nil)
  end

end


local function request_remote_input_socket(device)

  if not is_remote_control_enabled(device) then
    return false
  end

  if device:get_field('remote_input_client')
     or device:get_field('remote_input_request_id')
     or device:get_field('remote_input_connecting') then
    return true
  end

  if not device:get_field('ws_client') then
    return false
  end

  local message, request_id = build_messsage(
    "request",
    "ssap://com.webos.service.networkinput/getPointerInputSocket",
    nil,
    "remote_input"
  )
  device:set_field('remote_input_request_id', request_id)

  local timer = thisDriver:call_with_delay(REMOTE_INPUT_TIMEOUT, function()
    if device:get_field('remote_input_request_id') == request_id then
      reset_remote_input_request(device, true)
      log.warn('Timed out waiting for LG remote input socket')
    end
  end)
  device:set_field('remote_input_request_timer', timer)

  if not send_command(device, message) then
    reset_remote_input_request(device, true)
    return false
  end

  return true

end

local function update_device(device)

  send_command(device, build_messsage("request", "ssap://com.webos.service.tvpower/power/getPowerState"))
  
  send_command(device, build_messsage("request", "ssap://com.webos.service.apiadapter/audio/getSoundOutput"))
  
  send_command(device, build_messsage("request", "ssap://audio/getStatus"))
  
  send_command(device, build_messsage("request", "ssap://tv/getCurrentChannel"))
  
  send_command(device, build_messsage("request", "ssap://com.webos.applicationManager/getForegroundAppInfo"))

  send_command(device, build_messsage("request", "ssap://tv/getExternalInputList"))

end

local function reset_refresh_timer(device)

  if device:get_field('refresh_timer') then; thisDriver:cancel_timer(device:get_field('refresh_timer')); end
  
  local timer = thisDriver:call_on_schedule(device.preferences.freq, function()
      update_device(device)
    end)
    
  device:set_field('refresh_timer', timer)

end


local function init_device(device)

  update_device(device)
  
  send_command(device, build_messsage("request", "ssap://com.webos.applicationManager/listApps"))
  if is_remote_control_enabled(device) then
    request_remote_input_socket(device)
  else
    reset_remote_input_request(device, true)
    clear_remote_input(device, true)
  end

  if device:get_field('screen_on_requested') then
    if send_command(device, build_messsage("request", "ssap://com.webos.service.tvpower/power/turnOnScreen")) then
      device:set_field('screen_on_requested', nil)
      device:set_field('screen_off_mode', false, { ['persist'] = true })
      send_command(device, build_messsage("request", "ssap://com.webos.service.tvpower/power/getPowerState"))
    end
  elseif device:get_field('screen_off_mode') then
    local screen_off_uri = device.preferences.keepConnectionWhenOff ~= false
      and "ssap://com.webos.service.tvpower/power/turnOffScreen"
      or "ssap://system/turnOff"
    if send_command(device, build_messsage("request", screen_off_uri)) then
      device:set_field('screen_off_mode', screen_off_uri ~= "ssap://system/turnOff", { ['persist'] = true })
      send_command(device, build_messsage("request", "ssap://com.webos.service.tvpower/power/getPowerState"))
    end
  end
  
  reset_refresh_timer(device)

end


local function update_remote_input_sources(device, sources)

  local input_sources = {}
  local labels_by_app = {}
  local supported_sources = {}

  for _, source in ipairs(sources) do
    if type(source) == 'table' then
      local input_id = source.id
      if type(input_id) ~= 'string' or input_id == '' then
        input_id = source.inputId
      end

      local app_id = type(source.appId) == 'string' and source.appId or nil
      local label = type(source.label) == 'string' and source.label or nil
      if not label or label == '' then
        label = (app_id and INPUT_SOURCE_LABELS_BY_APP[app_id]) or input_id
      end

      if type(input_id) == 'string' and input_id ~= ''
         and type(label) == 'string' and label ~= '' then
        local normalized_label = string.lower(label):gsub("[%s_%-]", "")
        local hdmi_number = string.match(normalized_label, "^hdmi(%d+)$")
        local usb_number = string.match(normalized_label, "^usb(%d+)$")

        if app_id == 'com.webos.app.livetv'
           or normalized_label == 'livetv'
           or normalized_label == 'digitaltv'
           or normalized_label == 'tv' then
          label = 'LIVE TV'
        elseif hdmi_number then
          label = 'HDMI ' .. hdmi_number
        elseif normalized_label == 'av1' or normalized_label == 'avinput' then
          label = 'AV'
        elseif normalized_label == 'component1' then
          label = 'Component'
        elseif usb_number then
          label = 'USB ' .. usb_number
        elseif normalized_label == 'usb' then
          label = 'USB'
        end

        if input_sources[label] then
          label = label .. ' (' .. input_id .. ')'
        end

        input_sources[label] = { input_id = input_id, app_id = app_id }
        table.insert(supported_sources, label)
        if app_id then
          labels_by_app[app_id] = label
        end
      else
        log.warn('Ignoring external input with no usable ID or label')
      end
    end
  end

  if not input_sources['LIVE TV'] then
    input_sources['LIVE TV'] = {
      input_id = 'Live_TV',
      app_id = 'com.webos.app.livetv'
    }
    table.insert(supported_sources, 'LIVE TV')
  end
  labels_by_app['com.webos.app.livetv'] = labels_by_app['com.webos.app.livetv'] or 'LIVE TV'

  device:set_field('remote_input_sources', input_sources)
  device:set_field('remote_input_labels_by_app', labels_by_app)
  device:emit_event(cap_remote.supportedInputSources(supported_sources))

  local current_app_id = device:get_field('current_app_id')
  local current_input_label = current_app_id and labels_by_app[current_app_id]
  if current_input_label then
    device:emit_event(cap_remote.inputSource(current_input_label))
    local legacy_label = INPUT_SOURCE_LABELS_BY_APP[current_app_id]
    if legacy_label then
      device:emit_event(cap_lginput.inputsource(legacy_label))
    end
  end

end


local function parse_response(device, payload)


  local is_applist = false

  for key, value in pairs(payload) do
  
    if key == 'state' then
      local tv_is_on = value ~= 'Power Off'
        and value ~= 'Suspend'
        and value ~= 'Request Suspend'
        and value ~= 'Active Standby'
      local power_state = tv_is_on and 'on' or 'off'
      local screen_is_on = tv_is_on and value ~= 'Screen Off'
      device:emit_event(cap_power_state.powerState(power_state))
      device:emit_event(cap_screen_state.screenState(screen_is_on and 'on' or 'off'))
      if screen_is_on then
        device:emit_event(capabilities.switch.switch('on'))
      else
        device:emit_event(capabilities.switch.switch('off'))
      end
      
    elseif key == 'volume' then
      device:emit_event(capabilities.audioVolume.volume(tonumber(value)))
      
    elseif key == 'mute' then
      local mutestate = {['true'] = 'muted', ['false'] = 'unmuted'}
      device:emit_event(capabilities.audioMute.mute(mutestate[tostring(value)]))
      
    elseif key == 'devices' and type(value) == 'table' then
      update_remote_input_sources(device, value)

    elseif key == 'apps' then
    
      local applist = {}
      for _, app in ipairs(value) do
        table.insert(applist, { id = app.id, name = app.title })
      end
      device:emit_event(capabilities.mediaPresets.presets(applist))
      is_applist = true
        
    elseif key == 'channelName' then
      
      local channel = payload.channelNumber .. ' - ' .. value
      device:emit_component_event(device.profile.components.main, cap_channel.currentChannel(channel))
      device:emit_component_event(device.profile.components.main, cap_channel_number.channelNumber(tonumber(payload.channelNumber)))
    
    elseif (key == 'appId') or ((key == 'id') and (is_applist == false)) then
    
      if type(value) == 'string' then
        device:set_field('current_app_id', value)
      end

      local appname

      local main_state = device.state_cache and device.state_cache.main
      local preset_state = main_state and main_state.mediaPresets and main_state.mediaPresets.presets
      if preset_state and type(preset_state.value) == 'table' then
        for _, element in ipairs(preset_state.value) do
          if element.id == value then
            appname = element.name
            break
          end
        end
      end

      local mediainputsource = type(value) == 'string' and INPUT_SOURCE_LABELS_BY_APP[value] or nil
      if appname then

        log.debug ('App name:', appname)
        device:emit_event(cap_app.currentApp(appname))
      else
        log.debug ('App name not determined:', value)
      end

      if mediainputsource then
        device:emit_event(cap_lginput.inputsource(mediainputsource))
      end

      local labels_by_app = device:get_field('remote_input_labels_by_app')
      local remote_input_source = type(value) == 'string' and labels_by_app and labels_by_app[value] or mediainputsource
      if remote_input_source then
        device:emit_event(cap_remote.inputSource(remote_input_source))
      end
    
    end
  end

end


clear_remote_input = function(device, close_socket)

  local sock = device:get_field('remote_input_sock')
  local client = device:get_field('remote_input_client')

  if sock then
    thisDriver:unregister_channel_handler(sock)
  end

  if close_socket then
    if client then
      client:close(1000, 'Remote input connection closed')
    end
    if sock then
      sock:close()
    elseif client then
      client:sock_close()
    end
  end

  device:set_field('remote_input_client', nil)
  device:set_field('remote_input_sock', nil)

end


local function send_remote_input_button(device, button)

  if not is_remote_control_enabled(device) then
    return false
  end

  local client = device:get_field('remote_input_client')
  if not client then
    return false
  end

  local message = 'type:button\nname:' .. button .. '\n\n'
  local ok, close_was_clean, close_code, close_reason = client:send(message)
  if not ok then
    log.error('Remote input send failed:', close_was_clean, close_code, close_reason)
    clear_remote_input(device, true)
    return false
  end

  if button == 'MUTE' then
    thisDriver:call_with_delay(1, function()
      send_command(device, build_messsage("request", "ssap://audio/getStatus"))
    end)
  end

  return true

end


local function connect_remote_input(device, socket_path)

  if not is_remote_control_enabled(device) then
    reset_remote_input_request(device, true)
    clear_remote_input(device, true)
    return
  end

  if not device:get_field('remote_input_connecting') then
    return
  end

  clear_remote_input(device, true)

  local client = ws.client.sync({timeout=2})
  if not client then
    log.error('Failed to create remote input websocket client')
    device:set_field('remote_input_connecting', false)
    device:set_field('remote_input_pending_buttons', nil)
    return
  end

  local ok, code, headers, sock = client:connect(socket_path, nil, SSL_PARMS)
  if not ok then
    client:sock_close()
    log.error('Could not connect to LG remote input socket:', code)
    device:set_field('remote_input_connecting', false)
    device:set_field('remote_input_pending_buttons', nil)
    return
  end

  device:set_field('remote_input_client', client)
  device:set_field('remote_input_sock', sock)
  device:set_field('remote_input_connecting', false)

  thisDriver:register_channel_handler(sock, function()
    local response, opcode, close_was_clean, close_code, err = client:receive()

    if opcode == PING_FRAME then
      local sent, send_close_was_clean, send_close_code, send_close_reason = client:send(response, PONG_FRAME)
      if not sent then
        log.error('Remote input PONG failed:', send_close_was_clean, send_close_code, send_close_reason)
        clear_remote_input(device, true)
        return
      end
    elseif opcode == CONNECTED_CLOSE_FRAME then
      log.warn('LG remote input socket closed')
      clear_remote_input(device, true)
      return
    end

    if err then
      if err == 'closed' then
        log.warn('LG remote input socket disconnected')
      else
        log.error('Remote input receive error:', err)
      end
      clear_remote_input(device, false)
    end
  end)

  local pending_buttons = device:get_field('remote_input_pending_buttons') or {}
  device:set_field('remote_input_pending_buttons', nil)
  for _, button in ipairs(pending_buttons) do
    if not send_remote_input_button(device, button) then
      break
    end
  end

end


local function handle_response_frame(device, payload)

  local response_table = cx.decode_json(payload)
  if response_table == nil then; return; end
  
  --cx.disptable(response_table, '  ', 3)
  
  if response_table.type == 'response' then
    local remote_request_id = device:get_field('remote_input_request_id')
    if remote_request_id and response_table.id == remote_request_id then
      reset_remote_input_request(device, false)
      local response_payload = response_table.payload
      if response_payload and response_payload.returnValue == true
         and type(response_payload.socketPath) == 'string' then
        device:set_field('remote_input_connecting', true)
        device.thread:queue_event(connect_remote_input, device, response_payload.socketPath)
      else
        reset_remote_input_request(device, true)
        log.error(
          'LG remote input socket request failed:',
          response_payload and response_payload.errorText or response_table.error
        )
      end
    end

    if response_table.id == 'register_0' then
      if response_table.payload.pairingType == 'PROMPT' then
        log.info('Pairing...')
        device:emit_event(cap_status.status('Pairing'))
      else
        log.warn('Unexpected pairing type', response_table.payload.pairintType)
        device:emit_event(cap_status.status(response_table.payload.pairingType))
      end
    else
      log.info(string.format('Response message to be handled id=%s:', response_table.id))
      if response_table.payload then
        if not response_table.payload.apps then
          cx.disptable(response_table.payload, '  ', 4)
        end
        
        print ("returnValue:", response_table.payload.returnValue, type(response_table.payload.returnValue))
        if response_table.payload.returnValue == true then
          parse_response(device, response_table.payload)
        else
          log.error('Unexpected returnValue', response_table.payload.returnValue)
        end
      else
        log.warn('Empty payload - no action taken')
      end
    end
  
  elseif response_table.type == 'registered' then
    log.info ('Successfully registered with LG webOS; key=', response_table.payload['client-key'])
    device:set_field('lg_registration_key', response_table.payload['client-key'], { ['persist'] = true })
    device:emit_event(cap_status.status('Registered'))
    device:set_field('unsigned_pairing_attempted', false)
    init_device(device)
  
  elseif response_table.type == 'error' then
    local payload_error = ''
    if response_table.payload and response_table.payload.errorText then
      payload_error = tostring(response_table.payload.errorText)
    end
    local error_text = tostring(response_table.error or '') .. ' ' .. payload_error
    local normalized_error = string.lower(error_text)

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
    elseif string.find(normalized_error, 'no active broadcast', 1, true)
       or string.find(normalized_error, 'utp/bind returns invalid result', 1, true) then
      log.debug('No active broadcast channel; current channel is unavailable')
    else
      log.error(string.format('Error reported in response: %s - %s', tostring(response_table.error), payload_error))
    end
  
  else
    log.warn(string.format('Unexpected message type: %s; with following payload:', response_table.type))
    if response_table.payload then
      cx.disptable(response_table.payload, '  ', 4)
    end
  end
  
end


local function handshake_lgtv(device)

  local handshake = clone_table(authdata)

  if device:get_field('lg_registration_key') then
    log.info('Handshake')
    handshake.payload['client-key'] = device:get_field('lg_registration_key')
  end
  
  send_command(device, cx.encode_json(handshake))

end


local RECONNECT_DELAY = 5
local PING_INTERVAL = 10
local PING_TIMEOUT = 30
local WAKE_RETRY_WINDOW = 120
local WOL_RETRY_INTERVAL = 15

clear_connection = function(device, sock, close_socket)

  reset_remote_input_request(device, true)
  clear_remote_input(device, true)

  if sock then
    thisDriver:unregister_channel_handler(sock)
    if close_socket then
      sock:close()
    end
  end

  device:set_field('ws_client', nil)
  device:set_field('ws_sock', nil)
  device:emit_event(cap_power_state.powerState('unknown'))
  device:emit_event(cap_screen_state.screenState('unknown'))

end

schedule_reconnect = function(device)

  if device:get_field('retrytimer') then
    return
  end

  local retrytimer = thisDriver:call_with_delay(RECONNECT_DELAY, function()
    device:set_field('retrytimer', nil)

    local wake_retry_until = device:get_field('wake_retry_until')
    if wake_retry_until then
      local now = socket.gettime()
      if now >= wake_retry_until then
        device:set_field('wake_retry_until', nil)
        device:set_field('last_wol_at', nil)
      elseif now - (device:get_field('last_wol_at') or 0) >= WOL_RETRY_INTERVAL then
        device:set_field('last_wol_at', now)
        wol.do_wakeonlan(device.preferences.macaddr, device.preferences.bcastaddr)
      end
    end

    init_connection(device)
  end)
  device:set_field('retrytimer', retrytimer)

end


local function pingmonitor()

  log.debug('Checking last pings...')

  local devicelist = thisDriver:get_devices()
  
  for _, device in ipairs(devicelist) do
  
    local client = device:get_field('ws_client')
    if client then

      local now = socket.gettime()
      local lastping = device:get_field('lastping') or now
      device:set_field('lastping', lastping)
      local time_since_last_ping = now - lastping
    
      if time_since_last_ping > PING_TIMEOUT then
      
        log.warn(string.format('%s has not pinged in %s seconds', device.label, time_since_last_ping))
        
        device:offline()
        local sock = device:get_field('ws_sock')
        clear_connection(device, sock, true)
        device:emit_event(cap_status.status('Connect retry...'))
        schedule_reconnect(device)

      else

        local ping_ok = client:send('', PING_FRAME)
        if not ping_ok then
          log.warn(string.format('%s heartbeat send failed', device.label))
          device:offline()
          local sock = device:get_field('ws_sock')
          clear_connection(device, sock, true)
          device:emit_event(cap_status.status('Connect retry...'))
          schedule_reconnect(device)
        end
        
      end
    end
  end

end


-- Initialize hub connection
function init_connection(device)

  device:emit_event(cap_power_state.powerState('unknown'))
  device:emit_event(cap_screen_state.screenState('unknown'))

  if not device:get_field('lg_registration_key') then
    device:set_field('unsigned_pairing_attempted', false)
  end
  local wssaddr = device:get_field('WSSaddr')
  log.debug ('Retrieved device address:', wssaddr)

  local uri = 'wss://' .. wssaddr
  --local uri = 'ws://' .. wssaddr
  
  log.info (string.format('Initializing %s at %s', device.label, uri))

  local client = ws.client.sync({timeout=2})
          
  if not client then
    log.error ('Failed to create websocket client')
    return
  end
  
  local ok, code, headers, sock = client:connect(uri,'echo', SSL_PARMS)
  --local ok, code, headers, sock = client:connect(uri,'echo')
  
  log.info (string.format('%s: WS Connect returned: ok=%s, code=%s, headers=%s', device.label, ok, code, headers))
  
  if not ok then
    log.error ('Could not connect:', code)
    log.info(string.format('%s: WS Connect will retry in %s seconds', device.label, RECONNECT_DELAY))
    device:emit_event(cap_status.status('Connect retry (' .. wssaddr .. ')'))
    schedule_reconnect(device)
    return
  end
  
  -- Get here if connected successfully
  device:online()
  device:emit_event(cap_status.status('Connected'))
  
  device:set_field('retrytimer', nil)
  device:set_field('wake_retry_until', nil)
  device:set_field('last_wol_at', nil)
  device:set_field('ws_client', client)
  device:set_field('ws_sock', sock)
  device:set_field('lastping', socket.gettime())

  thisDriver:register_channel_handler(sock, function ()
      local payload, opcode, c, d, err = client:receive()
      
      log.debug (string.format('Received opcode=%s, c=%s, d=%s, err=%s', opcode, c, d, err))

      if opcode then
        device:set_field('lastping', socket.gettime())
      end
      
      if opcode ~= PING_FRAME then
        
        if opcode == TEXT_FRAME then
          log.debug ('WS Receive TEXT frame payload')
          log.debug (payload)
          handle_response_frame(device, payload)
          
        elseif opcode == CONNECTED_CLOSE_FRAME then
          log.warn ('Connection has been closed by request')
          device:emit_event(cap_status.status('Connection closed'))
          clear_connection(device, sock, true)
          device:offline()
          device:emit_event(cap_status.status('Connect retry...'))
          schedule_reconnect(device)
          return
        end
        
      else
        client:send(payload, PONG_FRAME)
        device:set_field('lastping', socket.gettime())
      end
      
      if err then
      
        if err == 'closed' then
          log.warn ('Connection has been closed')
        else
          log.error ('Receive error:', err)
          device:offline()
        end
        
        clear_connection(device, sock, false)
        device:emit_event(cap_status.status('Connect retry...'))
        log.info(string.format('%s: WS Re-Connect attempt in %s seconds', device.label, RECONNECT_DELAY))
        schedule_reconnect(device)
        return
        
      end
    end)
 
  handshake_lgtv(device)
  
end


local function shutdown_device(driver, device, msg)

  reset_remote_input_request(device, true)
  clear_remote_input(device, true)

  if device:get_field('retrytimer') then
    thisDriver:cancel_timer(device:get_field('retrytimer'))
    device:set_field('retrytimer', nil)
  end
  
  if device:get_field('refresh_timer') then
    thisDriver:cancel_timer(device:get_field('refresh_timer'))
  end

  local client = device:get_field('ws_client')
  if client then
    local was_clean,code,reason = client:close(1000, msg)
    log.debug('Client close result:', was_clean, code, reason)
  end
  
  device:set_field('ws_client', nil)
  device:set_field('ws_sock', nil)
  device:set_field('lastping', nil)

end


local function update_known_tv_address(device, ip)

  local new_wssaddr = ip .. ':' .. WSSPORT
  local old_wssaddr = device:get_field('WSSaddr')
  if old_wssaddr ~= new_wssaddr then
    log.warn(string.format('%s address changed from %s to %s', device.label, tostring(old_wssaddr), new_wssaddr))
    device:set_field('WSSaddr', new_wssaddr, { ['persist'] = true })
    local sock = device:get_field('ws_sock')
    clear_connection(device, sock, true)
    device:offline()
    device:emit_event(cap_status.status('Address updated; reconnecting'))
    schedule_reconnect(device)
  end

end


local function scan_selector_tvs(driver, selector)

  if not selector:get_field('selector_scan_active')
     or selector:get_field('selector_scan_running') then
    return
  end

  selector:set_field('selector_scan_running', true)
  local known_devices = {}
  for _, device in ipairs(driver:get_devices()) do
    if not is_tv_selector(device) then
      known_devices[device.device_network_id] = device
    end
  end

  local discovered_tvs = selector:get_field('discovered_lg_tvs') or {}

  local function record_lgdevice(lgdevice)
    local uuid = lgdevice.uuid
    local known_device = known_devices[uuid]
    if known_device then
      update_known_tv_address(known_device, lgdevice.ip)
    end
    if newly_added[uuid] then
      discovered_tvs[uuid] = nil
    else
      local label = known_device and known_device.label or lgdevice.name or 'LG webOS TV'
      local model = lgdevice.model
      if type(model) == 'string' and model ~= '' and model ~= 'LGE webOS TV'
         and not string.find(label, model, 1, true) then
        label = label .. ' (' .. model .. ')'
      end
      if known_device then
        label = label .. ' (이미 추가됨)'
      end
      label = label .. ' [' .. lgdevice.ip .. ']'

      discovered_tvs[uuid] = {
        device = lgdevice,
        label = label,
        already_added = known_device ~= nil,
        last_seen = socket.gettime()
      }
    end
  end

  discovery.find(nil, record_lgdevice)

  local now = socket.gettime()
  local presets = {}
  for uuid, tv in pairs(discovered_tvs) do
    if not tv.last_seen or now - tv.last_seen > TV_SELECTOR_CANDIDATE_TIMEOUT then
      discovered_tvs[uuid] = nil
    else
      table.insert(presets, { id = uuid, name = tv.label })
    end
  end

  table.sort(presets, function(left, right) return left.name < right.name end)
  selector:set_field('discovered_lg_tvs', discovered_tvs)
  selector:emit_event(capabilities.mediaPresets.presets(presets))

  local status = #presets == 0
    and '주변에서 LG TV를 찾지 못했습니다'
    or string.format('%d대의 LG TV를 찾았습니다. 목록에서 선택하세요.', #presets)
  selector:emit_event(cap_status.status(status))

  selector:set_field('selector_scan_running', nil)
  if selector:get_field('selector_scan_active') then
    local timer = driver:call_with_delay(TV_SELECTOR_SCAN_INTERVAL, function()
      selector:set_field('selector_scan_timer', nil)
      if selector:get_field('selector_scan_active') then
        selector.thread:queue_event(scan_selector_tvs, driver, selector)
      end
    end)
    selector:set_field('selector_scan_timer', timer)
  end

end


local function start_selector_scan(driver, selector)

  selector:set_field('selector_scan_active', true)
  local timer = selector:get_field('selector_scan_timer')
  if timer then
    driver:cancel_timer(timer)
    selector:set_field('selector_scan_timer', nil)
  end

  if not selector:get_field('selector_scan_running') then
    selector.thread:queue_event(scan_selector_tvs, driver, selector)
  end

end


local function stop_selector_scan(driver, selector)

  selector:set_field('selector_scan_active', false)
  local timer = selector:get_field('selector_scan_timer')
  if timer then
    driver:cancel_timer(timer)
    selector:set_field('selector_scan_timer', nil)
  end

end


local function refresh_known_tv_addresses(driver)

  local known_devices = {}
  for _, device in ipairs(driver:get_devices()) do
    if not is_tv_selector(device) then
      known_devices[device.device_network_id] = device
    end
  end

  if next(known_devices) == nil then
    return
  end

  discovery.find(nil, function(lgdevice)
    local known_device = known_devices[lgdevice.uuid]
    if known_device then
      update_known_tv_address(known_device, lgdevice.ip)
    end
  end)

end


------------------------------------------------------------------------
--                    CAPABILITY HANDLERS
------------------------------------------------------------------------


local function handle_refresh(driver, device, command)
  -- note: refreshes can be Edge-induced or user-induced
  log.info (string.format('>>> Refresh requested for %s<<<', device.label))

  if is_tv_selector(device) then
    start_selector_scan(driver, device)
    return
  end
  
 
  -- Inhibit refreshes during device creation
  local gorefresh = true
  if device:get_field('createtime') then
    local now = socket.gettime()
    local diff = now - device:get_field('createtime')
    log.debug ('Time since creation', diff)
    if diff < 5 then
      gorefresh = false
    end
  end
  
  if gorefresh then
  
    if not device:get_field('ws_client') then
      if device:get_field('retrytimer') then
        driver:cancel_timer(device:get_field('retrytimer'))
        device:set_field('retrytimer', nil)
      end
      
      device.thread:queue_event(init_connection, device)
      
    else
      init_device(device)
    end
      
    device:set_field('lastrefresh', socket.gettime())
    
  else
    log.info ('>>>> Refresh ignored')
  end
end


local function handle_switch(driver, device, command)

  log.debug ('Switch changed to', command.command)
  
  if command.command == 'on' then
    local connected = device:get_field('ws_client') ~= nil

    if connected and device:get_field('screen_off_mode') then
      connected = send_command(device, build_messsage("request", "ssap://com.webos.service.tvpower/power/turnOnScreen"))
      if connected then
        device:set_field('screen_off_mode', false, { ['persist'] = true })
        send_command(device, build_messsage("request", "ssap://com.webos.service.tvpower/power/getPowerState"))
      end
    end

    if not connected then
      if device:get_field('screen_off_mode') then
        device:set_field('screen_on_requested', true)
      end
      local wake_sent = wol.do_wakeonlan(device.preferences.macaddr, device.preferences.bcastaddr)
      if wake_sent then
        local now = socket.gettime()
        device:set_field('wake_retry_until', now + WAKE_RETRY_WINDOW)
        device:set_field('last_wol_at', now)
        local sock = device:get_field('ws_sock')
        clear_connection(device, sock, true)
        device:offline()
      end

      if not device:get_field('ws_client') then
        local retrytimer = device:get_field('retrytimer')
        if retrytimer then
          driver:cancel_timer(retrytimer)
          device:set_field('retrytimer', nil)
        end
        schedule_reconnect(device)
      end
    end
  else
    device:set_field('wake_retry_until', nil)
    device:set_field('last_wol_at', nil)
    if device.preferences.keepConnectionWhenOff ~= false then
      if device:get_field('ws_client') then
        if send_command(device, build_messsage("request", "ssap://com.webos.service.tvpower/power/turnOffScreen")) then
          device:set_field('screen_off_mode', true, { ['persist'] = true })
          send_command(device, build_messsage("request", "ssap://com.webos.service.tvpower/power/getPowerState"))
        end
      else
        log.info('Screen-off request skipped while disconnected; reconnecting')
        schedule_reconnect(device)
      end
    else
      device:set_field('screen_off_mode', false, { ['persist'] = true })
      if device:get_field('ws_client') then
        send_command(device, build_messsage("request", "ssap://system/turnOff"))
      else
        log.info('Power-off request skipped while disconnected; reconnecting')
        schedule_reconnect(device)
      end
    end
  end
  
end


local function _handle_volume(device, command)

  local volume = device.state_cache.main.audioVolume.volume.value
  local bump = device.preferences.volbump or 1
  if command.command == 'volumeDown' then; bump = bump * -1; end
  volume = volume + bump
  if volume > 100 then; volume = 100; end
  if volume < 0 then; volume = 0; end
  device:emit_event(capabilities.audioVolume.volume(volume))
  
  for i = 1, device.preferences.volbump do
    send_command(device, build_messsage("request", "ssap://audio/" .. command.command))
    socket.sleep(.1)
  end

end

local function handle_volume(_, device, command)

  log.debug(string.format("Volume command received: %s, arg=%s", command.command, command.args.volume))
  
  if command.command == 'setVolume' then
  
    device:emit_event(capabilities.audioVolume.volume(command.args.volume))
    send_command(device, build_messsage("request", "ssap://audio/setVolume", {volume=command.args.volume}))
    
  elseif (command.command == 'volumeUp') or (command.command == 'volumeDown') then
  
    _handle_volume(device, command)
    
  end
end


local function handle_mute(_, device, command)

  log.debug("Mute set to " .. command.command, command.args.state)
  
  local newstate
  
  if command.command == 'setMute' then
    newstate = command.args.state
  else
    newstate = command.command .. 'd'
  end
  
  device:emit_event(capabilities.audioMute.mute(newstate))
  
  local lgmute = { muted = true, unmuted = false }
  
  send_command(device, build_messsage("request", "ssap://audio/setMute", {mute=lgmute[newstate]}))

end


local function handle_volup(_, device, command)

  _handle_volume(device, {command = 'volumeUp'})

end


local function handle_voldown(_, device, command)

  _handle_volume(device, {command = 'volumeDown'})

end


local function handle_app(driver, device, command)

  local preset_id = command.args and command.args.presetId
  if is_tv_selector(device) then
    if type(preset_id) == 'string' and newly_added[preset_id] then
      stop_selector_scan(driver, device)
      log.info('Selected LG TV is already being added:', preset_id)
      return
    end

    local discovered_tvs = device:get_field('discovered_lg_tvs') or {}
    local selected_tv = type(preset_id) == 'string' and discovered_tvs[preset_id] or nil
    if not selected_tv then
      log.warn('Selected LG TV is no longer available; refresh the selector:', preset_id)
      start_selector_scan(driver, device)
      return
    end

    for _, existing_device in ipairs(driver:get_devices()) do
      if existing_device.device_network_id == preset_id then
        log.info('Attempting to connect to selected LG TV:', preset_id)
          stop_selector_scan(driver, device)
          device:emit_event(cap_status.status('선택한 TV에 연결을 시도합니다. TV 화면을 확인해 주세요.'))
          handle_refresh(driver, existing_device, { command = 'refresh' })
          return
      end
    end

    stop_selector_scan(driver, device)
    local lgdevice = selected_tv.device
    local create_device_msg = {
      type = 'LAN',
      device_network_id = preset_id,
      label = selected_tv.label,
      profile = DEVICE_PROFILE,
      manufacturer = 'LG',
      model = lgdevice.model,
      vendor_provided_label = 'LGE WebOS TV',
    }

    newly_added[preset_id] = lgdevice

    local remaining_tvs = {}
    local remaining_presets = {}
    for uuid, tv in pairs(discovered_tvs) do
      if uuid ~= preset_id then
        remaining_tvs[uuid] = tv
        table.insert(remaining_presets, { id = uuid, name = tv.label })
      end
    end
    table.sort(remaining_presets, function(left, right) return left.name < right.name end)
    device:set_field('discovered_lg_tvs', remaining_tvs)
    device:emit_event(capabilities.mediaPresets.presets(remaining_presets))
    device:emit_event(cap_status.status('TV 화면에서 페어링을 허용해 주세요.'))

    disco_sem:acquire(function()
      log.info_with({ hub_logs = true },
        string.format('Create selected LG TV with: %s', utils.stringify_table(create_device_msg)))
      assert(driver:try_create_device(create_device_msg), 'failed to create selected LG TV')
    end)

    return
  end

  log.info ('Media Preset action:', command.command, preset_id)

  send_command(device, build_messsage("request", "ssap://system.launcher/launch", {id=preset_id}))
  
end


local function find_streaming_app_id(device, aliases)

  local main_state = device.state_cache and device.state_cache.main
  local preset_state = main_state and main_state.mediaPresets and main_state.mediaPresets.presets
  local presets = preset_state and preset_state.value
  if type(presets) ~= 'table' then
    return nil
  end

  for _, app in ipairs(presets) do
    if type(app) == 'table' and type(app.id) == 'string' then
      local app_name = type(app.name) == 'string' and app.name or ''
      local searchable_name = string.lower(app_name):gsub("[%s%p]", "")
      local searchable_id = string.lower(app.id):gsub("[%s%p]", "")
      for _, alias in ipairs(aliases) do
        if string.find(searchable_name, alias, 1, true)
           or string.find(searchable_id, alias, 1, true) then
          return app.id
        end
      end
    end
  end

  return nil

end


local function handle_channel(driver, device, command)

  log.debug("Channel set to " .. command.command, command.args.tvChannel)
  
  device:emit_component_event(device.profile.components.main, capabilities.tvChannel.tvChannel(command.command))
  
  send_command(device, build_messsage("request", 'ssap://tv/' .. command.command))
  
  device:emit_component_event(device.profile.components.main, cap_channel.currentChannel(' '), { visibility = { displayed = false } })

  driver:call_with_delay(1, function()
      send_command(device, build_messsage("request", "ssap://tv/getCurrentChannel"))
    end)
    
end


local function handle_lgmessage(_, device, command)

  log.debug("Message set to " .. command.command, command.args.message)
  
  device:emit_event(cap_lgmsg.message(command.args.message))
  
  send_command(device, build_messsage("request", "ssap://system.notifications/createToast", {message=command.args.message}))
  
end


local function handle_lginput(driver, device, command)

  log.debug("Media Input set to " .. command.command, command.args.value)
  
  device:emit_event(cap_lginput.inputsource(command.args.value))
  
  if command.args.value == 'Live_TV' then
    send_command(device, build_messsage("request", "ssap://system.launcher/launch", {id='com.webos.app.livetv'}))
  else
    send_command(device, build_messsage("request", "ssap://tv/switchInput", {inputId=command.args.value}))
    
    driver:call_with_delay(1, function()
      send_command(device, build_messsage("request", "ssap://com.webos.applicationManager/getForegroundAppInfo"))
    end)
  end

end


local function handle_remote_button(driver, device, command)

  if not is_remote_control_enabled(device) then
    log.debug('Ignoring LG remote button while remote control is disabled')
    return
  end

  local key = command.args and command.args.key
  if type(key) ~= 'string' or not REMOTE_BUTTONS[key] then
    log.warn('Unsupported LG remote button:', key)
    return
  end

  if key == 'POWER' then
    local main_state = device.state_cache and device.state_cache.main
    local switch_state = main_state and main_state.switch and main_state.switch.switch
    local currently_on = switch_state and switch_state.value == 'on'
    if device:get_field('screen_off_mode') then
      currently_on = false
    end
    handle_switch(driver, device, { command = currently_on and 'off' or 'on' })
  elseif key == 'VOLUMEUP' then
    handle_volume(driver, device, { command = 'volumeUp', args = { volume = 0 } })
  elseif key == 'VOLUMEDOWN' then
    handle_volume(driver, device, { command = 'volumeDown', args = { volume = 0 } })
  elseif key == 'CHANNELUP' then
    handle_channel(driver, device, { command = 'channelUp', args = { tvChannel = '' } })
  elseif key == 'CHANNELDOWN' then
    handle_channel(driver, device, { command = 'channelDown', args = { tvChannel = '' } })
  else
    if not device:get_field('ws_client') then
      log.warn('Ignoring remote button while TV is disconnected:', key)
      schedule_reconnect(device)
      return
    end

    local app_aliases = STREAMING_APP_SHORTCUTS[key]
    if app_aliases then
      local app_id = find_streaming_app_id(device, app_aliases)
      if app_id then
        handle_app(driver, device, { command = 'playPreset', args = { presetId = app_id } })
        return
      elseif key ~= 'AMAZON' then
        log.warn('Streaming app is not installed or available:', key)
        return
      end
    end

    if device:get_field('remote_input_client') then
      send_remote_input_button(device, key)
    else
      local pending_buttons = device:get_field('remote_input_pending_buttons') or {}
      table.insert(pending_buttons, key)
      device:set_field('remote_input_pending_buttons', pending_buttons)
      if not request_remote_input_socket(device) then
        device:set_field('remote_input_pending_buttons', nil)
      end
    end
  end

end


local function handle_remote_input(driver, device, command)

  if not is_remote_control_enabled(device) then
    log.debug('Ignoring LG input selection while remote control is disabled')
    return
  end

  local value = command.args and command.args.value
  local input_sources = device:get_field('remote_input_sources')
  local source = type(value) == 'string' and input_sources and input_sources[value]
  if not source then
    log.warn('Unsupported LG TV input source:', value)
    return
  end

  local sent
  if source.app_id == 'com.webos.app.livetv' or source.input_id == 'Live_TV' then
    sent = send_command(
      device,
      build_messsage("request", "ssap://system.launcher/launch", { id = 'com.webos.app.livetv' })
    )
  else
    sent = send_command(device, build_messsage("request", "ssap://tv/switchInput", { inputId = source.input_id }))
  end

  if sent then
    device:emit_event(cap_remote.inputSource(value))
    local legacy_label = source.app_id and INPUT_SOURCE_LABELS_BY_APP[source.app_id] or value
    device:emit_event(cap_lginput.inputsource(legacy_label))
    driver:call_with_delay(1, function()
      send_command(device, build_messsage("request", "ssap://com.webos.applicationManager/getForegroundAppInfo"))
    end)
  end

end


------------------------------------------------------------------------
--                REQUIRED EDGE DRIVER HANDLERS
------------------------------------------------------------------------

-- Lifecycle handler to initialize existing devices AND newly discovered devices
local function device_init(driver, device)
  
  log.debug(device.label .. ": " .. device.device_network_id .. "> INITIALIZING")

  initialized = true

  devices_inited = devices_inited + 1

  if is_tv_selector(device) then
    start_selector_scan(driver, device)
    log.debug('Initialized LG TV selector')
    return
  end
  
  if not device:get_field('ws_client') then
    device.thread:queue_event(init_connection, device)
  end
  
  log.debug('Exiting device initialization')
end


-- Called when device was just created in SmartThings
local function device_added (driver, device)

  log.info(device.label .. ": " .. device.device_network_id .. "> ADDED")
  
  device:set_field('createtime', socket.gettime())

  if is_tv_selector(device) then
    newly_added[device.device_network_id] = nil
    device:emit_event(capabilities.mediaPresets.presets({}))
    device:emit_event(cap_status.status('주변 LG TV 검색 준비 완료'))
    disco_sem:release()
    return
  end
    
  local lgdevice = newly_added[device.device_network_id]
  if lgdevice then
    device:set_field('WSSaddr', lgdevice.ip .. ':' .. WSSPORT, { ['persist'] = true })
    newly_added[device.device_network_id] = nil
    log.debug('IP stored:', lgdevice.ip)
  end

  
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(cap_power_state.powerState('unknown'))
  device:emit_event(cap_screen_state.screenState('unknown'))
  device:emit_event(cap_lginput.inputsource('HDMI 1'))
  device:emit_event(cap_remote.inputSource('unknown'))
  device:emit_event(cap_remote.supportedInputSources({}))
  device:emit_event(capabilities.audioVolume.volume(50))
  device:emit_event(capabilities.audioMute.mute('unmuted'))
  device:emit_event(cap_app.currentApp(' '))
  device:emit_event(cap_lgmsg.message(' '))
  device:emit_event(cap_status.status('Created'))
  
  device:emit_component_event(device.profile.components.main, cap_channel.currentChannel(' '))
  device:emit_component_event(device.profile.components.main, cap_channel_number.channelNumber(0))
  device:emit_component_event(device.profile.components.main, capabilities.tvChannel.tvChannel('0'))
    
  disco_sem:release()
    
end

-- Called when device was deleted via mobile app
local function device_removed(driver, device)
  
  log.warn(device.id .. ": " .. device.device_network_id .. "> removed")

  if is_tv_selector(device) then
    stop_selector_scan(driver, device)
  end

  reset_remote_input_request(device, true)
  clear_remote_input(device, true)

  --shutdown_device(driver, device, 'Device removed')
  
  if #driver:get_devices() == 0 then
    log.warn ('All devices removed')
    initialized = false
  end
  
end


-- Called when SmartThings thinks the device needs provisioning
local function device_doconfigure (_, device)

  log.info ('Device doConfigure lifecycle invoked')

end


local function handler_driverchanged(driver, device, event, args)

  log.debug ('*** Driver changed handler invoked ***')

end

local function shutdown_handler(driver, event)

  if event == 'shutdown' then

    log.warn ('Shutting down all devices')
    local device_list = driver:get_devices()
    for _, device in ipairs(device_list) do
      if is_tv_selector(device) then
        stop_selector_scan(driver, device)
      end
      shutdown_device(driver, device, 'Driver shutdown')
    end
  end
end


local function handler_infochanged (driver, device, event, args)

  log.debug ('Info changed handler invoked')
  
  -- Did preferences change?
  if args.old_st_store.preferences then
    local old_preferences = args.old_st_store.preferences

    if old_preferences.enableRemoteControl ~= device.preferences.enableRemoteControl then
      if is_remote_control_enabled(device) then
        if device:get_field('ws_client') then
          send_command(device, build_messsage("request", "ssap://com.webos.applicationManager/listApps"))
          request_remote_input_socket(device)
        end
      else
        reset_remote_input_request(device, true)
        clear_remote_input(device, true)
      end
    end
    
    if old_preferences.freq ~= device.preferences.freq then
      log.info ('Refresh interval changed to: ', device.preferences.freq)
      reset_refresh_timer(device)
    end
  end
  
end


-- Device discovery handler
local function discovery_handler(driver, _, should_continue)
  
  log.info("Starting discovery")
  if not should_continue() then
    return
  end

  for _, device in ipairs(driver:get_devices()) do
    if is_tv_selector(device) then
      start_selector_scan(driver, device)
      log.info('Updated the LG TV selector list')
      return
    end
  end

  if newly_added[TV_SELECTOR_DEVICE_NETWORK_ID] then
    log.info('LG TV selector is already being added')
    return
  end

  local create_device_msg = {
    type = 'LAN',
    device_network_id = TV_SELECTOR_DEVICE_NETWORK_ID,
    label = 'LG TV 선택기',
    profile = TV_SELECTOR_PROFILE,
    manufacturer = 'LG',
    model = 'LG TV Selector',
    vendor_provided_label = 'LG TV Selector',
  }
  newly_added[TV_SELECTOR_DEVICE_NETWORK_ID] = true
  log.info_with({ hub_logs = true },
    string.format('Create LG TV selector with: %s', utils.stringify_table(create_device_msg)))
  disco_sem:acquire(function()
    assert(driver:try_create_device(create_device_msg), 'failed to create LG TV selector')
  end)

  log.info('Ending discovery')
end


-----------------------------------------------------------------------
--        DRIVER MAINLINE: Build driver context table
-----------------------------------------------------------------------
thisDriver = Driver("thisDriver", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    driverSwitched = handler_driverchanged,
    infoChanged = handler_infochanged,
    doConfigure = device_doconfigure,
    removed = device_removed
  },
  driver_lifecycle = shutdown_handler,
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch,
      [capabilities.switch.commands.off.NAME] = handle_switch,
    },
    [capabilities.tvChannel.ID] = {
      [capabilities.tvChannel.commands.setTvChannel.NAME] = handle_channel,
      [capabilities.tvChannel.commands.channelUp.NAME] = handle_channel,
      [capabilities.tvChannel.commands.channelDown.NAME] = handle_channel
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.setVolume.NAME] = handle_volume,
      [capabilities.audioVolume.commands.volumeUp.NAME] = handle_volume,
      [capabilities.audioVolume.commands.volumeDown.NAME] = handle_volume
    },
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.setMute.NAME] = handle_mute,
      [capabilities.audioMute.commands.mute.NAME] = handle_mute,
      [capabilities.audioMute.commands.unmute.NAME] = handle_mute
    },
    [cap_remote.ID] = {
      [cap_remote.commands.pressButton.NAME] = handle_remote_button,
      [cap_remote.commands.setInputSource.NAME] = handle_remote_input,
      [cap_remote.commands.selectRemoteInputSource.NAME] = handle_remote_input
    },
    [capabilities.mediaPresets.ID] = {
      [capabilities.mediaPresets.commands.playPreset.NAME] = handle_app,
    },
    [cap_lgmsg.ID] = {
      [cap_lgmsg.commands.setMessage.NAME] = handle_lgmessage
    },
    [cap_lginput.ID] = {
      [cap_lginput.commands.setInputSource.NAME] = handle_lginput
    },
    [cap_volup.ID] = {
      [cap_volup.commands.push.NAME] = handle_volup,
    },
		[cap_voldown.ID] = {
      [cap_voldown.commands.push.NAME] = handle_voldown,
    },
  }
})

log.info ('LG TV Driver V1.1 Started')

-- start ping monitor
thisDriver:call_on_schedule(PING_INTERVAL, pingmonitor)

disco_sem = semaphore()

thisDriver:call_with_delay(5, function()
  refresh_known_tv_addresses(thisDriver)
end)

thisDriver:call_on_schedule(300, function()
  refresh_known_tv_addresses(thisDriver)
end)

thisDriver:run()
