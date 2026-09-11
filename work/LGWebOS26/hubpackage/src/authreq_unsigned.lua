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