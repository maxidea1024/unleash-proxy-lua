-- TODO 로깅 정리(단순화, 현재는 지나치게 복잡함)

-- FIXME
--   fetch 중 timeout이 30초로 되어 있어서, 반응이 없을 경우 30초동안 대기하는 상황이 발생한다.

-- FIXME
--   disable 된 플래그는 조회가 안되므로, impressionData로 설정해놔도
--   항상 false로 인식된다.
--   해결방법은 impressionDataAll=true로 해놓는건데, 그렇게 되면
--   Unleash dashboard에서 impressionData=false로 설정해놓은게 무의미해진다.
--   frontend sdk 에서는 무조건 impression event를 추적할수 밖에 없을듯한데?
--   아니면 전체 플래그 목록과 impressionData가 true/false인지 알아야한다.
--   Unleash frontend api에서 내려받는 형태를 바꾸는게 맞을듯하다.
--   추가적으로 이 문제점으로 인해서 boolVariation 함수에 defaultValue를 지정할수 없다.

local Json = require("framework.3rdparty.togglet.dkjson")
local Timer = require("framework.3rdparty.togglet.timer")
local MetricsReporter = require("framework.3rdparty.togglet.metrics-reporter")
local MetricsReporterNoop = require("framework.3rdparty.togglet.metrics-reporter-noop")
local InMemoryStorageProvider = require("framework.3rdparty.togglet.storage-provider-inmemory")
local EventEmitter = require("framework.3rdparty.togglet.event-emitter")
local Util = require("framework.3rdparty.togglet.util")
local Logging = require("framework.3rdparty.togglet.logging")
local Events = require("framework.3rdparty.togglet.events")
local ErrorTypes = require("framework.3rdparty.togglet.error-types")
local ToggleProxy = require("framework.3rdparty.togglet.toggle-proxy")
local ErrorHelper = require("framework.3rdparty.togglet.error-helper")
local Version = require("framework.3rdparty.togglet.version")
local Validation = require("framework.3rdparty.togglet.validation")
local Promise = require("framework.3rdparty.togglet.promise")
local WatchToggleGroup = require("framework.3rdparty.togglet.watch-toggle-group")

local STATIC_CONTEXT_FIELDS = {
  appName = true,
  environment = true,
  sessionId = true,
}

local DEFINED_CONTEXT_FIELDS = {
  userId = true,
  sessionId = true,
  remoteAddress = true,
  currentTime = true,
}

local ACCEPTABLE_CONTEXT_FIELD_TYPES = {
  ["bool"] = true,
  ["string"] = true,
  ["number"] = true,
  ["userdata"] = true, -- force tostring
  ["nil"] = true,
}

local IMPRESSION_EVENTS = {
  IS_ENABLED = "isEnabled",
  GET_VARIANT = "getVariant",
}

local DEFAULT_DISABLED_VARIANT = {
  name = "disabled",
  enabled = false,
  feature_enabled = false,
  payload = nil,
}

local TOGGLES_KEY = "toggles"
local LAST_UPDATE_KEY = "storeLastUpdateTimestamp"
local ETAG_KEY = "etag"
local SESSION_ID_KEY = "sessionId"

-- local SDK_STATES = {"initializing", "healthy", "error"}

local function createImpressionEvent(context, enabled, featureName, eventType, impressionData, variantName)
  local event = {
    eventType = eventType,
    eventId = Util.UuidV4(),
    context = context,
    enabled = enabled,
    featureName = featureName,
    impressionData = impressionData,
  }

  if variantName and variantName ~= "" then
    event.variantName = variantName
  end

  return event
end

local function convertTogglesArrayToMap(togglesArray)
  local togglesMap = {}
  for _, toggle in ipairs(togglesArray) do
    togglesMap[toggle.name] = toggle
  end
  return togglesMap
end

local function validateContextFieldValue(field, value)
  -- TODO
  local valueType = type(value)
  if valueType == "userdata" then
    return tostring(value)
  end

  return value
end

local function normalizeContext(context)
  local result = {}
  for key, val in pairs(context) do
    if val ~= nil and key ~= "properties" then
      result[key] = validateContextFieldValue(key, val)
    end
  end

  if context.properties and type(context.properties) == "table" then
    for key, val in pairs(context.properties) do
      if val ~= nil then
        result[key] = validateContextFieldValue(key, val)
      end
    end
  end

  return result
end

------------------------------------------------------------------------------
-- ToggletClient implementation
------------------------------------------------------------------------------

local M = {}
M.__index = M
M.__name = "ToggletClient"

function M.New(config)
  local self = setmetatable({}, M)

  Validation.RequireTable(config, "config", "ToggletClient.New")

  self.devMode = config.devMode or false
  self.offlineMode = config.offlineMode or false

  -- 주의: config.logFormatter는 아직 적용안됨.

  -- devMode에서는 Debug, devMode가 아니면 Info 레벨을 기본으로 한다.
  local logLevel = self.devMode and Logging.LogLevel.Debug or Logging.LogLevel.Info

  -- logLevel을 직접 지정한 경우에는 지정된것을 사용.
  if config.logLevel then
    config.logLevel = Logging.LogLevel[config.logLevel:gsub("^%l", string.upper)]
    if not config.logLevel then
      error("Invalid log level: " .. tostring(config.logLevel))
    end
    logLevel = config.logLevel
  end

  -- logSinks가 지정된 경우에는 지정된것을 사용해서 loggerFactory를 생성후 사용.
  if config.logSinks then
    self.loggerFactory = Logging.LoggerFactory.New(logLevel, config.logSinks)
  else
    self.loggerFactory = Logging.DefaultLoggerFactory.New(logLevel)
  end

  self.logger = self.loggerFactory:CreateLogger("Togglet")

  if not self.offlineMode then
    Validation.RequireField(config, "appName", "config", "ToggletClient.New")
    Validation.RequireField(config, "url", "config", "ToggletClient.New")
    Validation.RequireField(config, "clientKey", "config", "ToggletClient.New")
    Validation.RequireField(config, "request", "config", "ToggletClient.New")
  end

  self.appName = config.appName
  self.environment = config.environment or "default"
  self.sdkName = Version
  self.connectionId = Util.UuidV4()

  self.bootstrap = config.bootstrap
  self.bootstrapOverride = config.bootstrapOverride ~= false
  self.experimental = Util.Clone(config.experimental or {})
  self.lastRefreshTimestamp = 0
  self.etag = nil

  self.readyEventEmitted = self.offlineMode == true
  self.fetchedFromServer = self.offlineMode == true
  self.started = self.offlineMode == true
  self.sdkState = "initializing"

  self.realtimeTogglesMap = convertTogglesArrayToMap(config.bootstrap or {})
  self.explicitSyncMode = config.explicitSyncMode or false
  self.synchronizedTogglesMap = Util.Clone(self.realtimeTogglesMap)
  self.lastSynchronizedETag = nil

  local context = {
    -- static context fields
    appName = self.appName,
    environment = self.environment,
  }
  if config.context then
    -- defined context fields
    for field, _ in pairs(DEFINED_CONTEXT_FIELDS) do
      if config.context[field] then
        context[field] = config.context[field]
      end
    end

    -- properties
    if config.context.properties and type(config.context.properties) == "table" then
      context.properties = config.context.properties
    end
  end

  self.context = normalizeContext(context)
  self.contextVersion = 1

  self.eventEmitter = EventEmitter.New({
    loggerFactory = self.loggerFactory,
    client = self
  })
  self.fetchTimer = nil

  self.storage = config.storageProvider or InMemoryStorageProvider.New()
  self.impressionDataAll = config.impressionDataAll or false

  self.url = config.url
  self.clientKey = config.clientKey
  self.headerName = config.headerName or "Authorization"
  self.customHeaders = config.customHeaders or {}
  self.request = config.request
  self.usePOSTrequests = config.usePOSTrequests or false
  self.refreshInterval = (self.offlineMode and 0) or (config.disableRefresh and 0) or (config.refreshInterval or 15)
  self.fetchFailures = 0
  self.fetchingContext = nil
  self.fetchingContextVersion = self.contextVersion
  self.fetching = false
  self.backoffParams = {
    min = config.backoff and config.backoff.min or 1,
    max = config.backoff and config.backoff.max or 10,
    factor = config.backoff and config.backoff.factor or 2,
    jitter = config.backoff and config.backoff.jitter or 0.2
  }

  local metricsDisabled = self.offlineMode or (config.disableMetrics or false)
  if metricsDisabled then
    self.metricsReporter = MetricsReporterNoop.New()
  else
    self.metricsReporter = MetricsReporter.New({
      client = self,
      connectionId = self.connectionId,
      appName = config.appName,
      url = self.url,
      request = self.request,
      clientKey = config.clientKey,
      headerName = self.headerName,
      customHeaders = self.customHeaders,
      metricsIntervalInitial = config.metricsIntervalInitial or 2,
      metricsInterval = config.metricsInterval or 60,
      onError = function(err) self:emit(Events.ERROR, err) end,
      onSent = function(data) self:emit(Events.SENT, data) end,
      loggerFactory = self.loggerFactory,
    })
  end

  self:registerEventHandlers(config)

  if self.devMode then
    self:summarizeConfiguration()
  end

  if not config.disableAutoStart then
    self:Start()
  end

  return self
end

function M:registerEventHandlers(config)
  if config.onErrorCallbacks then
    for _, callback in ipairs(config.onErrorCallbacks) do
      self:On(Events.ERROR, callback)
    end
  end
  if config.onInitCallbacks then
    for _, callback in ipairs(config.onInitCallbacks) do
      self:On(Events.INIT, callback)
    end
  end
  if config.onReadyCallbacks then
    for _, callback in ipairs(config.onReadyCallbacks) do
      self:On(Events.READY, callback)
    end
  end
  if config.onUpdateCallbacks then
    for _, callback in ipairs(config.onUpdateCallbacks) do
      self:On(Events.UPDATE, callback)
    end
  end
  if config.onSentCallbacks then
    for _, callback in ipairs(config.onSentCallbacks) do
      self:On(Events.SENT, callback)
    end
  end

  if config.watchToggles then
    for _, watchToggle in ipairs(config.watchToggles) do
      self:WatchToggle(watchToggle.featureName, watchToggle.callback)
    end
  end
  if config.watchToggleWithInitialStates then
    for _, watchToggleWithInitialState in ipairs(config.watchToggleWithInitialStates) do
      self:WatchToggleWithInitialState(watchToggleWithInitialState.featureName,
        watchToggleWithInitialState.callback)
    end
  end

  -- -- debugging 용 핸들러 추가
  -- if self.devMode then
  --   if not self.eventEmitter:HasListeners(Events.IMPRESSION) then
  --     self:On(Events.IMPRESSION, function(event)
  --       self.logger:Debug("[DEBUG] IMPRESSION: %s", Json.encode(event))
  --     end)
  --   end
  -- end
end

function M:summarizeConfiguration()
  local summary = {
    appName = self.appName,
    environment = self.environment,
    sdkName = self.sdkName,
    connectionId = self.connectionId,
    offlineMode = self.offlineMode,
    devMode = self.devMode,
    explicitSyncMode = self.explicitSyncMode,
    dataFetchMode = self.refreshInterval > 0 and "polling" or "manual",
    url = self.url,
  }

  if self.refreshInterval > 0 then
    summary.refreshInterval = string.format("%.2f sec", self.refreshInterval)
  end

  self.logger:Info("ℹ️ Create ToggletClient instance with configuration=%s", Json.encode(summary))
end

function M:Start()
  if self.offlineMode then
    return Promise.Completed()
  end

  if self.started then
    self.logger:Warn("ToggletClient has already started, call Stop() before restarting.")
    return Promise.Completed()
  end

  self.logger:Info("🚀 Starting Togglet client...")

  self.started = true

  -- Load local cache -> Initial fetch toggles
  return self:tryLoadLocalCache()
      :Next(function()
        return self:initialFetchToggles()
            :Next(function()
              self.logger:Debug("✅ Starting metrics reporter")
              self.metricsReporter:Start()

              self.logger:Info("🌀 ToggletClient is started")
            end)
      end)
      :Catch(function(err)
        local errorData = self:emitError(
          ErrorTypes.UNKNOWN_ERROR,
          "ToggletClient initialization failed: " .. tostring(err),
          "ToggletClient:Start",
          Logging.LogLevel.Error,
          {
            originalError = err,
            prevention = "Ensure proper client configuration and network connectivity.",
            solution = "Check client configuration parameters and verify network access to the service.",
            troubleshooting = {
              "1. Verify all required configuration parameters are provided",
              "2. Check network connectivity to the service endpoint",
              "3. Ensure API key is valid and has proper permissions",
              "4. Review client initialization logs for specific error details"
            }
          }
        )

        self.sdkState = "error"
        self.lastError = errorData
      end)
end

function M:tryLoadLocalCache()
  self.logger:Debug("🔄 Try loading local cache...")

  return self:resolveSessionId()
      :Next(function(sessionId)
        self.logger:Debug("✅ Session ID resolved: %s", sessionId)

        self.context.sessionId = sessionId
        return self.storage:Load(TOGGLES_KEY)
      end)
      :Next(function(toggleArray)
        self.logger:Debug("✅ Toggles loaded: %s", toggleArray and "found" or "not found")

        self.realtimeTogglesMap = convertTogglesArrayToMap(toggleArray or {})
        self.synchronizedTogglesMap = Util.Clone(self.realtimeTogglesMap)
        return self.storage:Load(ETAG_KEY)
      end)
      :Next(function(etag)
        self.etag = etag
        return self:loadLastRefreshTimestamp()
      end)
      :Next(function(timestamp)
        self.lastRefreshTimestamp = timestamp

        local shouldOverrideBootstrap =
            self.bootstrap and
            (self.bootstrapOverride or Util.IsEmptyTable(self.realtimeTogglesMap))

        if shouldOverrideBootstrap then
          self.logger:Debug("✅ Override bootstrap data")

          return self.storage:Store(TOGGLES_KEY, self.bootstrap)
              :Next(function()
                self.realtimeTogglesMap = convertTogglesArrayToMap(self.bootstrap)
                self.synchronizedTogglesMap = Util.Clone(self.realtimeTogglesMap)

                self.sdkState = "healthy"
                self.etags = nil

                return self:storeLastRefreshTimestamp()
              end)
              :Next(function()
                self:emit(Events.INIT)

                -- Note:
                --   This can be called twice.
                --   Once during bootstrapping, and once more
                --   when the initial fetchToggles() completes.
                self:setReady()

                self.logger:Debug("✅ Loading local cache completed with bootstrap")
              end)
        else
          self.sdkState = "healthy"
          self:emit(Events.INIT)

          self.logger:Debug("✅ Loading local cache completed without bootstrap")
        end
      end)
      :Catch(function(err)
        self.logger:Error("❌ Loading local cache failed: %s", tostring(err))
        return Promise.FromError(err)
      end)
end

function M:setReady()
  self.logger:Debug("🎉 ToggletClient is ready")

  self.readyEventEmitted = true
  self:emit(Events.READY)
end

function M:WaitUntilReady()
  if self.readyEventEmitted then
    return Promise.Completed()
  end

  local promise = Promise.New()
  self:Once(Events.READY, function()
    promise:Resolve()
  end)
  return promise
end

function M:GetContext()
  return Util.Clone(self.context)
end

function M:updateContextField(field, value)
  Validation.RequireName(field, "field", "ToggletClient:updateContextField")

  if STATIC_CONTEXT_FIELDS[field] then
    self.logger:Warn("🧩 `%s` is a static field. It can't be updated with ToggletClient:updateContextField.", field)
    return false
  end

  self.logger:Debug("🧩 Update a context field: field=`%s`, value=`%s`", field, value)

  value = validateContextFieldValue(field, value)

  if DEFINED_CONTEXT_FIELDS[field] then
    if value == self.context[field] then return false end
    self.context[field] = value
  else
    if self.context.properties then
      if value == self.context.properties[field] then return false end
    else
      self.context.properties = {}
    end

    self.context.properties[field] = value
  end

  return true
end

function M:updateContextFields(fields)
  local changeds = 0
  for field, value in pairs(fields) do
    if self:updateContextField(field, value) then
      changeds = changeds + 1
    end
  end

  return changeds
end

function M:advanceContextVersion()
  self.contextVersion = self.contextVersion + 1
end

function M:SetContextFields(fields)
  if self.offlineMode then
    return Promise.Completed()
  end

  local changeds = self:updateContextFields(fields);
  if changeds > 0 then
    self:advanceContextVersion()

    if self.readyEventEmitted then
      return self:UpdateToggles()
    end
  end

  return Promise.Completed()
end

function M:SetContextField(field, value)
  if self.offlineMode then
    return Promise.Completed()
  end

  local changed = self:updateContextField(field, value)
  if changed then
    self:advanceContextVersion()

    if self.readyEventEmitted then
      return self:UpdateToggles()
    end
  end

  return Promise.Completed()
end

function M:RemoveContextField(field)
  if self.offlineMode then
    return Promise.Completed()
  end

  if DEFINED_CONTEXT_FIELDS[field] then
    if not self.context[field] then
      return Promise.Completed()
    end

    self.context[field] = nil
  elseif self.context.properties and type(self.context.properties) == "table" then
    if not self.context.properties[field] then
      return Promise.Completed()
    end

    table.remove(self.context.properties, field)
  end

  self:advanceContextVersion()

  if self.readyEventEmitted then
    return self:UpdateToggles()
  else
    return Promise.Completed()
  end
end

function M:GetAllToggles(forceSelectRealtimeToggle)
  local togglesMap = self:selectTogglesMap(forceSelectRealtimeToggle)
  local result = {}
  for _, toggle in pairs(togglesMap) do
    table.insert(result, {
      name = toggle.name,
      enabled = toggle.enabled,
      variant = toggle.variant,
      impressionData = toggle.impressionData
    })
  end
  return result
end

function M:IsEnabled(featureName, forceSelectRealtimeToggle)
  Validation.RequireName(featureName, "featureName", "ToggletClient:IsEnabled")

  local togglesMap = self:selectTogglesMap(forceSelectRealtimeToggle)
  local toggle = togglesMap[featureName]
  local enabled = toggle and toggle.enabled or false

  if not self.offlineMode then
    self.metricsReporter:Count(featureName, enabled)

    local impressionData = self.impressionDataAll or (toggle and toggle.impressionData)
    if impressionData then
      local event = createImpressionEvent(
        self.context,
        enabled,
        featureName,
        IMPRESSION_EVENTS.IS_ENABLED,
        (toggle and toggle.impressionData) or nil,
        nil -- variant name is not applicable here
      )
      self:emit(Events.IMPRESSION, event)
    end
  end

  return enabled
end

function M:GetVariant(featureName, forceSelectRealtimeToggle)
  Validation.RequireName(featureName, "featureName", "ToggletClient:GetVariant")

  local togglesMap = self:selectTogglesMap(forceSelectRealtimeToggle)
  local toggle = togglesMap[featureName]
  local enabled = toggle and toggle.enabled or false
  local variant = toggle and toggle.variant or DEFAULT_DISABLED_VARIANT

  if not self.offlineMode then
    self.metricsReporter:CountVariant(featureName, variant.name)
    self.metricsReporter:Count(featureName, enabled)

    local impressionData = self.impressionDataAll or (toggle and toggle.impressionData)
    if impressionData then
      local event = createImpressionEvent(
        self.context,
        enabled,
        featureName,
        IMPRESSION_EVENTS.GET_VARIANT,
        (toggle and toggle.impressionData) or nil,
        variant.name
      )
      self:emit(Events.IMPRESSION, event)
    end
  end

  return {
    name = variant.name,
    enabled = variant.enabled,
    feature_enabled = enabled,
    payload = variant.payload
  }
end

function M:GetToggle(featureName, forceSelectRealtimeToggle)
  local variant = self:GetVariant(featureName, forceSelectRealtimeToggle)
  return ToggleProxy.GetOrCreate(self, featureName, variant)
end

function M:BoolVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetToggle(featureName, forceSelectRealtimeToggle):BoolVariation(defaultValue)
end

function M:NumberVariation(featureName, defaultValue, min, max, forceSelectRealtimeToggle)
  return self:GetToggle(featureName, forceSelectRealtimeToggle):NumberVariation(defaultValue, min, max)
end

function M:StringVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetToggle(featureName, forceSelectRealtimeToggle):StringVariation(defaultValue)
end

function M:JsonVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetToggle(featureName, forceSelectRealtimeToggle):JsonVariation(defaultValue)
end

function M:Variation(featureName, defaultVariantName, forceSelectRealtimeToggle)
  return self:GetToggle(featureName, forceSelectRealtimeToggle):Varation(defaultVariantName)
end

function M:selectTogglesMap(forceSelectRealtimeToggle)
  if forceSelectRealtimeToggle == true then
    return self.realtimeTogglesMap
  end

  return self.explicitSyncMode and self.synchronizedTogglesMap or self.realtimeTogglesMap
end

function M:SyncToggles(fetchNow)
  if self.offlineMode or not self.explicitSyncMode then
    return Promise.Completed()
  end

  if fetchNow then
    return self:UpdateToggles()
        :Next(function()
          self:conditionalSyncTogglesMap()
        end)
  else
    self:conditionalSyncTogglesMap()
    return Promise.Completed()
  end
end

function M:conditionalSyncTogglesMap(force)
  if force == true or self.lastSynchronizedETag ~= self.etag then
    self.lastSynchronizedETag = self.etag
    self.synchronizedTogglesMap = Util.Clone(self.realtimeTogglesMap)
    self:emit(Events.UPDATE, self.synchronizedTogglesMap)
  end
end

function M:WatchToggle(featureName, callback)
  if self.offlineMode then return function() end end

  Validation.RequireName(featureName, "featureName", "ToggletClient:WatchToggle")
  Validation.RequireFunction(callback, "callback", "ToggletClient:WatchToggle")

  local toggle = self:GetToggle(featureName, true) -- realtime
  self.logger:Debug("👀 WatchToggle: feature=`%s`, enabled=%s", featureName, toggle:IsEnabled())

  local eventName = "update:" .. featureName
  self.eventEmitter:On(eventName, callback)

  return function()
    self:UnwatchToggle(featureName, callback)
  end
end

function M:WatchToggleWithInitialState(featureName, callback)
  Validation.RequireName(featureName, "featureName", "ToggletClient:WatchToggleWithInitialState")
  Validation.RequireFunction(callback, "callback", "ToggletClient:WatchToggleWithInitialState")

  -- 초기화를 위해서 바로 call해줘야함!
  if self.offlineMode then
    local toggle = self:GetToggle(featureName, true) -- realtime
    self.logger:Debug("👀 WatchToggleWithInitialState: feature=`%s`, enabled=%s", featureName, toggle:IsEnabled())
    -- 안전하게 호출할 방법이 필요하지 않을까?
    if callback and type(callback) == "function" then
      callback(toggle)
    end

    -- 오프라인에서 더이상의 처리는 의미 없다.
    return
  end

  local eventName = "update:" .. featureName
  self.eventEmitter:On(eventName, callback)

  if self.readyEventEmitted then
    local toggle = self:GetToggle(featureName, true) -- realtime
    self.logger:Debug("👀 WatchToggleWithInitialState: feature=`%s`, enabled=%s", featureName, toggle:IsEnabled())
    self.eventEmitter:Emit(eventName, toggle)
  else
    self.logger:Debug("👀 WatchToggleWithInitialState: Waiting for `ready` event. feature=`%s` enabled=???", featureName)

    self:Once(Events.READY, function()
      local toggle = self:GetToggle(featureName, true) -- realtime
      self.logger:Debug("👀 WatchToggleWithInitialState(Pended): feature=`%s`, enabled=%s", featureName,
        toggle:IsEnabled())
      self.eventEmitter:Emit(eventName, toggle)
    end)
  end

  return function()
    self:UnwatchToggle(featureName, callback)
  end
end

function M:UnwatchToggle(featureName, callback)
  if self.offlineMode then return end

  Validation.RequireName(featureName, "featureName", "ToggletClient:UnwatchToggle")
  Validation.RequireFunction(callback, "callback", "ToggletClient:UnwatchToggle")

  self.logger:Debug("👀 UnwatchToggle: feature=`%s`", featureName)

  local eventName = "update:" .. featureName
  self.eventEmitter:Off(eventName, callback)
end

--[[
local watchToggleGroup = client:CreateWatchToggleGroup()
  :WatchToggle("flag-1", function(toggle) end)
  :WatchToggle("flag-2", function(toggle) end)
  :WatchToggle("flag-3", function(toggle) end)
  :WatchToggle("flag-4", function(toggle) end)
  :WatchToggle("flag-5", function(toggle) end)

watchToggleGroup:UnwatchAll()
]]

function M:CreateWatchToggleGroup(name)
  name = name or Util.GenerateRandomName("WatchToggleGroup:")

  if not self.watchToggleGroups then
    self.watchToggleGroups = setmetatable({}, { __mode = "v" })
  end

  local group = WatchToggleGroup.New(self, name)
  table.insert(self.watchToggleGroups, group)

  self.logger:Debug("👀 CreateWatchToggleGroup: name=`%s`", name)
  return group
end

-- 개선:
-- Stop()에서 호출할 경우, 다시 Start()를 호출하기 전에,
-- 다시 WatchToggle* 을 호출해서 변화감지를 걸어줘야하는 번거로움이 있다.
function M:destroyAllWatchToggleGroups()
  if self.watchToggleGroups then
    for _, group in ipairs(self.watchToggleGroups) do
      if group then
        self.logger:Debug("👀 DestroyWatchToggleGroup: name=`%s`", group.name)

        group:UnwatchAll()
      end
    end
    self.watchToggleGroups = nil
  end
end

function M:UpdateToggles()
  if self.offlineMode then
    return Promise.Completed()
  end

  if self.fetching then
    local promise = Promise.New()
    if self.fetchingContextVersion ~= self.contextVersion then
      -- FIXME
      -- 요청을 계속 쌓아봐야 마지막만 의미가 있다.
      -- 마지막 요청만 인정하는 형태면 좋을듯하다. 개선의 여지가 있다.
      self:Once(Events.FETCH_COMPLETED, function()
        self:UpdateToggles():Next(function()
          promise:Resolve()
        end)
      end)
    else
      self:Once(Events.FETCH_COMPLETED, function()
        promise:Resolve()
      end)
    end
    return promise
  end

  if self.readyEventEmitted then
    self.logger:Debug("ℹ️ Force refetch now")

    self:cancelFetchTimer()
    return self:fetchToggles()
  else
    local promise = Promise.New()
    self:Once(Events.READY, function()
      self:cancelFetchTimer()
      self:fetchToggles():Next(function()
        promise:Resolve()
      end)
    end)
    return promise
  end
end

function M:handleHttpErrorCases(url, statusCode, responseBody)
  local nextFetchDelay = self:backoff()

  local errorType = ErrorTypes.UNKNOWN_ERROR
  local errorMsg = "Unknown error"
  local detail = ErrorHelper.BuildHttpErrorDetail(url, statusCode, {
    context = "togglet",
    nextFetchDelay = nextFetchDelay,
    failures = self.fetchFailures,
    responseBody = responseBody,
  })

  if statusCode == 401 then
    errorType = ErrorTypes.AUTHENTICATION_ERROR
    errorMsg = "Authentication required. Please check your API key."
    nextFetchDelay = 0 -- Don't retry on auth errors
  elseif statusCode == 403 then
    errorType = ErrorTypes.AUTHORIZATION_ERROR
    errorMsg = "You don't have access to this resource. Please check your API key and permissions."
    nextFetchDelay = 0 -- Don't retry on auth errors
  elseif statusCode == 404 then
    errorType = ErrorTypes.NOT_FOUND_ERROR
    errorMsg = "Not found: " .. url
    -- nextFetchDelay = 0 -- Don't retry on not found errors
  elseif statusCode == 429 then
    errorType = ErrorTypes.RATE_LIMIT_ERROR
    errorMsg = "Rate limit exceeded. Retrying in " .. nextFetchDelay .. " seconds."
  elseif statusCode >= 500 then
    errorType = ErrorTypes.SERVER_ERROR
    errorMsg = "Server error with status code " .. statusCode ..
        " which means the server is having issues. Stopping refresh of toggles for " .. nextFetchDelay .. " seconds"
  end

  -- responseBody 객체에 message가 있다면, 그걸 출력하는게 맞다.
  -- 메시지 내용이 썩 이쁘지 않은 관계로 막아두자.
  -- if responseBody then
  --   local responseJson = Json.decode(responseBody)
  --   if responseJson and responseJson.message and type(responseJson.message) == "string" then
  --     errorMsg = responseJson.message
  --   end
  -- end

  -- Add retry information for recoverable errors
  if nextFetchDelay > 0 then
    detail.retryInfo = {
      currentFailures = self.fetchFailures,
      willRetry = true,
      nextRetryDelay = nextFetchDelay
    }
  else
    detail.retryInfo = {
      currentFailures = self.fetchFailures,
      willRetry = false,
      nextRetryDelay = 0
    }
  end

  local error = self:emitError(
    errorType,
    "❌ " .. errorMsg,
    "handleHttpErrorCases",
    Logging.LogLevel.Error,
    detail)

  self.sdkState = "error"
  self.lastError = error

  return nextFetchDelay
end

function M:getNextFetchDelay()
  local delay = self.refreshInterval

  if self.fetchFailures > 0 then
    local extra = math.pow(2, self.fetchFailures)

    if self.backoffParams.jitter > 0 then
      local rand = math.random() * 2 - 1
      extra = extra + rand * self.backoffParams.jitter * extra
    end

    extra = math.min(extra, self.backoffParams.max)
    extra = math.max(extra, self.backoffParams.min)

    delay = delay + extra
  end

  return delay
end

function M:backoff()
  self.fetchFailures = math.min(self.fetchFailures + 1, 10)
  return self:getNextFetchDelay()
end

function M:countSuccess()
  self.fetchFailures = math.max(self.fetchFailures - 1, 0)
  return self:getNextFetchDelay()
end

function M:scheduleNextFetch(delay, retry)
  if delay > 0 then
    self:cancelFetchTimer()

    if retry == true then
      self.logger:Debug("🗓️ Next fetch toggles in %.2fs for Retry", delay)
    else
      self.logger:Debug("🗓️ Next fetch toggles in %.2fs", delay)
    end

    self.fetchTimer = Timer.SetTimeout(delay, function()
      self:fetchToggles(retry)
    end)
  else
    -- 더 이상의 동작을 하지 않음.
  end
end

function M:cancelFetchTimer()
  if self.fetchTimer then
    Timer.Cancel(self.fetchTimer)
    self.fetchTimer = nil
  end
end

function M:Stop()
  local promise = Promise.New()

  if self.offlineMode then
    return promise:Resolve()
  end

  if not self.started then
    self.logger:Warn("⚠️ ToggletClient is not started.")
    return promise:Resolve()
  end

  self.metricsReporter:Stop()
  self:cancelFetchTimer()
  self:destroyAllWatchToggleGroups()
  self.started = false

  self.logger:Info("⏹️ ToggletClient is stopped.")

  return promise:Resolve()
end

function M:IsReady()
  return self.readyEventEmitted
end

function M:GetError()
  return self.sdkState == 'error' and self.lastError or nil
end

function M:SendMetrics()
  return self.metricsReporter:SendMetrics()
end

function M:resolveSessionId()
  if self.context.sessionId then
    return Promise.FromResult(self.context.sessionId)
  end

  return self.storage:Load(SESSION_ID_KEY)
    :Next(function(sessionId)
      if sessionId then
        return Promise.FromResult(sessionId)
      end

      sessionId = tostring(math.random(1, 1000000000))
      return self.storage:Store(SESSION_ID_KEY, sessionId)
    end)
end

function M:getHeaders()
  local headers = {
    [self.headerName] = self.clientKey,
    ["Accept"] = "application/json",
    ["Cache"] = "no-cache",
    ["unleash-appname"] = self.appName,
    ["unleash-connection-id"] = self.connectionId,
    ["unleash-sdk"] = self.sdkName,
  }

  if self.usePOSTrequests then
    headers["Content-Type"] = "application/json"
  end

  if self.etag and #self.etag > 0 then
    headers["If-None-Match"] = self.etag
  end

  for name, value in pairs(self.customHeaders) do
    if value then
      headers[name] = value
    end
  end

  return headers
end

function M:storeToggles(toggleArray)
  local newTogglesArray = toggleArray or {}

  local oldTogglesMap = self.realtimeTogglesMap
  local newTogglesMap = convertTogglesArrayToMap(newTogglesArray)

  if self.logger:IsEnabled(Logging.LogLevel.Debug) then
    self.logger:Debug("✨ Toggles updated: oldToggles=%s", Json.encode(oldTogglesMap))
    self.logger:Debug("✨ Toggles updated: newToggles=%s", Json.encode(newTogglesMap))
  end

  self.realtimeTogglesMap = newTogglesMap

  if not self.explicitSyncMode then
    self:emit(Events.UPDATE, newTogglesArray)
  end

  -- Detects disabled flags
  for _, oldToggle in pairs(oldTogglesMap) do
    local newToggle = newTogglesMap[oldToggle.name]
    local toggleIsDisabled = newToggle == nil or oldToggle.enabled and not newToggle.enabled
    if toggleIsDisabled then
      self.logger:Debug("✨ Toggle `%s` is disabled.", oldToggle.name)

      local eventName = "update:" .. oldToggle.name
      if self.eventEmitter:HasListeners(eventName) then
        self.eventEmitter:Emit(eventName, self:GetToggle(oldToggle.name, true)) -- realtime
      end
    end
  end

  -- Detects enabled or variant changed flags
  for _, newToggle in pairs(newTogglesMap) do
    local emitEvent = false

    local oldToggle = oldTogglesMap[newToggle.name]
    if not oldToggle then
      self.logger:Debug("✨ Toggle `%s` is enabled.", newToggle.name)
      emitEvent = true
    elseif not oldToggle.enabled and newToggle.enabled then
      self.logger:Debug("✨ Toggle `%s` is enabled.", newToggle.name)
      emitEvent = true
    elseif Util.CalculateHash(oldToggle) ~= Util.CalculateHash(newToggle) then -- hash 비교를 제거하자.
      self.logger:Debug("✨ Toggle `%s` is enabled and variants changed.", newToggle.name)
      emitEvent = true
    end

    if emitEvent then
      local eventName = "update:" .. newToggle.name
      if self.eventEmitter:HasListeners(eventName) then
        self.eventEmitter:Emit(eventName, self:GetToggle(newToggle.name, true)) -- realtime
      end
    end
  end

  return self.storage:Store(TOGGLES_KEY, newTogglesArray)
end

function M:isTogglesStorageTTLEnabled()
  return self.experimental.togglesStorageTTL and self.experimental.togglesStorageTTL > 0
end

function M:isUpToDate()
  if not self:isTogglesStorageTTLEnabled() then
    return false
  end

  local now = os.time()
  local ttl = self.experimental.togglesStorageTTL or 0
  return self.lastRefreshTimestamp > 0 and
      self.lastRefreshTimestamp <= now and
      now - self.lastRefreshTimestamp <= ttl
end

function M:loadLastRefreshTimestamp()
  if not self:isTogglesStorageTTLEnabled() then
    return Promise.FromResult(0)
  end

  return self.storage:Load(LAST_UPDATE_KEY)
    :Next(function(lastRefresh)
      local contextHash = Util.computeContextHashValue(self.context)
      local timestamp = (lastRefresh and lastRefresh.key == contextHash) and lastRefresh.timestamp or 0
      return Promise.FromResult(timestamp)
    end)
end

function M:storeLastRefreshTimestamp()
  if not self:isTogglesStorageTTLEnabled() then
    return Promise.Completed()
  end

  self.lastRefreshTimestamp = os.time()
  local contextHash = Util.computeContextHashValue(self.context)
  local lastUpdateValue = {
    key = contextHash,
    timestamp = self.lastRefreshTimestamp
  }
  return self.storage:Store(LAST_UPDATE_KEY, lastUpdateValue)
end

function M:initialFetchToggles()
  self.logger:Debug("🔄 Initial fetch toggles")

  if self:isUpToDate() then
    if not self.fetchedFromServer then
      self.fetchedFromServer = true
      self:setReady()
    end

    self:scheduleNextFetch(self.refreshInterval, false)

    return Promise.Completed()
  end

  return self:fetchToggles()
    :Next(function()
      self.synchronizedTogglesMap = Util.Clone(self.realtimeTogglesMap)
    end)
end

-- TODO 기존 요청을 취소할수 있는기능이 필요하다.
function M:fetchToggles(retry)
  self.fetching = true

  if not retry then
    self.fetchingContextVersion = self.contextVersion
    self.fetchingContext = Util.Clone(self.context)
  end

  local isPOST = self.usePOSTrequests
  local url = isPOST and self.url or Util.UrlWithContextAsQuery(self.url, self.fetchingContext)
  local method = isPOST and "POST" or "GET"
  local headers = self:getHeaders()

  if self.logger:IsEnabled(Logging.LogLevel.Debug) then
    self.logger:Debug("🔄 Fetching feature flags%s: contextVersion=%s, url=\"%s\"",
      retry and " for Retry" or "", self.fetchingContextVersion, url)
  end

  -- Safely encode JSON for POST requests
  local body = nil
  if isPOST then
    body = Json.encode({ context = self.fetchingContext })
    -- Note: When using the POST method, the Content-Length header must be set.
    headers["Content-Length"] = tostring(body and #body or 0)
  end

  -- TODO request cancel 기능을 추가해야함
  local promise = Promise.New()
  self.request(url, method, headers, body, function(response)
    self:handleFetchResponse(url, method, headers, body, response, promise)
  end)
  return promise
end

-- fetching remains true during retry attempts
function M:handleFetchResponse(url, method, headers, body, response, promise)
  if response.status >= 200 and response.status <= 299 or response.status == 304 then
    self.fetching = false

    self:emit(Events.FETCH_COMPLETED)

    if self.sdkState == "error" then
      self.sdkState = "healthy"
      self:emit(Events.RECOVERED)
    end
  end

  if response.status >= 200 and response.status <= 299 then
    self.etag = Util.FindCaseInsensitive(response.headers, "ETag") or nil

    local data, error = self:parseAndValidateResponse(url, method, response)
    if error then
      promise:Reject(error)
      return
    end

    self:processSuccessfulResponse(data, promise)
  elseif response.status == 304 then
    self.logger:Debug("🟰 No changes, using cached data")

    if not self.fetchedFromServer then
      self.fetchedFromServer = true
      self:setReady()
    end

    self:storeLastRefreshTimestamp():Next(function()
      promise:Resolve()

      local nextFetchDelay = self:countSuccess()
      self:scheduleNextFetch(nextFetchDelay, false)
    end)
  else
    local nextFetchDelay = self:handleHttpErrorCases(url, response.status, response.body)
    if nextFetchDelay > 0 then
      self:scheduleNextFetch(nextFetchDelay, true) -- retry
    else
      self.fetching = false
      promise:Reject(error)
    end
  end
end

function M:parseAndValidateResponse(url, method, response)
  local success, data, err = pcall(Json.decode, response.body)
  if not success then
    local jsonErrorDetail = ErrorHelper.GetJsonDecodingErrorDetail("exception")
    local detail = {
      responseBodyPreview = string.sub(response.body or "", 1, 256),
      responseStatus = response.status,
      url = url,
      method = method,
      errorMessage = tostring(data), -- data contains the error message when pcall fails
      prevention = jsonErrorDetail.prevention,
      solution = jsonErrorDetail.solution,
      troubleshooting = jsonErrorDetail.troubleshooting
    }

    local error = self:emitError(
      ErrorTypes.JSON_ERROR,
      "JSON decode exception: " .. tostring(data),
      "fetchToggles",
      Logging.LogLevel.Error,
      detail
    )

    self.sdkState = "error"
    self.lastError = error
    return nil, error
  elseif not data then
    local jsonErrorDetail = ErrorHelper.GetJsonDecodingErrorDetail("nil_result")
    local detail = {
      responseBodyPreview = string.sub(response.body or "", 1, 256),
      responseStatus = response.status,
      url = url,
      method = method,
      errorMessage = tostring(err),
      prevention = jsonErrorDetail.prevention,
      solution = jsonErrorDetail.solution,
      troubleshooting = jsonErrorDetail.troubleshooting
    }

    local error = self:emitError(
      ErrorTypes.JSON_ERROR,
      "JSON decode failed: " .. tostring(err),
      "fetchToggles",
      Logging.LogLevel.Error,
      detail
    )

    self.sdkState = "error"
    self.lastError = error
    return nil, error
  end

  if type(data) ~= "table" then
    local detail = {
      responseBodyPreview = string.sub(response.body or "", 1, 256),
      responseStatus = response.status,
      url = url,
      method = method,
      dataType = type(data),
      prevention = "Ensure server returns JSON object with proper structure.",
      solution = "Verify API endpoint returns a JSON object containing toggles array.",
      troubleshooting = {
        "1. Check if server returns JSON object (not array or primitive)",
        "2. Verify API endpoint implementation",
        "3. Check for API version compatibility",
        "4. Ensure proper Content-Type header is set",
        "5. Test API endpoint manually to verify response structure"
      }
    }

    local error = self:emitError(
      ErrorTypes.JSON_ERROR,
      "Invalid JSON structure: expected object but got " .. type(data),
      "fetchToggles",
      Logging.LogLevel.Error,
      detail
    )

    self.sdkState = "error"
    self.lastError = error
    return nil, error
  end

  if data.toggles == nil then
    local detail = {
      responseBodyPreview = string.sub(response.body or "", 1, 256),
      responseStatus = response.status,
      url = url,
      method = method,
      availableFields = ErrorHelper.GetTableKeys(data),
      prevention = "Ensure server returns JSON object with 'toggles' field.",
      solution = "Verify API endpoint returns proper response structure with toggles array.",
      troubleshooting = {
        "1. Check if 'toggles' field exists in response",
        "2. Verify API endpoint implementation",
        "3. Check for API version compatibility",
        "4. Ensure proper response schema is used",
        "5. Test API endpoint manually to verify response structure"
      }
    }

    local error = self:emitError(
      ErrorTypes.JSON_ERROR,
      "Missing 'toggles' field in response",
      "fetchToggles",
      Logging.LogLevel.Error,
      detail
    )

    self.sdkState = "error"
    self.lastError = error
    return nil, error
  end

  if type(data.toggles) ~= "table" then
    local detail = {
      responseBodyPreview = string.sub(response.body or "", 1, 256),
      responseStatus = response.status,
      url = url,
      method = method,
      togglesType = type(data.toggles),
      prevention = "Ensure server returns 'toggles' field as an array.",
      solution = "Verify API endpoint returns toggles as an array of toggle objects.",
      troubleshooting = {
        "1. Check if 'toggles' field is an array/table",
        "2. Verify API endpoint implementation",
        "3. Check for API version compatibility",
        "4. Ensure proper response schema is used",
        "5. Test API endpoint manually to verify toggles structure"
      }
    }

    local error = self:emitError(
      ErrorTypes.JSON_ERROR,
      "Invalid 'toggles' field type: expected table but got " .. type(data.toggles),
      "fetchToggles",
      Logging.LogLevel.Error,
      detail
    )

    self.sdkState = "error"
    self.lastError = error
    return nil, error
  end

  return data, nil
end

function M:processSuccessfulResponse(data, promise)
  return self:storeToggles(data.toggles)
      :Next(function()
        if self.sdkState ~= "healthy" then
          self.sdkState = "healthy"
        end

        if not self.fetchedFromServer then
          self.fetchedFromServer = true
          self:setReady()
        end

        return self:storeLastRefreshTimestamp()
      end)
      :Next(function()
        return self.storage:Store(ETAG_KEY, self.etag)
      end)
      :Next(function()
        promise:Resolve()

        -- 이건 호출자쪽으로 빼주는게 좋지 않을까?
        local nextFetchDelay = self:countSuccess()
        self:scheduleNextFetch(nextFetchDelay, false)
      end)
      :Catch(function(err)
        promise:Reject(err)
      end)
end

function M:emit(event, ...)
  self.eventEmitter:Emit(event, ...)
end

function M:On(event, callback)
  if self.offlineMode then return function() end end

  return self.eventEmitter:On(event, callback)
end

function M:Once(event, callback)
  if self.offlineMode then return function() end end

  return self.eventEmitter:Once(event, callback)
end

function M:Off(event, callback)
  if self.offlineMode then return end

  self.eventEmitter:Off(event, callback)
end

function M:createError(type, message, functionName, detail)
  local errorData = {
    type = type,
    message = message,
    functionName = functionName
  }

  if detail then
    errorData.detail = Util.IsTable(detail) and detail or { info = tostring(detail) }
  end

  if self.devMode and debug and debug.traceback then
    errorData.stackTrace = debug.traceback("", 2)
  end

  return errorData
end

function M:emitError(type, message, functionName, logLevel, detail)
  local errorData = self:createError(type, message, functionName, detail)

  -- set default log level to warning
  logLevel = logLevel or Logging.LogLevel.Warning

  -- output log message (include detail if available)
  local logMessage = message
  if detail and self.logger:IsEnabled(logLevel) then
    if Util.IsTable(detail) then
      local success, jsonDetail = pcall(Json.encode, detail)
      if success then
        logMessage = logMessage .. "\n\nDetail: " .. jsonDetail
      else
        logMessage = logMessage .. "\n\nDetail: [JSON encoding failed: " .. tostring(jsonDetail) .. "]"
      end
    else
      logMessage = logMessage .. "\n\nDetail: " .. tostring(detail)
    end

    -- append optional stack trace
    if errorData.stackTrace then
      logMessage = logMessage .. "\n" .. tostring(errorData.stackTrace)
    end

    self.logger:Log(logLevel, logMessage)
  end

  self:emit(Events.ERROR, errorData)

  return errorData
end

return M
