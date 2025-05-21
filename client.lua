-- TODO emit(Events.ERROR, ...) 처리시에 오류 로깅 개선(stacktrace 가 안이쁘게 출력되고 있음.)

local Json = require("framework.3rdparty.feature-flags.dkjson")
local Timer = require("framework.3rdparty.feature-flags.timer")
local MetricsReporter = require("framework.3rdparty.feature-flags.metrics-reporter")
local InMemoryStorageProvider = require("framework.3rdparty.feature-flags.storage-provider-inmemory")
local EventEmitter = require("framework.3rdparty.feature-flags.event-emitter")
local Util = require("framework.3rdparty.feature-flags.util")
local Logger = require("framework.3rdparty.feature-flags.logger")
local Events = require("framework.3rdparty.feature-flags.events")
local VariantProxy = require("framework.3rdparty.feature-flags.variant-proxy")
local SdkVersion = require("framework.3rdparty.feature-flags.sdk-version")

local DEFINED_FIELDS = {
  "userId",
  "sessionId",
  "remoteAddress",
  "currentTime"
}

local STATIC_CONTEXT_FIELDS = {
  "appName",
  "environment",
  "sessionId"
}

local IMPRESSION_EVENTS = {
  IS_ENABLED = "isEnabled",
  GET_VARIANT = "getVariant",
}

local DEFAULT_DISABLED_VARIANT = {
  name = "disabled",
  enabled = false,
  feature_enabled = false,
}

local TOGGLES_KEY = "toggles"
local LAST_UPDATE_KEY = "storeLastUpdateTimestamp"
local ETAG_KEY = "etag"
local SESSION_ID_KEY = "sessionId"

-- local SDK_STATES = {"initializing", "healthy", "error"}

local function createImpressionEvent(context, enabled, featureName, eventType, impressionData, variantName)
  local event = {
    eventType = eventType,
    eventId = Util.Uuid(),
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

local function isDefinedContextField(fieldName)
  for _, f in ipairs(DEFINED_FIELDS) do
    if f == fieldName then
      return true
    end
  end

  return false
end

local function convertToggleArrayToMap(togglesArray)
  local toggleMap = {}
  for _, toggle in ipairs(togglesArray) do
    toggleMap[toggle.name] = toggle
  end
  return toggleMap
end

------------------------------------------------------------------
-- Client implementation
------------------------------------------------------------------

local Client = {}
Client.__index = Client

function Client.New(config)
  if not config or type(config) ~= "table" then error("`config` is required") end

  local self = setmetatable({}, Client)

  -- setup logger
  self.loggerFactory = config.loggerFactory or Logger.DefaultLoggerFactory.New(Logger.LogLevel.Log)
  self.logger = self.loggerFactory:CreateLogger("UnleashClient")

  self.enableDevMode = config.enableDevMode or false
  if self.enableDevMode then
    self.logger:Info("Development mode enabled - detailed error information will be included.")
  end

  self.offline = config.offline or false

  -- Validate required fields
  if not config.appName then error("`appName` is required") end
  if not self.offline then
    if not config.url then error("`url` is required") end
    if not config.request then error("`request` is required") end
    if not config.clientKey then error("`clientKey` is required") end
  end

  self.sdkName = SdkVersion
  self.connectionId = Util.Uuid()

  self.realtimeToggleMap = convertToggleArrayToMap(config.bootstrap or {})
  self.useExplicitSyncMode = config.useExplicitSyncMode or false
  self.synchronizedToggleMap = Util.DeepClone(self.realtimeToggleMap)

  self.context = {
    -- static context
    appName = config.appName,
    environment = config.environment or "default",

    -- mutable context
    userId = config.context and config.context.userId,
    sessionId = config.context and config.context.sessionId,
    remoteAddress = config.context and config.context.remoteAddress,
    currentTime = config.context and config.context.currentTime,
    properties = config.context and config.context.properties,
  }

  self.url = type(config.url) == "string" and config.url or config.url
  self.clientKey = config.clientKey
  self.headerName = config.headerName or "Authorization"
  self.customHeaders = config.customHeaders or {}

  self.storage = config.storageProvider or InMemoryStorageProvider.New(self.loggerFactory)
  self.impressionDataAll = config.impressionDataAll or false
  self.refreshInterval = (config.offline and 0) or (config.disableRefresh and 0) or (config.refreshInterval or 30)
  self.request = config.request
  self.usePOSTrequests = config.usePOSTrequests or false
  self.sdkState = "initializing"
  self.experimental = Util.DeepClone(config.experimental or {})

  self.lastRefreshTimestamp = 0
  self.etag = nil
  self.readyEventEmitted = false
  self.fetchedFromServer = false
  self.started = false
  self.bootstrap = config.bootstrap
  self.bootstrapOverride = config.bootstrapOverride ~= false
  self.hasPreviousStates = false

  self.eventEmitter = EventEmitter.New({
    loggerFactory = self.loggerFactory,
    onError = function(err) self:emit(Events.ERROR, err) end,
  })

  self.timer = Timer.New(self.loggerFactory)
  self.fetchTimer = nil

  -- setup backoff
  self.backoffParams = {
    min = config.backoff and config.backoff.min or 1,        -- 1초부터 시작
    max = config.backoff and config.backoff.max or 10,       -- 10초까지 증가
    factor = config.backoff and config.backoff.factor or 2,  -- exponential backoff
    jitter = config.backoff and config.backoff.jitter or 0.2 -- 20% jitter
  }
  self.failures = 0

  if not self.offline then
    self.metricsReporter = MetricsReporter.New({
      connectionId = self.connectionId,
      appName = config.appName,
      url = self.url,
      request = self.request,
      clientKey = config.clientKey,
      headerName = self.headerName,
      customHeaders = self.customHeaders,
      disableMetrics = config.disableMetrics or false,
      metricsIntervalInitial = config.metricsIntervalInitial or 2,
      metricsInterval = config.metricsInterval or 30,
      onError = function(err) self:emit(Events.ERROR, err) end,
      onSent = function(data) self:emit(Events.SENT, data) end,
      timer = self.timer,
      loggerFactory = self.loggerFactory,
    })
  else
    self.metricsReporter = nil
  end

  -- auto start
  if config.disableAutoStart ~= true then
    self.logger:Info("Starting automatically...")

    self:Start()
  end

  return self
end

function Client:WaitUntilReady(callback)
  if self.readyEventEmitted then
    self:callWithGuard(callback)
  else
    self:Once(Events.READY, function()
      self:callWithGuard(callback)
    end)
  end
end

function Client:GetAllEnabledToggles()
  local toggleMap = self:selectToggleMap()

  local result = {}
  for _, toggle in pairs(toggleMap) do
    table.insert(result, {
      name = toggle.name,
      enabled = toggle.enabled,
      variant = toggle.variant,
      impressionData = toggle.impressionData
    })
  end
  return result
end

function Client:IsEnabled(featureName, forceSelectRealtimeToggle)
  if not featureName or type(featureName) ~= "string" or string.len(featureName) == 0 then
    self.logger:Error("`featureName` is required")
    return false
  end

  local toggleMap = self:selectToggleMap(forceSelectRealtimeToggle)

  local toggle = toggleMap[featureName]
  local enabled = (toggle and toggle.enabled) or false

  if self.metricsReporter then
    self.metricsReporter:Count(featureName, enabled)
  end

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

  return enabled
end

function Client:GetRawVariant(featureName, forceSelectRealtimeToggle)
  if not featureName or type(featureName) ~= "string" or string.len(featureName) == 0 then
    self.logger:Warn("`featureName` is required")
    return DEFAULT_DISABLED_VARIANT
  end

  local toggleMap = self:selectToggleMap(forceSelectRealtimeToggle)

  local toggle = toggleMap[featureName]
  local enabled = (toggle and toggle.enabled) or false
  local variant = (toggle and toggle.variant) or DEFAULT_DISABLED_VARIANT

  if self.metricsReporter then
    if variant.name then
      self.metricsReporter:CountVariant(featureName, variant.name)
    end

    self.metricsReporter:Count(featureName, enabled)
  end

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

  return {
    name = variant.name,
    enabled = variant.enabled,
    feature_enabled = enabled,
    payload = variant.payload
  }
end

function Client:GetVariant(featureName, forceSelectRealtimeToggle)
  local variant = self:GetRawVariant(featureName, forceSelectRealtimeToggle)
  return VariantProxy.New(self, featureName, variant)
end

-- Helper function to safely call user callbacks
function Client:callWithGuard(callback, ...)
  -- FIXME callback이 지정안된 경우는 오류로 취급해야하지 않을까?
  if not callback or type(callback) ~= "function" then
    return
  end

  local success, result = pcall(callback, ...)
  if not success then
    local errorMsg = tostring(result)

    self.logger:Error("Error in user callback: %s", errorMsg)

    self:emit(Events.ERROR, {
      type = "CallbackError",
      message = errorMsg
    })
  end
  return success, result
end

function Client:UpdateToggles(callback)
  if self.offline then
    self:callWithGuard(callback)
    return
  end

  -- FIXME
  -- self.fetchTimer ~= nil 대신 self.fetching 플래그로 체크하는게 좋을듯
  if self.fetchTimer ~= nil or self.fetchedFromServer then
    self:cancelFetchTimer()
    self:fetchToggles(callback)
    return
  end

  if self.started then
    self:Once(Events.READY, function()
      self:cancelFetchTimer()
      self:fetchToggles(function()
        self:callWithGuard(callback)
      end)
    end)
  else
    -- If not started yet, we'll fetch toggles after start anyway,
    -- so we can skip fetching toggles here.
    self:callWithGuard(callback)
  end
end

function Client:anyContextFieldHasChanged(fields)
  for key, val in pairs(fields) do
    if key == "userId" then
      if self.context.userId ~= val then
        return true
      end
    elseif key == "sessionId" then
      if self.context.sessionId ~= val then
        return true
      end
    elseif key == "remoteAddress" then
      if self.context.remoteAddress ~= val then
        return true
      end
    elseif key == "currentTime" then
      if self.context.currentTime ~= val then
        return true
      end
    else
      if self.context.properties[key] ~= val then
        return true
      end
    end
  end

  -- nothing changed
  return false
end

function Client:UpdateContext(context, callback)
  if self.offline then
    self:callWithGuard(callback)
    return
  end

  for _, field in ipairs(STATIC_CONTEXT_FIELDS) do
    if context[field] then
      self.logger:Warn("`%s` is a static field name. It can't be updated with UpdateContext.", field)
    end
  end

  local staticContext = {
    environment = self.context.environment,
    appName = self.context.appName,
    sessionId = self.context.sessionId,
  }

  -- TODO If there are no changes in the context, return
  -- context 비교 루틴을 하나 만들어서 처리하는게 좋을듯.

  self.context = Util.DeepClone(staticContext, context)

  if self.logger:IsEnabled(Logger.LogLevel.Debug) then
    self.logger:Debug("Context is updated: %s", Json.encode(self.context))
  end

  self:UpdateToggles(callback)
end

function Client:GetContext()
  return Util.DeepClone(self.context)
end

function Client:SetContextField(field, value, callback)
  if self.offline then
    self:callWithGuard(callback)
    return
  end

  local changed = false

  -- Predefined fields are stored directly in the context,
  -- while others are stored in properties.
  if isDefinedContextField(field) then
    if value ~= self.context[field] then
      self.context[field] = value
      changed = true
    end
  else
    self.context.properties = self.context.properties or {}
    if self.context.properties[field] ~= value then
      self.context.properties[field] = value
      changed = true
    end
  end

  if changed then
    self:UpdateToggles(callback)
  else
    self:callWithGuard(callback)
  end
end

function Client:RemoveContextField(field, callback)
  if self.offline then
    self:callWithGuard(callback)
    return
  end

  if isDefinedContextField(field) then
    if not self.context[field] then
      self:callWithGuard(callback)
      return
    end

    self.context[field] = nil
  elseif self.context.properties and type(self.context.properties) == "table" then
    if not self.context.properties[field] then
      self:callWithGuard(callback)
      return
    end

    table.remove(self.context.properties, field)
  end

  self:UpdateToggles(callback)
end

function Client:setReady()
  if not self.readyEventEmitted then
    self.readyEventEmitted = true
    self:emit(Events.READY)
  end
end

function Client:init(callback)
  self.logger:Debug("Initializing...")

  self:resolveSessionId(function(sessionId)
    self.context.sessionId = sessionId

    self.storage:Load(TOGGLES_KEY, function(toggles)
      self.realtimeToggleMap = convertToggleArrayToMap(toggles or {})
      if self.useExplicitSyncMode then
        self.synchronizedToggleMap = Util.DeepClone(self.realtimeToggleMap)
      end

      self.storage:Load(ETAG_KEY, function(etag)
        self.etag = etag
      end)

      self:loadLastRefreshTimestamp(function(timestamp)
        self.lastRefreshTimestamp = timestamp

        if self.bootstrap and (self.bootstrapOverride or Util.IsEmptyTable(self.realtimeToggleMap)) then
          self.storage:Store(TOGGLES_KEY, self.bootstrap, function()
            self.realtimeToggleMap = convertToggleArrayToMap(self.bootstrap)
            if self.useExplicitSyncMode then
              self.synchronizedToggleMap = Util.DeepClone(self.realtimeToggleMap)
            end

            self.sdkState = "healthy"
            self.etags = nil

            self:storeLastRefreshTimestamp(function()
              self:emit(Events.INIT)
              self:setReady()
              self:callWithGuard(callback)
            end)
          end)
        else
          self.sdkState = "healthy"
          self:emit(Events.INIT)
          self:callWithGuard(callback)
        end
      end)
    end)
  end)
end

-- TODO callback 인자로 error를 전달해주는게 좋을듯
function Client:Start(callback)
  if self.started then
    -- TODO error 이벤트를 발생시켜줘야하나?

    self.logger:Error("Client has already started, call Stop() before restarting.")
    self:callWithGuard(callback)
    return
  end

  local startInfo = {
    appName = self.context.appName,
    environment = self.context.environment,
    sdkName = self.sdkName,
    connectionId = self.connectionId,
    explicitSyncMode = self.useExplicitSyncMode,
    dataFetchMode = self.refreshInterval > 0 and "polling" or "manual",
    offline = self.offline,
    url = self.url,
  }

  if self.refreshInterval > 0 then
    startInfo.refreshInterval = string.format("%.2f sec", self.refreshInterval)
  end

  self.logger:Info("Starting client: %s", Json.encode(startInfo))

  self.started = true

  -- initialize asynchronously with a callback
  self:init(function(err)
    if err then
      self.logger:Error(tostring(err))

      self.sdkState = "error"
      self:emit(Events.ERROR, err)
      self.lastError = err
    end

    if self.offline then
      self:setReady()

      self:callWithGuard(callback)

      self.logger:Info("Client is started.")
    else
      self:initialFetchToggles(function()
        if self.metricsReporter then
          self.metricsReporter:Start()
        end

        self:callWithGuard(callback)

        self.logger:Info("Client is started.")
      end)
    end
  end)
end

function Client:handleErrorCases(url, statusCode)
  if statusCode == 401 or     -- unauthorized
      statusCode == 403 then  -- forbidden
    return self:handleConfigurationError(url, statusCode)
  elseif statusCode == 404 or -- not found
      statusCode == 429 or    -- too many request
      statusCode == 500 or    -- internal server error
      statusCode == 502 or    -- bad gate way
      statusCode == 503 or    -- service unavailable
      statusCode == 504 then  -- gateway timeout
    return self:handleRecoverableError(url, statusCode)
  else
    return self.refreshInterval
  end
end

function Client:handleConfigurationError(url, statusCode)
  self.failures = self.failures + 1

  local errorMsg = url .. " responded " .. statusCode ..
    " which means your API key is not allowed to connect. Stopping refresh of toggles"

  self.logger:Error("No more fetches will be performed. Please check that the token for API calls is correct!")

  self:emit(Events.ERROR, {
    type = "ConfigurationError",
    message = errorMsg,
    code = statusCode,
  })

  return 0 -- stop fetching
end

function Client:handleRecoverableError(url, statusCode)
  local nextFetchDelay = self:backoff()
  local errorType, errorMsg

  if statusCode == 429 then -- too many request
    errorType = "RateLimitError"
    errorMsg = url .. " responded " .. statusCode ..
      " which means you are being rate limited. Stopping refresh of toggles for " .. nextFetchDelay .. " seconds"
  elseif statusCode == 404 then -- not found
    errorType = "NotFoundError"
    errorMsg = url .. " responded " .. statusCode ..
      " which means the resource was not found. Stopping refresh of toggles for " .. nextFetchDelay .. " seconds"
  elseif statusCode == 500 or -- internal server error
      statusCode == 502 or    -- bad gate way
      statusCode == 503 or    -- service unavailable
      statusCode == 504 then  -- gateway timeout
    errorType = "ServerError"
    errorMsg = url .. " responded " .. statusCode ..
      " which means the server is having issues. Stopping refresh of toggles for " .. nextFetchDelay .. " seconds"
  end

  self.logger:Error(errorMsg)

  self:emit(Events.ERROR, {
    type = errorType,
    message = errorMsg,
    code = statusCode,
  })

  return nextFetchDelay
end

function Client:getNextFetchDelay()
  local delay = self.refreshInterval
  if self.failures > 0 then
    local extra = math.pow(2, self.failures)

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

function Client:backoff()
  self.failures = math.min(self.failures + 1, 10)
  return self:getNextFetchDelay()
end

function Client:countSuccess()
  self.failures = math.max(self.failures - 1, 0)
  return self:getNextFetchDelay()
end

function Client:timedFetch(interval)
  -- interval이 0보다 작거나 같으면, timer를 예약하지 않음.
  -- (의도된 동작임. 복구 불가능한 에러가 발생했을 경우에는 더이상 시도하지 않음. 토큰 오류 같은 경우)

  if interval > 0 then
    self.logger:Debug("Schedule a request to fetch toggles after %.2f seconds.", interval)

    self.fetchTimer = self.timer:Timeout(interval, function()
      self:fetchToggles(function(err) end)
    end)
  end
end

function Client:cancelFetchTimer()
  if self.fetchTimer then
    self.logger:Debug("Cancel fetch timer.");

    self.timer:Cancel(self.fetchTimer)
    self.fetchTimer = nil
  end
end

-- TODO apply callback
function Client:Stop(callback)
  if self.offline then
    return
  end

  if not self.started then
    self.logger:Warn("Client is not stated.")
    return
  end

  self:cancelFetchTimer()

  if self.metricsReporter then
    self.metricsReporter:Stop()
  end

  if self.timer then
    self.timer:CancelAll()
  end

  self.started = false

  self.logger:Info("Client is stopped.")
end

function Client:IsReady()
  if self.offline then
    return true
  end

  return self.readyEventEmitted
end

function Client:GetError()
  if self.offline then
    return nil
  end

  return (self.sdkState == 'error' and self.lastError) or nil
end

function Client:SendMetrics()
  if self.metricsReporter then
    self.metricsReporter:SendMetrics()
  end
end

function Client:resolveSessionId(callback)
  if self.context.sessionId then
    self:callWithGuard(callback, self.context.sessionId)
    return
  end

  self.storage:Load(SESSION_ID_KEY, function(sessionId)
    if not sessionId then
      sessionId = tostring(math.random(1, 1000000000))
      -- sessionId = Util.uuid()
      self.storage:Store(SESSION_ID_KEY, sessionId, function()
        self:callWithGuard(callback, sessionId)
      end)
    else
      self:callWithGuard(callback, sessionId)
    end
  end)
end

function Client:getHeaders()
  local headers = {
    [self.headerName] = self.clientKey,
    ["Accept"] = "application/json",
    ["Cache"] = "no-cache",
    ["unleash-appname"] = self.context.appName,
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
    if value then -- discard nil
      headers[name] = value
    end
  end

  return headers
end

function Client:storeToggles(toggles, callback)
  local newToggleArray = toggles or {}

  local oldToggleMap = self.realtimeToggleMap or {}
  local newToggleMap = convertToggleArrayToMap(newToggleArray)

  if self.logger:IsEnabled(Logger.LogLevel.Debug) then
    self.logger:Debug("Toggles updated: oldToggles=%s", Json.encode(oldToggleMap))
    self.logger:Debug("Toggles updated: newToggles=%s", Json.encode(newToggleMap))
  end

  self.realtimeToggleMap = newToggleMap

  self:emit(Events.UPDATE, newToggleArray)
  self.storage:Store(TOGGLES_KEY, newToggleArray, callback)

  -- Detects disabled flags
  for _, oldToggle in pairs(oldToggleMap) do
    local newToggle = newToggleMap[oldToggle.name]
    local toggleIsDisabled = newToggle == nil
    if toggleIsDisabled then
      self.logger:Info("Feature flag `%s` is disabled.", oldToggle.name)
      local eventName = "update:" .. oldToggle.name
      if self.eventEmitter:HasListeners(eventName) then
        self.eventEmitter:Emit(eventName, self:GetVariant(oldToggle.name, true)) -- force select realtime toggle
      end
    end
  end

  -- Detects enabled or variant changed flags
  for _, newToggle in pairs(newToggleMap) do
    local emitEvent = false

    local oldToggle = oldToggleMap[newToggle.name]
    if not oldToggle then
      self.logger:Info("Feature flag `%s` is enabled.", newToggle.name)
      emitEvent = true
    elseif Util.CalculateHash(oldToggle) ~= Util.CalculateHash(newToggle) then
      self.logger:Info("Feature flag `%s` is enabled and variants changed.", newToggle.name)
      emitEvent = true
    end

    if emitEvent then
      local eventName = "update:" .. newToggle.name
      if self.eventEmitter:HasListeners(eventName) then
        self.eventEmitter:Emit(eventName, self:GetVariant(newToggle.name, true)) -- force select realtime toggle
      end
    end
  end
end

function Client:isTogglesStorageTTLEnabled()
  return self.experimental.togglesStorageTTL and self.experimental.togglesStorageTTL > 0
end

function Client:isUpToDate()
  if not self:isTogglesStorageTTLEnabled() then
    return false
  end

  local now = os.time()
  local ttl = self.experimental.togglesStorageTTL or 0
  return self.lastRefreshTimestamp > 0 and
      self.lastRefreshTimestamp <= now and
      now - self.lastRefreshTimestamp <= ttl
end

function Client:loadLastRefreshTimestamp(callback)
  if self:isTogglesStorageTTLEnabled() then
    self.storage:Load(LAST_UPDATE_KEY, function(lastRefresh)
      local contextHash = Util.computeContextHashValue(self.context)
      local timestamp = (lastRefresh and lastRefresh.key == contextHash) and lastRefresh.timestamp or 0
      self:callWithGuard(callback, timestamp)
    end)
  else
    self:callWithGuard(callback, 0)
  end
end

function Client:storeLastRefreshTimestamp(callback)
  if self:isTogglesStorageTTLEnabled() then
    self.lastRefreshTimestamp = os.time()
    local contextHash = Util.computeContextHashValue(self.context)
    local lastUpdateValue = {
      key = contextHash,
      timestamp = self.lastRefreshTimestamp
    }
    self.storage:Store(LAST_UPDATE_KEY, lastUpdateValue, callback)
  else
    self:callWithGuard(callback)
  end
end

function Client:initialFetchToggles(callback)
  self.logger:Debug("Initial fetching toggles...")

  if self:isUpToDate() then
    if not self.fetchedFromServer then
      self.fetchedFromServer = true
      self:setReady()
    end

    self:timedFetch(self.refreshInterval)

    self:callWithGuard(callback)
  else
    self:fetchToggles(function(err)
      if not err and self.useExplicitSyncMode then
        self.synchronizedToggleMap = Util.DeepClone(self.realtimeToggleMap)
      end

      self:callWithGuard(callback, err)
    end)
  end
end

function Client:fetchToggles(callback)
  local isPOST = self.usePOSTrequests
  local url = isPOST and self.url or Util.UrlWithContextAsQuery(self.url, self.context)
  local body = isPOST and Json.encode({ context = self.context }) or nil
  local method = isPOST and "POST" or "GET"

  local headers = self:getHeaders()

  -- Note: When using the POST method, the Content-Length header must be set.
  if isPOST then
    headers["Content-Length"] = tostring(body and #body or 0)
  end

  if self.logger:IsEnabled(Logger.LogLevel.Debug) then
    self.logger:Debug("Fetch feature flags: %s", Json.encode(Util.UrlDecode(url)))
  end

  self.request(url, method, headers, body, function(response)
    if self.sdkState == "error" and (response.status >= 200 and response.status < 400) then
      self.sdkState = "healthy"
      self:emit(Events.RECOVERED)
    end

    if response.status >= 200 and response.status < 300 then
      self.etag = Util.FindCaseInsensitive(response.headers, "ETag") or nil

      local data, err = Json.decode(response.body)
      if not data then
        self.logger:Error("JSON decode failed: %s", tostring(err))

        local error = {
          type = "JsonError",
          message = tostring(err)
        }

        self.sdkState = "error"
        self:emit(Events.ERROR, error)
        self.lastError = error

        self:callWithGuard(callback, error)

        return -- stop fetching no more
      end

      self:storeToggles(data.toggles, function()
        if self.sdkState ~= "healthy" then
          self.sdkState = "healthy"
        end

        -- Mark as ready when fetched from server for the first time
        if not self.fetchedFromServer then
          self.fetchedFromServer = true
          self:setReady()
        end

        self:storeLastRefreshTimestamp(function()
          self.storage:Store(ETAG_KEY, self.etag, function()
            local nextFetchDelay = self:countSuccess()
            self:timedFetch(nextFetchDelay)

            self:callWithGuard(callback, nil)
          end)
        end)
      end)
    elseif response.status == 304 then
      self.logger:Debug("No changes in feature flags, using cached data. etag=%s", tostring(self.etag))

      -- REMARKS
      --  When ETag is cached, although we didn't actually fetch from the server,
      --  we should treat it as fetched since it's already up-to-date
      if not self.fetchedFromServer then
        self.fetchedFromServer = true
        self:setReady()
      end

      self:storeLastRefreshTimestamp(function()
        self:callWithGuard(callback, nil)

        local nextFetchDelay = self:countSuccess()
        self:timedFetch(nextFetchDelay)
      end)
    else
      if response.status <= 0 then
        self.logger:Warn("Failed to fetch flags: " .. response.status)
      else
        self.logger:Warn("Failed to fetch flags: " .. response.status .. "\n\n" .. response.body)
      end

      local error = { type = "HttpError", code = response.status }

      self.sdkState = "error"
      self:emit(Events.ERROR, error)
      self.lastError = error

      local nextFetchDelay = self:handleErrorCases(url, response.status)
      self:timedFetch(nextFetchDelay)

      self:callWithGuard(callback, error)
    end
  end)
end

function Client:emit(event, ...)
  if event == Events.ERROR and self.enableDevMode then
    local args = { ... }
    if #args > 0 then
      local errorData = args[1]

      -- Only add stack trace if it doesn't already exist
      if type(errorData) == "table" and not errorData.stackTrace then
        if debug and debug.traceback then
          errorData.stackTrace = debug.traceback("", 2)

          -- Log the error with stack trace
          if errorData.message then
            self.logger:Error("%s\nStack trace:\n%s", errorData.message, errorData.stackTrace)
          end
        end
      end

      -- Call original emit with modified error data
      return self:_emit(event, errorData, select(2, ...))
    end
  end

  -- For non-error events or when not in dev mode, call original emit
  return self:_emit(event, ...)
end

function Client:_emit(event, ...)
  if self.eventEmitter:HasListeners(event) then
    if self.logger:IsEnabled(Logger.LogLevel.Debug) then
      local argCount = select("#", ...)
      if argCount > 0 then
        local args = ...
        self.logger:Debug("`" .. event .. "` event is emitted: %s", Json.encode(args))
      else
        self.logger:Debug("`" .. event .. "` event is emitted.")
      end
    end

    self.eventEmitter:Emit(event, ...)
  end
end

function Client:On(event, callback)
  self.eventEmitter:On(event, callback)
end

function Client:Once(event, callback)
  self.eventEmitter:Once(event, callback)
end

function Client:Off(event, callback)
  self.eventEmitter:Off(event, callback)
end

function Client:selectToggleMap(forceSelectRealtimeToggle)
  if forceSelectRealtimeToggle == true then
    return self.realtimeToggleMap
  end

  if self.useExplicitSyncMode then
    return self.synchronizedToggleMap
  else
    return self.realtimeToggleMap
  end
end

function Client:SyncToggles(fetchNow, callback)
  if not self.useExplicitSyncMode then
    self:callWithGuard(callback)
    return
  end

  if fetchNow then
    self:UpdateToggles(function()
      self.synchronizedToggleMap = Util.DeepClone(self.realtimeToggleMap)
      self:callWithGuard(callback)
    end)
  else
    self.synchronizedToggleMap = Util.DeepClone(self.realtimeToggleMap)
    self:callWithGuard(callback)
  end
end

function Client:WatchToggle(featureName, callback)
  if not featureName or type(featureName) ~= "string" or string.len(featureName) == 0 then
    self.logger:Warn("`featureName` is required")
    return
  end

  if not callback or type(callback) ~= "function" then
    self.logger:Warn("`callback` is required")
    return
  end

  local eventName = "update:" .. featureName
  return self.eventEmitter:On(eventName, callback)
end

function Client:WatchToggleWithInitialState(featureName, callback)
  if not featureName or type(featureName) ~= "string" or string.len(featureName) == 0 then
    self.logger:Warn("`featureName` is required")
    return
  end

  if not callback or type(callback) ~= "function" then
    self.logger:Warn("`callback` is required")
    return
  end

  local eventName = "update:" .. featureName

  -- Note: Register event handlers first to ensure they work as intended when emitting for initial setup.
  local off = self.eventEmitter:On(eventName, callback)

  local initialAction = function()
    self.eventEmitter:Emit(eventName, self:GetVariant(featureName, true)) -- select realtime toggle
  end

  -- If READY event has already been emitted, execute immediately
  -- If READY event has not been emitted yet, execute after the READY event occurs
  if self.readyEventEmitted then
    initialAction()
  else
    self.logger:Debug("WatchToggleWithInitialState: waiting for ready event. feature=`%s`", featureName)
    self:Once(Events.READY, initialAction)
  end

  return off
end

function Client:UnwatchToggle(featureName, callback)
  local eventName = "update:" .. featureName
  self.eventEmitter:Off(eventName, callback)
end

function Client:Tick()
  if self.offline then
    return
  end

  self.timer:Tick()
end

function Client:BoolVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  local variant = self:GetVariant(featureName, forceSelectRealtimeToggle)
  return variant:BoolVariation(defaultValue)
end

function Client:NumberVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  local variant = self:GetVariant(featureName, forceSelectRealtimeToggle)
  return variant:NumberVariation(defaultValue)
end

function Client:StringVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  local variant = self:GetVariant(featureName, forceSelectRealtimeToggle)
  return variant:StringVariation(defaultValue)
end

function Client:JsonVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  local variant = self:GetVariant(featureName, forceSelectRealtimeToggle)
  return variant:JsonVariation(defaultValue)
end

return Client
