-- Privacy switches for the microphone and the camera.
--
-- The "privacy" metadata object holds them (subject 0), set by nx809j-privacy
-- from ~/.config/denial/privacy.json:
--   microphone, camera            "on" or "off", for every app
--   microphone.app.<binary>       "off" turns it off for that app only
--   camera.app.<binary>           (the same for the camera)
-- An app that is switched off doesn't see microphones (Audio/Source) or
-- cameras (Video/Source) at all. The switches are kept in WirePlumber's state
-- too, so they hold from the first client on, before nx809j-privacy runs.
--
-- Apps are known by application.process.binary, which the app reports
-- itself: this keeps honest apps out, it is no sandbox. Sandboxed apps keep
-- their portal rules, and WirePlumber and PipeWire's own clients are never
-- switched off.

log = Log.open_topic ("s-client")

state = State ("nx809j-privacy")
switches = state:load ()

EXEMPT = {
  ["wireplumber"] = true,
  ["pipewire"] = true,
  ["pipewire-pulse"] = true,
}

local function kind_of (node)
  local class = node.properties["media.class"] or ""
  if class:find ("^Audio/Source") then
    return "microphone"
  elseif class:find ("^Video/Source") then
    return "camera"
  end
  return nil
end

local function app_of (client)
  return client:get_property ("application.process.binary")
      or client:get_property ("application.name")
      or ""
end

local function allowed (client, kind)
  local app = app_of (client)
  if EXEMPT[app] then
    return true
  end
  if switches[kind] == "off" then
    return false
  end
  return switches[kind .. ".app." .. app] ~= "off"
end

privacy_pm = PermissionManager ()
privacy_pm:set_default_permissions (Perm.ALL)

for _, kind in ipairs ({ "microphone", "camera" }) do
  local class = kind == "microphone" and "Audio/Source*" or "Video/Source*"
  privacy_pm:add_interest_match (
    function (_, client, node)
      if allowed (client, kind) then
        return Perm.ALL
      end
      log:info (client, string.format ("%s off for '%s'", kind, app_of (client)))
      return Perm.NONE
    end,
    Interest {
      type = "node",
      Constraint { "media.class", "matches", class },
    }
  )
end

privacy_pm:activate (Features.ALL, function (_, e)
  if e then
    log:warning ("failed to activate the privacy permission manager: " .. tostring (e))
  end
end)

-- Ordinary clients get this manager instead of the one the other access
-- hooks picked (the default, all permissions): it grants the same, except
-- the sources a switch turns off. Sandboxed and restricted clients keep
-- theirs.
SimpleEventHook {
  name = "client/find-privacy-access",
  before = "client/apply-access",
  after = {
    "client/find-config-access",
    "client/find-flatpak-access",
    "client/find-snap-access",
    "client/find-portal-access",
    "client/find-default-access",
  },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-access" },
    },
  },
  execute = function (event)
    local client = event:get_subject ()
    local access = event:get_data ("effective-access")
        or client:get_property ("pipewire.access")
    if access ~= nil and access ~= "unrestricted" and access ~= "default" then
      return
    end
    if event:get_data ("default-permissions") ~= nil then
      return
    end
    event:set_data ("permission-manager", privacy_pm)
  end
}:register ()

-- The switches as a metadata object anyone in the session can write.
metadata = ImplMetadata ("privacy")
metadata:activate (Features.ALL, function (m, e)
  if e then
    log:warning ("failed to activate the privacy metadata: " .. tostring (e))
    return
  end
  for key, value in pairs (switches) do
    m:set (0, key, "Spa:String", value)
  end
  m:connect ("changed", function (_, subject, key, _, value)
    if subject ~= 0 then
      return
    end
    if key == nil then
      switches = {}
    else
      switches[key] = value
    end
    state:save_after_timeout (switches)
    privacy_pm:update_permissions ()
  end)
end)
