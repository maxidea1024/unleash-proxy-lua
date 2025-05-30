-- TODO 로깅 정리(단순화, 현재는 지나치게 복잡함)
-- TODO fetchToggles() 시에 재시도 처리 정리(재시도 상황은 하나의 fetch가 여전히 진행중으로 봐야함)
-- TODO 용어정리. featur, flag, toggle ?  어떤게 자연스러운걸까? featureName으로 찾는게 맞다면, getToggle이 아니라 getFeature가 맞지 않을까?

local Json = require("framework.3rdparty.togglet.dkjson")
local Timer = require("framework.3rdparty.togglet.timer")
local MetricsReporter = require("framework.3rdparty.togglet.metrics-reporter")
local InMemoryStorageProvider = require("framework.3rdparty.togglet.storage-provider-inmemory")
local EventEmitter = require("framework.3rdparty.togglet.event-emitter")
local Util = require("framework.3rdparty.togglet.util")
local Logging = require("framework.3rdparty.togglet.logging")
local Events = require("framework.3rdparty.togglet.events")
local ErrorTypes = require("framework.3rdparty.togglet.error-types")
local ToggleProxy = require("framework.3rdparty.togglet.toggle-proxy")
local ErrorHelper = require("framework.3rdparty.togglet.error-helper")
local SdkVersion = require("framework.3rdparty.togglet.sdk-version")
local Validation = require("framework.3rdparty.togglet.validation")
local Promise = require("framework.3rdparty.togglet.promise")

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

------------------------------------------------------------------
-- ToggletClient implementation
------------------------------------------------------------------

local ToggletClient = {}
ToggletClient.__index = ToggletClient

function ToggletClient.New(config)
  Validation.RequireTable(config, "config", "ToggletClient.New")

  local self = setmetatable({}, ToggletClient)

  self.loggerFactory = config.loggerFactory or Logging.DefaultLoggerFactory.New(Logging.LogLevel.Log)
  self.logger = self.loggerFactory:CreateLogger("Togglet")
  self.devMode = config.enableDevMode or false
  self.offline = config.offline or false

  Validation.RequireField(config, "appName", "config", "ToggletClient.New")

  if not self.offline then
    Validation.RequireField(config, "url", "config", "ToggletClient.New")
    Validation.RequireField(config, "request", "config", "ToggletClient.New")
    Validation.RequireField(config, "clientKey", "config", "ToggletClient.New")
  end

  self.appName = config.appName
  self.sdkName = SdkVersion
  self.connectionId = Util.UuidV4()
  self.bootstrap = config.bootstrap
  self.bootstrapOverride = config.bootstrapOverride ~= false
  self.experimental = Util.DeepClone(config.experimental or {})
  self.lastRefreshTimestamp = 0
  self.etag = nil
  self.readyEventEmitted = false
  self.fetchedFromServer = false
  self.started = false
  self.sdkState = "initializing"

  self.realtimeTogglesMap = convertTogglesArrayToMap(config.bootstrap or {})
  self.useExplicitSyncMode = config.useExplicitSyncMode or false
  self.synchronizedTogglesMap = Util.DeepClone(self.realtimeTogglesMap)
  self.lastSynchronizedETag = nil

  self.context = {
    userId = config.context and config.context.userId,
    sessionId = config.context and config.context.sessionId,
    remoteAddress = config.context and config.context.remoteAddress,
    currentTime = config.context and config.context.currentTime,
    properties = config.context and config.context.properties,
  }

  self.eventEmitter = EventEmitter.New({
    loggerFactory = self.loggerFactory,
    client = self
  })
  self.timer = Timer.New(self.loggerFactory, self)
  self.fetchTimer = nil

  self.storage = config.storageProvider or InMemoryStorageProvider.New(self.loggerFactory)
  self.impressionDataAll = config.impressionDataAll or false

  if self.offline then
    self.metricsReporter = nil
    self.refreshInterval = 0
  else
    self.url = type(config.url) == "string" and config.url or config.url
    self.clientKey = config.clientKey
    self.headerName = config.headerName or "Authorization"
    self.customHeaders = config.customHeaders or {}
    self.request = config.request
    self.usePOSTrequests = config.usePOSTrequests or false
    self.refreshInterval = (config.disableRefresh and 0) or (config.refreshInterval or 15)

    self.backoffParams = {
      min = config.backoff and config.backoff.min or 1,
      max = config.backoff and config.backoff.max or 10,
      factor = config.backoff and config.backoff.factor or 2,
      jitter = config.backoff and config.backoff.jitter or 0.2
    }
    self.fetchFailures = 0
    self.fetchingContextHash = nil
    self.fetching = false

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
      metricsInterval = config.metricsInterval or 60,
      onError = function(err) self:emit(Events.ERROR, err) end,
      onSent = function(data) self:emit(Events.SENT, data) end,
      timer = self.timer,
      loggerFactory = self.loggerFactory,
    })
  end

  self:registerEventHandlers(config)

  self:summayConfiguration()

  if not config.disableAutoStart then
    self:Start()
  end

  return self
end

function ToggletClient:registerEventHandlers(config)
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
end

function ToggletClient:summayConfiguration()
  if self.devMode then
    local summary = {
      appName = self.appName,
      environment = self.environment,
      sdkName = self.sdkName,
      connectionId = self.connectionId,
      offline = self.offline,
      devMode = self.devMode,
      explicitSyncMode = self.useExplicitSyncMode,
      dataFetchMode = self.refreshInterval > 0 and "polling" or "manual",
      url = self.url,
    }

    if self.refreshInterval > 0 then
      summary.refreshInterval = string.format("%.2f sec", self.refreshInterval)
    end

    self.logger:Info("ℹ️ Create ToggletClient instance with configuration=%s", Json.encode(summary))
  else
    self.logger:Info("ℹ️ Create ToggletClient instance")
  end
end

function ToggletClient:Start()
  if self.offline then
    return Promise.Completed()
  end

  if self.started then
    self.logger:Warn("ToggletClient has already started, call Stop() before restarting.")
    return Promise.Completed()
  end

  self.logger:Info("🚀 Starting Togglet client...")

  self.started = true

  return self:init()
      :Next(function()
        return self:initialFetchToggles()
            :Next(function()
              if self.metricsReporter then
                self.logger:Debug("✅ Starting metrics reporter")
                self.metricsReporter:Start()
              end

              self.logger:Info("🌀 ToggletClient started")
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

function ToggletClient:init()
  self.logger:Debug("🔄 Initializing ToggletClient...")

  return self:resolveSessionId()
      :Next(function(sessionId)
        self.logger:Debug("✅ Session ID resolved: %s", sessionId)

        self.context.sessionId = sessionId
        return self.storage:Load(TOGGLES_KEY)
      end)
      :Next(function(toggleArray)
        self.logger:Debug("✅ Toggles loaded: %s", toggleArray and "found" or "not found")

        self.realtimeTogglesMap = convertTogglesArrayToMap(toggleArray or {})
        self.synchronizedTogglesMap = Util.DeepClone(self.realtimeTogglesMap)
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
                self.synchronizedTogglesMap = Util.DeepClone(self.realtimeTogglesMap)

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

                self.logger:Debug("✅ Init process completed with bootstrap")
              end)
        else
          self.sdkState = "healthy"
          self:emit(Events.INIT)

          self.logger:Debug("✅ Init process completed without bootstrap")
        end
      end)
      :Catch(function(err)
        self.logger:Error("❌ Init process failed: %s", tostring(err))
        return Promise.FromError(err)
      end)
end

function ToggletClient:setReady()
  self.readyEventEmitted = true
  self:emit(Events.READY)
end

function ToggletClient:WaitUntilReady()
  if self.offline or self.readyEventEmitted then
    return Promise.Completed()
  end

  local promise = Promise.New()
  self:Once(Events.READY, function()
    promise:Resolve()
  end)
  return promise
end

function ToggletClient:GetAllToggles(forceSelectRealtimeToggle)
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

function ToggletClient:IsEnabled(featureName, forceSelectRealtimeToggle)
  Validation.RequireName(featureName, "featureName", "ToggletClient:IsEnabled")

  local togglesMap = self:selectTogglesMap(forceSelectRealtimeToggle)
  local toggle = togglesMap[featureName]

  -- FIXME
  -- 활성화된 플래그들만 받아와서 가지고 있기 때문에, 플래그가 없다고해서 defaultValue를
  -- 반환하게되면, false 부정에 불과해진다.
  -- 이를 확실하게 처리하려면,
  local enabled = (toggle and toggle.enabled) or false

  if not self.offline then
    if self.metricsReporter then
      self.metricsReporter:Count(featureName, enabled)
    end

    local impressionData = self.impressionDataAll or (toggle and toggle.impressionData)
    if impressionData then
      local event = createImpressionEvent(
        self:contextWithAppName(),
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

function ToggletClient:GetVariant(featureName, forceSelectRealtimeToggle)
  Validation.RequireName(featureName, "featureName", "ToggletClient:GetVariant")

  local togglesMap = self:selectTogglesMap(forceSelectRealtimeToggle)

  local toggle = togglesMap[featureName]
  local enabled = (toggle and toggle.enabled) or false
  local variant = (toggle and toggle.variant) or DEFAULT_DISABLED_VARIANT

  if not self.offline then
    if self.metricsReporter then
      self.metricsReporter:CountVariant(featureName, variant.name)
      self.metricsReporter:Count(featureName, enabled)
    end

    local impressionData = self.impressionDataAll or (toggle and toggle.impressionData)
    if impressionData then
      local event = createImpressionEvent(
        self:contextWithAppName(),
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

function ToggletClient:GetToggle(featureName, forceSelectRealtimeToggle)
  local variant = self:GetVariant(featureName, forceSelectRealtimeToggle)
  return ToggleProxy.GetOrCreate(self, featureName, variant)
end

-- FIXME
-- 서버에서 enabled된 플래그들만 가져오기 때문에, 찾지 못한 플래그일 경우
-- defaultValue를 반환하는 기능을 적용할수 없다.
-- 활성화된 플래그뿐만 아니라 비활성화된 플래그도 가져온다면 해결이 가능할것 같은데??
function ToggletClient:BoolVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetToggle(featureName, forceSelectRealtimeToggle):BoolVariation(defaultValue)
end

function ToggletClient:NumberVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetToggle(featureName, forceSelectRealtimeToggle):NumberVariation(defaultValue)
end

function ToggletClient:StringVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetToggle(featureName, forceSelectRealtimeToggle):StringVariation(defaultValue)
end

function ToggletClient:JsonVariation(featureName, defaultValue, forceSelectRealtimeToggle)
  return self:GetToggle(featureName, forceSelectRealtimeToggle):JsonVariation(defaultValue)
end

-- Detail은 이런 형태면 되지 않나?
-- return {
--   value = ...
--   reason = ...
-- }

-- function ToggletVersion:BoolVariationDetail(featureName, defaultValue, forceSelectRealtimeToggle)
--   return self:GetToggle(featureName, forceSelectRealtimeToggle):BoolVariationDetail(defaultValue)
-- end
--
-- function ToggletVersion:NumberVariationDetail(featureName, defaultValue, forceSelectRealtimeToggle)
--   return self:GetToggle(featureName, forceSelectRealtimeToggle):NumberVariationDetail(defaultValue)
-- end
--
-- function ToggletVersion:StringVariationDetail(featureName, defaultValue, forceSelectRealtimeToggle)
--   return self:GetToggle(featureName, forceSelectRealtimeToggle):StringVariationDetail(defaultValue)
-- end
--
-- function ToggletVersion:JsonVariationDetail(featureName, defaultValue, forceSelectRealtimeToggle)
--   return self:GetToggle(featureName, forceSelectRealtimeToggle):JsonVariationDetail(defaultValue)
-- end

function ToggletClient:Variation(featureName, defaultVariantName, forceSelectRealtimeToggle)
  local variant = self:GetVariant(featureName, forceSelectRealtimeToggle)
  return variant and variant.feature_enabled and variant.enabled and variant.name or defaultVariantName
end

function ToggletClient:selectTogglesMap(forceSelectRealtimeToggle)
  if forceSelectRealtimeToggle == true then
    return self.realtimeTogglesMap
  end

  return self.useExplicitSyncMode and self.synchronizedTogglesMap or self.realtimeTogglesMap
end

function ToggletClient:SyncToggles(fetchNow)
  if self.offline or not self.useExplicitSyncMode then
    return Promise.Completed()
  end

  if fetchNow then
    return self:UpdateToggles(true) -- skip calculate context hash
        :Next(function()
          self:conditionalSyncTogglesMap()
        end)
  else
    self:conditionalSyncTogglesMap()
    return Promise.Completed()
  end
end

function ToggletClient:conditionalSyncTogglesMap(force)
  if force == true or self.lastSynchronizedETag ~= self.etag then
    self.lastSynchronizedETag = self.etag
    self.synchronizedTogglesMap = Util.DeepClone(self.realtimeTogglesMap)
    self:emit(Events.UPDATE, self.synchronizedTogglesMap)
  end
end

function ToggletClient:WatchToggle(featureName, callback)
  if self.offline then return function() end end

  Validation.RequireName(featureName, "featureName", "ToggletClient:WatchToggle")
  Validation.RequireFunction(callback, "callback", "ToggletClient:WatchToggle")

  local eventName = "update:" .. featureName
  return self.eventEmitter:On(eventName, callback)
end

function ToggletClient:WatchToggleWithInitialState(featureName, callback)
  if self.offline then return function() end end

  Validation.RequireName(featureName, "featureName", "ToggletClient:WatchToggleWithInitialState")
  Validation.RequireFunction(callback, "callback", "ToggletClient:WatchToggleWithInitialState")

  local eventName = "update:" .. featureName

  -- Note: Register event handlers first to ensure they work as intended when emitting for initial setup.
  local off = self.eventEmitter:On(eventName, callback)

  -- If READY event has already been emitted, execute immediately
  -- If READY event has not been emitted yet, execute after the READY event occurs
  if self.readyEventEmitted then
    self.eventEmitter:Emit(eventName, self:GetToggle(featureName, true)) -- select realtime toggle
  else
    self.logger:Debug("👀 WatchToggleWithInitialState: Waiting for `ready` event. feature=`%s`", featureName)

    self:Once(Events.READY, function()
      self.eventEmitter:Emit(eventName, self:GetToggle(featureName, true)) -- select realtime toggle
    end)
  end

  return off
end

function ToggletClient:UnwatchToggle(featureName, callback)
  if self.offline then return end

  Validation.RequireName(featureName, "featureName", "ToggletClient:UnwatchToggle")

  local eventName = "update:" .. featureName
  self.eventEmitter:Off(eventName, callback)
end

function ToggletClient:UpdateToggles(skipCalculateContextHash)
  if self.offline then
    return Promise.Completed()
  end

  if self.fetching then
    local promise = Promise.New()

    if skipCalculateContextHash or self.fetchingContextHash ~= Util.CalculateHash(self.context) then
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

  if self.started then
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

function ToggletClient:GetContext()
  return Util.DeepClone(self.context)
end

function ToggletClient:updateContextField(field, value)
  if STATIC_CONTEXT_FIELDS[field] then
    self.logger:Warn("🧩 `%s` is a static field. It can't be updated with ToggletClient:updateContextField.", field)
    return false
  end

  self.logger:Debug("🧩 Update a context field: field=`%s`, value=`%s`", field, value)

  if DEFINED_CONTEXT_FIELDS[field] then
    self.context[field] = value
  else
    if not self.context.properties then
      self.context.properties = {}
    end
    if value == self.context.properties[field] then return false end
    self.context.properties[field] = value
  end

  return true
end

function ToggletClient:updateContextFields(fields)
  local changeds = 0
  for field, value in pairs(fields) do
    if self:updateContextField(field, value) then
      changeds = changeds + 1
    end
  end

  return changeds > 0
end

function ToggletClient:SetContextFields(fields)
  if self.offline then
    return Promise.Completed()
  end

  local changeds = self:updateContextFields(fields);
  if self.started and changeds then
    return self:UpdateToggles(true) -- skip calculate context hash
  else
    return Promise.Completed()
  end
end

function ToggletClient:SetContextField(field, value)
  if self.offline then
    return Promise.Completed()
  end

  local changed = self:updateContextField(field, value)
  if self.started and changed then
    return self:UpdateToggles(true) -- skip calculate context hash
  else
    return Promise.Completed()
  end
end

function ToggletClient:RemoveContextField(field)
  if self.offline then
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

  if self.started then
    return self:UpdateToggles(true) -- skip calculate context hash
  else
    return Promise.Completed()
  end
end

function ToggletClient:handleHttpErrorCases(url, statusCode, responseBody)
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

function ToggletClient:getNextFetchDelay()
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

function ToggletClient:backoff()
  self.fetchFailures = math.min(self.fetchFailures + 1, 10)
  return self:getNextFetchDelay()
end

function ToggletClient:countSuccess()
  self.fetchFailures = math.max(self.fetchFailures - 1, 0)
  return self:getNextFetchDelay()
end

-- FIXME retry 상황일때 처리만 신경써주면 문제없을듯 하다!!
function ToggletClient:scheduleNextFetch(delay, retry)
  if delay > 0 then
    self:cancelFetchTimer()

    if retry == true then
      self.logger:Debug("🗓️ Next fetch toggles in %.2fs for Retry", delay)
    else
      self.logger:Debug("🗓️ Next fetch toggles in %.2fs", delay)
    end

    self.fetchTimer = self.timer:SetTimeout(delay, function()
      self:fetchToggles(retry)
    end)
  end
end

function ToggletClient:cancelFetchTimer()
  if self.fetchTimer then
    -- self.logger:Debug("Cancel fetch timer")
    self.timer:Cancel(self.fetchTimer)
    self.fetchTimer = nil
  end
end

function ToggletClient:Stop()
  local promise = Promise.New()

  if self.offline then
    return promise:Resolve()
  end

  if not self.started then
    self.logger:Warn("⚠️ ToggletClient is not started.")
    return promise:Resolve()
  end

  if self.metricsReporter then
    self.metricsReporter:Stop()
  end

  if self.timer then
    self.timer:CancelAll()
  end

  self.started = false

  self.logger:Info("⏹️ ToggletClient is stopped.")

  return promise:Resolve()
end

function ToggletClient:IsReady()
  return self.offline or self.readyEventEmitted
end

function ToggletClient:GetError()
  return (self.sdkState == 'error' and self.lastError) or nil
end

function ToggletClient:SendMetrics()
  if self.metricsReporter then
    return self.metricsReporter:SendMetrics()
  else
    return Promise.Completed()
  end
end

function ToggletClient:resolveSessionId()
  if self.context.sessionId then
    return Promise.FromResult(self.context.sessionId)
  end

  return self.storage:Load(SESSION_ID_KEY):Next(function(sessionId)
    if sessionId then
      return Promise.FromResult(sessionId)
    end

    sessionId = tostring(math.random(1, 1000000000))
    return self.storage:Save(SESSION_ID_KEY, sessionId)
  end)
end

function ToggletClient:getHeaders()
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
    if value then -- discard nil
      headers[name] = value
    end
  end

  return headers
end

function ToggletClient:storeToggles(toggleArray)
  local newTogglesArray = toggleArray or {}

  local oldTogglesMap = self.realtimeTogglesMap
  local newTogglesMap = convertTogglesArrayToMap(newTogglesArray)

  if self.logger:IsEnabled(Logging.LogLevel.Debug) then
    self.logger:Debug("✨ Toggles updated: oldToggles=%s", Json.encode(oldTogglesMap))
    self.logger:Debug("✨ Toggles updated: newToggles=%s", Json.encode(newTogglesMap))
  end

  self.realtimeTogglesMap = newTogglesMap

  if not self.useExplicitSyncMode then
    self:emit(Events.UPDATE, newTogglesArray)
  end

  -- Detects disabled flags
  for _, oldToggle in pairs(oldTogglesMap) do
    local newToggle = newTogglesMap[oldToggle.name]
    local toggleIsDisabled = newToggle == nil
    if toggleIsDisabled then
      self.logger:Debug("✨ Toggle `%s` is disabled.", oldToggle.name)

      local eventName = "update:" .. oldToggle.name
      if self.eventEmitter:HasListeners(eventName) then
        self.eventEmitter:Emit(eventName, self:GetToggle(oldToggle.name, true)) -- select realtime toggle
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
    elseif Util.CalculateHash(oldToggle) ~= Util.CalculateHash(newToggle) then
      self.logger:Debug("✨ Toggle `%s` is enabled and variants changed.", newToggle.name)
      emitEvent = true
    end

    if emitEvent then
      local eventName = "update:" .. newToggle.name
      if self.eventEmitter:HasListeners(eventName) then
        self.eventEmitter:Emit(eventName, self:GetToggle(newToggle.name, true)) -- select realtime toggle
      end
    end
  end

  return self.storage:Store(TOGGLES_KEY, newTogglesArray)
end

function ToggletClient:isTogglesStorageTTLEnabled()
  return self.experimental.togglesStorageTTL and self.experimental.togglesStorageTTL > 0
end

function ToggletClient:isUpToDate()
  if not self:isTogglesStorageTTLEnabled() then
    return false
  end

  local now = os.time()
  local ttl = self.experimental.togglesStorageTTL or 0
  return self.lastRefreshTimestamp > 0 and
      self.lastRefreshTimestamp <= now and
      now - self.lastRefreshTimestamp <= ttl
end

function ToggletClient:loadLastRefreshTimestamp()
  if not self:isTogglesStorageTTLEnabled() then
    return Promise.FromResult(0)
  end

  return self.storage:Load(LAST_UPDATE_KEY):Next(function(lastRefresh)
    local contextHash = Util.computeContextHashValue(self.context)
    local timestamp = (lastRefresh and lastRefresh.key == contextHash) and lastRefresh.timestamp or 0
    return Promise.FromResult(timestamp)
  end)
end

function ToggletClient:storeLastRefreshTimestamp()
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

function ToggletClient:initialFetchToggles()
  self.logger:Info("🔄 Initial fetch toggles")

  if self:isUpToDate() then
    if not self.fetchedFromServer then
      self.fetchedFromServer = true
      self:setReady()
    end

    self:scheduleNextFetch(self.refreshInterval, false)

    return Promise.Completed()
  end

  return self:fetchToggles():Next(function()
    if not self.useExplicitSyncMode then
      self.synchronizedTogglesMap = Util.DeepClone(self.realtimeTogglesMap)
    end
  end)
end

function ToggletClient:contextWithAppName()
  local context = {
    -- static context fields
    appName = self.appName,
    environment = self.environment,
  }

  -- predefined context fields
  for field, _ in pairs(DEFINED_CONTEXT_FIELDS) do
    local value = self.context[field]
    if value ~= nil then
      context[field] = value
    end
  end

  -- custom properties
  if self.context.properties then
    context.properties = {}
    for key, val in pairs(self.context.properties) do
      context.properties[key] = val
    end
  end

  return context
end

-- FIXME retry를 구분해서 처리해야함
function ToggletClient:fetchToggles(retry)
  local context = self:contextWithAppName()

  local isPOST = self.usePOSTrequests
  local url = isPOST and self.url or Util.UrlWithContextAsQuery(self.url, context)
  local body = nil
  local method = isPOST and "POST" or "GET"

  -- Safely encode JSON for POST requests
  if isPOST then
    local success, jsonBody = pcall(Json.encode, { context = context })
    if not success then
      local jsonErrorDetail = ErrorHelper.GetJsonEncodingErrorDetail(tostring(jsonBody), "context")
      local detail = {
        contextPreview = ErrorHelper.GetTableKeys(context),
        errorMessage = tostring(jsonBody),
        prevention = jsonErrorDetail.prevention,
        solution = jsonErrorDetail.solution,
        troubleshooting = jsonErrorDetail.troubleshooting
      }

      local error = self:emitError(
        ErrorTypes.JSON_ERROR,
        "Failed to encode request JSON: " .. tostring(jsonBody),
        "fetchToggles",
        Logging.LogLevel.Error,
        detail
      )

      self.sdkState = "error"
      self.lastError = error

      return Promise.FromError(error) -- stop fetching
    end
    body = jsonBody
  end

  local headers = self:getHeaders()

  -- Note: When using the POST method, the Content-Length header must be set.
  if isPOST then
    headers["Content-Length"] = tostring(body and #body or 0)
  end

  -- if self.logger:IsEnabled(Logging.LogLevel.Debug) then
  --   local success, jsonUrl = pcall(Json.encode, Util.UrlDecode(url))
  --   if success then
  --     self.logger:Debug("🔄 Fetching feature flags: %s", jsonUrl)
  --   else
  --     self.logger:Debug("🔄 Fetching feature flags: %s [JSON encoding failed]", tostring(url))
  --   end
  -- end

  self.logger:Debug("🔄 Fetching feature flags...")

  self.fetching = true
  self.fetchingContextHash = Util.CalculateHash(self.context)

  local promise = Promise.New()
  self.request(url, method, headers, body, function(response)
    self:handleFetchResponse(url, method, headers, body, response, promise)
  end)
  return promise
end

function ToggletClient:handleFetchResponse(url, method, headers, body, response, promise)
  self.fetching = false

  -- FIXME
  -- 성공일때만 지운다. 재시도 상황이면 클리어하면 안됨.
  -- 이건 좀 자세하게 분석해봐야함.
  self.fetchingContextHash = nil

  self:emit(Events.FETCH_COMPLETED) -- 성공일때만 emit해야하는??

  if self.sdkState == "error" and (response.status >= 200 and response.status < 400) then
    self.sdkState = "healthy"
    self:emit(Events.RECOVERED)
  end

  if response.status >= 200 and response.status < 300 then
    self.etag = Util.FindCaseInsensitive(response.headers, "ETag") or nil

    local data, error = self:parseAndValidateResponse(url, method, response)
    if error then
      promise:Reject(error)
      return
    end

    self:processSuccessfulResponse(data, promise)
  elseif response.status == 304 then
    self.logger:Debug("⚡ No changes, using cached data")

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
    end

    promise:Reject(error)
  end
end

function ToggletClient:parseAndValidateResponse(url, method, response)
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

function ToggletClient:processSuccessfulResponse(data, promise)
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

function ToggletClient:emit(event, ...)
  self.eventEmitter:Emit(event, ...)
end

function ToggletClient:On(event, callback)
  if self.offline then return function() end end

  return self.eventEmitter:On(event, callback)
end

function ToggletClient:Once(event, callback)
  if self.offline then return function() end end

  return self.eventEmitter:Once(event, callback)
end

function ToggletClient:Off(event, callback)
  if self.offline then return end

  self.eventEmitter:Off(event, callback)
end

-- FIXME 시스템 전역으로 처리해야함
-- Promise만 따로 처리를 하면 되려나?
function ToggletClient:Tick()
  if self.timer then
    self.timer:Tick()
  end

  -- 시스템 전역객체이므로, 별도로 처리하는게 맞다.
  -- 일단은 이 코드베이스외에서는 사용되지 않으므로, 당장은 여기에서 호출하도록 하자.
  Promise.Update()
end

function ToggletClient:createError(type, message, functionName, detail)
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

function ToggletClient:emitError(type, message, functionName, logLevel, detail)
  local errorData = self:createError(type, message, functionName, detail)

  -- Set default log level to Warning
  logLevel = logLevel or Logging.LogLevel.Warning

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

    self.logger:Log(logLevel, logMessage)
  end

  self:emit(Events.ERROR, errorData)

  return errorData
end

-- function ToggletClient:callWithGuard(callback, ...)
--   if not callback then return end

--   local success, result = pcall(callback, ...)
--   if not success then
--     local errorMsg = tostring(result)
--     local detail = {
--       callbackType = type(callback),
--       argCount = select("#", ...),
--       callLocation = debug.getinfo(2, "Sl"),
--       prevention = "Ensure callback functions are properly implemented and handle all edge cases.",
--       solution = "Review callback implementation and add proper error handling within the callback.",
--       troubleshooting = {
--         "1. Check callback function implementation for runtime errors",
--         "2. Verify all parameters passed to callback are valid",
--         "3. Add try-catch blocks within callback if needed",
--         "4. Review callback logic for potential nil access or type errors"
--       }
--     }
--     self:emitError(ErrorTypes.CALLBACK_ERROR, errorMsg, "callWithGuard", Logging.LogLevel.Error, detail)
--   end
--   return success, result
-- end

return ToggletClient
