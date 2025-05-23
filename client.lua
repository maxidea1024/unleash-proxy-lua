local Json = require("framework.3rdparty.feature-flags.dkjson")
local Timer = require("framework.3rdparty.feature-flags.timer")
local MetricsReporter = require("framework.3rdparty.feature-flags.metrics-reporter")
local InMemoryStorageProvider = require("framework.3rdparty.feature-flags.storage-provider-inmemory")
local EventEmitter = require("framework.3rdparty.feature-flags.event-emitter")
local Util = require("framework.3rdparty.feature-flags.util")
local Logger = require("framework.3rdparty.feature-flags.logger")
local Events = require("framework.3rdparty.feature-flags.events")
local ErrorTypes = require("framework.3rdparty.feature-flags.error-types")
local VariantProxy = require("framework.3rdparty.feature-flags.variant-proxy")
local ErrorHelper = require("framework.3rdparty.feature-flags.error-helper")
local SdkVersion = require("framework.3rdparty.feature-flags.sdk-version")
local Validation = require("framework.3rdparty.feature-flags.validation")

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
    eventId = Util.UuidV7(),
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

-- logger 개선:
--  sinker만 외부에서 추가하는 형태로 하는게 좋을듯함.
--  현재는 Logger Factory를 외부에서 지정하는 형태임.

local Client = {}
Client.__index = Client

function Client.New(config)
  Validation.RequireTable(config, "config", "Client.New")

  local self = setmetatable({}, Client)

  -- setup logger
  self.loggerFactory = config.loggerFactory or Logger.DefaultLoggerFactory.New(Logger.LogLevel.Log)
  self.logger = self.loggerFactory:CreateLogger("UnleashClient")

  self.enableDevMode = config.enableDevMode or false
  if self.enableDevMode then
    self.logger:Info("Development mode enabled - detailed error information will be included.")
  end

  self.offline = config.offline or false
  if self.enableDevMode then
    self.logger:Info("Operating in offline mode.")
  end

  -- Validate required fields
  Validation.RequireField(config, "appName", "config", "Client.New")

  if not self.offline then
    Validation.RequireField(config, "url", "config", "Client.New")
    Validation.RequireField(config, "request", "config", "Client.New")
    Validation.RequireField(config, "clientKey", "config", "Client.New")
  end

  self.sdkName = SdkVersion
  self.connectionId = Util.UuidV7()

  self.realtimeToggleMap = convertToggleArrayToMap(config.bootstrap or {})
  self.useExplicitSyncMode = config.useExplicitSyncMode or false
  self.synchronizedToggleMap = Util.DeepClone(self.realtimeToggleMap)
  self.lastSynchronizedETag = nil

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

  -- Create EventEmitter with client reference for error handling
  self.eventEmitter = EventEmitter.New({
    loggerFactory = self.loggerFactory,
    client = self
  })

  self.timer = config.timer or Timer.New(self.loggerFactory, self)
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
      client = self,
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

  return self
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

function Client:Start(callback)
  -- CHECKME
  -- offline 모드에서도 로컬에 캐싱된 데이터를 가져오는것 까지해야한다면,
  -- 여기서 리턴하면 안됨.
  if self.offline then
    self:callWithGuard(callback)
    return
  end

  if self.started then
    self.logger:Warn("Client has already started, call Stop() before restarting.")
    -- self:callWithGuard(callback)
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

  -- Safely encode startInfo for logging
  local success, jsonStartInfo = pcall(Json.encode, startInfo)
  if success then
    self.logger:Info("Starting client: %s", jsonStartInfo)
  else
    self.logger:Info("Starting client: [JSON encoding failed: %s]", tostring(jsonStartInfo))
  end

  self.started = true

  -- initialize asynchronously with a callback
  self:init(function(err)
    if err then
      -- Use emitError for consistent error handling
      local errorData = self:emitError(
        ErrorTypes.UNKNOWN_ERROR,
        "Client initialization failed: " .. tostring(err),
        "Start",
        Logger.LogLevel.Error,
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

function Client:setReady()
  if not self.readyEventEmitted then
    self.readyEventEmitted = true
    self:emit(Events.READY)
  end
end

function Client:WaitUntilReady(callback)
  if self.offline or self.readyEventEmitted then
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
  -- 직접 유효성 검사 호출 (pcall 없이)
  Validation.RequireString(featureName, "featureName", "IsEnabled")

  local toggleMap = self:selectToggleMap(forceSelectRealtimeToggle)
  local toggle = toggleMap[featureName]

  -- Add debug log when toggle is not found
  if not toggle and self.logger:IsEnabled(Logger.LogLevel.Debug) then
    self.logger:Debug("Feature flag `%s` not found in toggle map", featureName)
  end

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
  Validation.RequireString(featureName, "featureName", "GetRawVariant")

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
  local rawVariant = self:GetRawVariant(featureName, forceSelectRealtimeToggle)
  return VariantProxy.GetOrCreate(self, featureName, rawVariant)
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

  if not context or type(context) ~= "table" then
    self:emitError(
      ErrorTypes.INVALID_ARGUMENT,
      "`context` must be a table",
      "UpdateContext",
      Logger.LogLevel.Warning,
      {
        providedType = type(context),
        prevention = "Ensure context parameter is a valid table with proper structure.",
        solution = "Pass a valid table containing context fields like userId, sessionId, etc.",
        troubleshooting = {
          "1. Verify context parameter is not nil",
          "2. Ensure context is a table, not string or other type",
          "3. Check context structure matches expected format",
          "4. Review context creation logic"
        }
      }
    )
    self:callWithGuard(callback)
    return
  end

  local staticFieldsFound = {}
  for _, field in ipairs(STATIC_CONTEXT_FIELDS) do
    if context[field] then
      table.insert(staticFieldsFound, field)
      self.logger:Warn("`%s` is a static field name. It can't be updated with UpdateContext.", field)
    end
  end

  if #staticFieldsFound > 0 then
    self:emitError(
      ErrorTypes.STATIC_FIELD_UPDATE_ATTEMPT,
      "Attempted to update static context fields",
      "UpdateContext",
      Logger.LogLevel.Warning,
      {
        staticFields = staticFieldsFound,
        prevention = "Avoid updating static context fields after client initialization.",
        solution = "Remove static fields from context update or reinitialize client with new static values.",
        troubleshooting = {
          "1. Review which fields are static: " .. table.concat(STATIC_CONTEXT_FIELDS, ", "),
          "2. Use only mutable context fields in UpdateContext",
          "3. Set static fields during client initialization",
          "4. Consider creating a new client instance if static fields need to change"
        }
      }
    )
  end

  local staticContext = {
    environment = self.context.environment,
    appName = self.context.appName,
    sessionId = self.context.sessionId,
  }

  -- TODO If there are no changes in the context, return
  -- It would be good to create a context comparison routine to handle this.

  self.context = Util.DeepClone(staticContext, context)

  if self.logger:IsEnabled(Logger.LogLevel.Debug) then
    self.logger:Debug("Context is updated: %s", Json.encode(self.context))
  end

  self:UpdateToggles(callback)
end

function Client:GetContext()
  return Util.DeepClone(self.context)
end

function Client:SetContextFields(fields, callback)
  -- TODO
end

-- context 변경까지는 해주는게 맞나?
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

function Client:handleHttpErrorCases(url, statusCode, responseBody)
  local nextFetchDelay = self:backoff()
  local errorType = ErrorTypes.UNKNOWN_ERROR
  local errorMsg = "Unknown error"
  local detail = ErrorHelper.BuildHttpErrorDetail(url, statusCode, {
    context = "feature-flags",
    nextFetchDelay = nextFetchDelay,
    failures = self.failures,
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
    errorMsg = "Resource not found: " .. url
    -- nextFetchDelay = 0 -- Don't retry on not found errors
  elseif statusCode == 429 then
    errorType = ErrorTypes.RATE_LIMIT_ERROR
    errorMsg = "Rate limit exceeded. Retrying in " .. nextFetchDelay .. " seconds."
  elseif statusCode >= 500 then
    errorType = ErrorTypes.SERVER_ERROR
    errorMsg = "Server error with status code " .. statusCode ..
        " which means the server is having issues. Stopping refresh of toggles for " .. nextFetchDelay .. " seconds"
  end

  -- Add retry information for recoverable errors
  if nextFetchDelay > 0 then
    detail.retryInfo = {
      currentFailures = self.failures,
      willRetry = true,
      nextRetryDelay = nextFetchDelay
    }
  else
    detail.retryInfo = {
      currentFailures = self.failures,
      willRetry = false,
      nextRetryDelay = 0
    }
  end

  local error = self:emitError(
    errorType,
    errorMsg,
    "handleHttpErrorCases",
    Logger.LogLevel.Error,
    detail)
  self.sdkState = "error"
  self.lastError = error

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
  if interval > 0 then
    self.logger:Debug("Next fetch toggles in %.2fs", interval)
    
    self.fetchTimer = self.timer:Timeout(interval, function()
      self:fetchToggles(function(err) end)
    end)
  end
end

function Client:cancelFetchTimer()
  if self.fetchTimer then
    self.timer:Cancel(self.fetchTimer)
    self.fetchTimer = nil
  end
end

function Client:Stop()
  if self.offline then return end

  if not self.started then
    self.logger:Warn("Client is not stated.")
    return
  end

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
  return self.offline or self.readyEventEmitted
end

function Client:GetError()
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

  if not self.useExplicitSyncMode then
    self:emit(Events.UPDATE, newToggleArray)
  end

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
  local body = nil
  local method = isPOST and "POST" or "GET"

  -- Safely encode JSON for POST requests
  if isPOST then
    local success, jsonBody = pcall(Json.encode, { context = self.context })
    if not success then
      local jsonErrorDetail = ErrorHelper.GetJsonEncodingErrorDetail(tostring(jsonBody), "context")
      local detail = {
        contextPreview = ErrorHelper.GetTableKeys(self.context),
        errorMessage = tostring(jsonBody),
        prevention = jsonErrorDetail.prevention,
        solution = jsonErrorDetail.solution,
        troubleshooting = jsonErrorDetail.troubleshooting
      }

      local error = self:emitError(
        ErrorTypes.JSON_ERROR,
        "Failed to encode request JSON: " .. tostring(jsonBody),
        "fetchToggles",
        Logger.LogLevel.Error,
        detail
      )

      self.sdkState = "error"
      self.lastError = error

      self:callWithGuard(callback, error)
      return -- stop fetching
    end
    body = jsonBody
  end

  local headers = self:getHeaders()

  -- Note: When using the POST method, the Content-Length header must be set.
  if isPOST then
    headers["Content-Length"] = tostring(body and #body or 0)
  end

  -- if self.logger:IsEnabled(Logger.LogLevel.Debug) then
  --   -- Safely encode URL for debug logging
  --   local success, jsonUrl = pcall(Json.encode, Util.UrlDecode(url))
  --   if success then
  --     self.logger:Debug("Fetch feature flags: %s", jsonUrl)
  --   else
  --     self.logger:Debug("Fetch feature flags: %s [JSON encoding failed]", tostring(url))
  --   end
  -- end

  self.request(url, method, headers, body, function(response)
    if self.sdkState == "error" and (response.status >= 200 and response.status < 400) then
      self.sdkState = "healthy"
      self:emit(Events.RECOVERED)
    end

    if response.status >= 200 and response.status < 300 then
      self.etag = Util.FindCaseInsensitive(response.headers, "ETag") or nil

      -- Use pcall to safely decode JSON and handle any exceptions
      local success, data, err = pcall(Json.decode, response.body)

      if not success then
        -- pcall failed, meaning Json.decode threw an exception
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
          Logger.LogLevel.Error,
          detail
        )

        self.sdkState = "error"
        self.lastError = error

        self:callWithGuard(callback, error)
        return -- stop fetching no more
      elseif not data then
        -- Json.decode succeeded but returned nil (with error message)
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
          Logger.LogLevel.Error,
          detail
        )

        self.sdkState = "error"
        self.lastError = error

        self:callWithGuard(callback, error)
        return -- stop fetching no more
      end

      -- Validate JSON structure
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
          Logger.LogLevel.Error,
          detail
        )

        self.sdkState = "error"
        self.lastError = error

        self:callWithGuard(callback, error)
        return -- stop fetching no more
      end

      -- Validate toggles field exists and is a table
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
          Logger.LogLevel.Error,
          detail
        )

        self.sdkState = "error"
        self.lastError = error

        self:callWithGuard(callback, error)
        return -- stop fetching no more
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
          Logger.LogLevel.Error,
          detail
        )

        self.sdkState = "error"
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
      local nextFetchDelay = self:handleHttpErrorCases(url, response.status, response.body)
      if nextFetchDelay > 0 then
        self:timedFetch(nextFetchDelay)
      end

      self:callWithGuard(callback, error)
    end
  end)
end

function Client:emit(event, ...)
  self.eventEmitter:Emit(event, ...)
end

function Client:On(event, callback)
  if self.offline then return function() end end
  return self.eventEmitter:On(event, callback)
end

function Client:Once(event, callback)
  if self.offline then return function() end end
  return self.eventEmitter:Once(event, callback)
end

function Client:Off(event, callback)
  if self.offline then return end
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
  if self.offline or not self.useExplicitSyncMode then
    self:callWithGuard(callback)
    return
  end

  if fetchNow then
    self:UpdateToggles(function()
      self:conditionalSyncToggles()
      self:callWithGuard(callback)
    end)
  else
    self:conditionalSyncToggles()
    self:callWithGuard(callback)
  end
end

function Client:conditionalSyncToggles(force)
  if force == true or self.lastSynchronizedETag ~= self.etag then
    self.lastSynchronizedETag = self.etag
    self.synchronizedToggleMap = Util.DeepClone(self.realtimeToggleMap)
    self:emit(Events.UPDATE, self.synchronizedToggleMap)
  end
end

function Client:WatchToggle(featureName, callback)
  if self.offline then
    return function() end
  end

  Validation.RequireString(featureName, "featureName", "WatchToggle")
  Validation.RequireFunction(callback, "callback", "WatchToggle")

  local eventName = "update:" .. featureName
  return self.eventEmitter:On(eventName, callback)
end

function Client:WatchToggleWithInitialState(featureName, callback)
  if self.offline then
    return function() end
  end

  Validation.RequireString(featureName, "featureName", "WatchToggleWithInitialState")
  Validation.RequireFunction(callback, "callback", "WatchToggleWithInitialState")

  local eventName = "update:" .. featureName

  -- Note: Register event handlers first to ensure they work as intended when emitting for initial setup.
  local off = self.eventEmitter:On(eventName, callback)

  local initialAction = function()
    self.eventEmitter:Emit(eventName, self:GetVariant(featureName, true)) -- force select realtime toggle
  end

  -- If READY event has already been emitted, execute immediately
  -- If READY event has not been emitted yet, execute after the READY event occurs
  if self.readyEventEmitted then
    initialAction()
  else
    self.logger:Debug("WatchToggleWithInitialState: Waiting for `ready` event. feature=`%s`", featureName)
    self:Once(Events.READY, initialAction)
  end

  return off
end

function Client:UnwatchToggle(featureName, callback)
  if self.offline then return end

  Validation.RequireString(featureName, "featureName", "UnwatchToggle")

  local eventName = "update:" .. featureName
  self.eventEmitter:Off(eventName, callback)
end

function Client:Tick()
  if self.timer then
    self.timer:Tick()
  end
end

function Client:BoolVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetVariant(featureName, forceSelectRealtimeToggle):BoolVariation(defaultValue)
end

function Client:NumberVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetVariant(featureName, forceSelectRealtimeToggle):NumberVariation(defaultValue)
end

function Client:StringVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetVariant(featureName, forceSelectRealtimeToggle):StringVariation(defaultValue)
end

function Client:JsonVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetVariant(featureName, forceSelectRealtimeToggle):JsonVariation(defaultValue)
end

-- Utility method to get any type of variation based on payload type
function Client:Variation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetVariant(featureName, forceSelectRealtimeToggle):Variation(defaultValue)
end

function Client:createError(type, message, functionName, detail)
  local errorData = {
    type = type,
    message = message,
    functionName = functionName
  }

  if detail then
    if Util.IsTable(detail) then
      errorData.detail = detail
    else
      errorData.detail = { info = tostring(detail) }
    end
  end

  if self.enableDevMode and debug and debug.traceback then
    errorData.stackTrace = debug.traceback("", 2)
  end

  return errorData
end

function Client:emitError(type, message, functionName, logLevel, detail)
  local errorData = self:createError(type, message, functionName, detail)

  -- Set default log level to Warning
  logLevel = logLevel or Logger.LogLevel.Warning

  -- Output log message (include detail if available)
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

    -- Append optional stack trace
    if errorData.stackTrace then
      logMessage = logMessage .. "\n" .. tostring(errorData.stackTrace)
    end
  end

  self.logger:Log(logLevel, logMessage)

  self:emit(Events.ERROR, errorData)

  return errorData
end

function Client:callWithGuard(callback, ...)
  if not callback then
    return
  end

  local success, result = pcall(callback, ...)
  if not success then
    local errorMsg = tostring(result)
    local detail = {
      callbackType = type(callback),
      argCount = select("#", ...),
      callLocation = debug.getinfo(2, "Sl"),
      prevention = "Ensure callback functions are properly implemented and handle all edge cases.",
      solution = "Review callback implementation and add proper error handling within the callback.",
      troubleshooting = {
        "1. Check callback function implementation for runtime errors",
        "2. Verify all parameters passed to callback are valid",
        "3. Add try-catch blocks within callback if needed",
        "4. Review callback logic for potential nil access or type errors"
      }
    }
    self:emitError(ErrorTypes.CALLBACK_ERROR, errorMsg, "callWithGuard", Logger.LogLevel.Error, detail)
  end
  return success, result
end

return Client
