local Promise = require("framework.3rdparty.togglet.promise")
local EventEmitter = require("framework.3rdparty.togglet.event-emitter")
local Events = require("framework.3rdparty.togglet.events")

local Repository = {}
Repository.__index = Repository

function Repository.New(config)
  local self = setmetatable({}, Repository)

  -- TODO
  -- url
  -- appName
  -- instanceId
  -- projectName (NOT used)
  -- refreshInterval
  -- timeout
  -- headers
  -- customHeadersFunction
  -- httpOptions
  -- namePrefix (NOT used)
  -- tags (NOT used)
  -- bootstrapProvider
  -- bootstrapOverride
  -- storageProvider

  self.toggles = {}
  self.eventEmitter = EventEmitter.New({
    loggerFactory = config.loggerFactory,
    client = self
  })


  return self
end

function Repository:GetToggle(name)
  return self.toggles[name]
end

function Repository:GetToggles()
  local result = {}
  for _, toggle in pairs(self.toggles) do
    table.insert(result, toggle)
  end
  return result
end

function Repository:Start()
  return Promise.Completed()
end

function Repository:Stop()
  return Promise.Completed()
end

function Repository:loadBootstrap()
  return self.bootstrapProvider:ReadBootstrap():Next(function(bootstrap)
    if not self.bootstrapOverride and self.ready then
      -- early exit if we already have backup data and should not override it.
    end

    if bootstrap and #bootstrap > 0 then
      return self:save(bootstrap, false)
    end
  end):Catch(function(err)
    self:emit(Events.ERROR, err)
  end)
end

function Repository:save(toggles, fromApi)
  if self.stopped then
    return Promise.Completed()
  end

  if fromApi then
    self.connected = true
    self.togglesMap = self:convertToMap(toggles)
  elseif !self.conntected then
    -- only allow bootstrap if not connected
    self.togglesMap = self:convertToMap(toggles)
  end

  self:setReady()
  self:emit(Events.Changed, toggles)

  return self.storageProvider:store(self.appName, toggles)
end

return Repository
