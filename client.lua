-- TODO 실시간으로 반영 가능한 부분과 수동으로 변경된 내용을 반영하는 부분을 나눌수 있도록 재설계.
-- TODO 폴링 외에 실시간 스트리밍 처리

local Json = require("framework.3rdparty.feature-flags.dkjson")
local Timer = require("framework.3rdparty.feature-flags.timer")
local MetricsReporter = require("framework.3rdparty.feature-flags.metrics-reporter")
local InMemoryStorageProvider = require("framework.3rdparty.feature-flags.storage-provider-inmemory")
local EventEmitter = require("framework.3rdparty.feature-flags.event-emitter")
local EventSystem = require("framework.3rdparty.feature-flags.event-system")
local Util = require("framework.3rdparty.feature-flags.util")
local Logger = require("framework.3rdparty.feature-flags.logger")
local Events = require("framework.3rdparty.feature-flags.events")

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
    eventId = Util.uuid(),
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

local function _makeDisabledToggle(name)
  return {
    name = name,
    enabled = false,
    variant = DEFAULT_DISABLED_VARIANT,
    impressionData = false,
  }
end

------------------------------------------------------------------
-- Client implementation
------------------------------------------------------------------

local Client = {}
Client.__index = Client

function Client.new(config)
  local self = setmetatable({}, Client)

  --TODO enableDevMode

  self.loggerFactory = config.loggerFactory or Logger.DefaultLoggerFactory.new(Logger.LogLevel.Log)
  self.logger = self.loggerFactory:createLogger("UnleashClient")

  self.offline = config.offline or false
  self.toggleMap = convertToggleArrayToMap(config.bootstrap or {})

  -- Validate required fields
  if not config.appName then error("`appName` is required") end

  if not self.offline then
    if not config.url then error("`url` is required") end
    if not config.request then error("`request` is required") end
    if not config.clientKey then error("`clientKey` is required") end
  end

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

  -- Explicit synchronization mode
  self.useExplicitSyncMode = config.useExplicitSyncMode or false
  self.synchronizedToggleMap = Util.deepClone(self.toggleMap)

  self.storage = config.storageProvider or InMemoryStorageProvider.new(self.loggerFactory)
  self.impressionDataAll = config.impressionDataAll or false
  self.refreshInterval = (config.disableRefresh and 0) or (config.refreshInterval or 30)
  self.request = config.request
  self.usePOSTrequests = config.usePOSTrequests or false
  self.sdkState = "initializing"
  self.experimental = Util.deepClone(config.experimental or {})

  self.lastRefreshTimestamp = 0
  self.etag = nil
  self.readyEventEmitted = false
  self.fetchedFromServer = false
  self.started = false
  self.bootstrap = config.bootstrap
  self.bootstrapOverride = config.bootstrapOverride ~= false
  self.hasPreviousStates = false

  self.eventEmitter = EventEmitter.new(self.loggerFactory)
  self.eventSystem = EventSystem.new(self.loggerFactory)

  self.timer = Timer.new(self.loggerFactory)
  self.fetchTimer = nil

  if not self.offline then
    self.metricsReporter = MetricsReporter.new({
      appName = config.appName,
      url = self.url,
      request = self.request,
      clientKey = config.clientKey,
      headerName = self.headerName,
      customHeaders = self.customHeaders,
      disableMetrics = config.disableMetrics or false,
      metricsIntervalInitial = config.metricsIntervalInitial or 2,
      metricsInterval = config.metricsInterval or 30,
      onError = function(err) self:_emit(Events.ERROR, err) end,
      onSent = function(data) self:_emit(Events.SENT, data) end,
      timer = self.timer,
      loggerFactory = self.loggerFactory,
    })
  end

  -- setup backoff
  self.backoffParams = {
    min = config.backoff and config.backoff.min or 1,        -- 1초부터 시작
    max = config.backoff and config.backoff.max or 10,       -- 10초까지 증가
    factor = config.backoff and config.backoff.factor or 2,  -- exponential backoff
    jitter = config.backoff and config.backoff.jitter or 0.2 -- 20% jitter
  }
  self.failures = 0

  -- auto start
  if config.disableAutoStart ~= true then
    self.logger:info("Starting automatically...")
    self:start()
  end

  return self
end

function Client:waitForReady(callback)
  if self.readyEventEmitted then
    self:_safeCallCallback(callback)
  else
    self:on(Events.READY, function()
      self:_safeCallCallback(callback)
    end)
  end
end

function Client:getAllEnabledToggles()
  local toggleMap = self:_selectToggleMap()

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

function Client:isEnabled(featureName)
  if not featureName or type(featureName) ~= "string" or string.len(featureName) == 0 then
    self.logger:error("`featureName` is required")
    return false
  end

  local toggleMap = self:_selectToggleMap()

  local toggle = toggleMap[featureName]
  local enabled = (toggle and toggle.enabled) or false
  self.metricsReporter:count(featureName, enabled)

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
    self:_emit(Events.IMPRESSION, event)
  end

  return enabled
end

function Client:getVariant(featureName)
  if not featureName or type(featureName) ~= "string" or string.len(featureName) == 0 then
    self.logger:warn("`featureName` is required")
    return DEFAULT_DISABLED_VARIANT
  end

  local toggleMap = self:_selectToggleMap()

  local toggle = toggleMap[featureName]
  local enabled = (toggle and toggle.enabled) or false
  local variant = (toggle and toggle.variant) or DEFAULT_DISABLED_VARIANT

  if variant.name then
    self.metricsReporter:countVariant(featureName, variant.name)
  end

  self.metricsReporter:count(featureName, enabled)

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
    self:_emit(Events.IMPRESSION, event)
  end

  return {
    name = variant.name,
    enabled = variant.enabled,
    feature_enabled = enabled,
    payload = variant.payload
  }
end

-- Helper function to safely call user callbacks
function Client:_safeCallCallback(callback, ...)
  if not callback or type(callback) ~= "function" then
    return
  end

  local success, result = pcall(callback, ...)
  if not success then
    self.logger:error("Error in user callback: %s", tostring(result))

    self:_emit(Events.ERROR, {
      type = "CallbackError",
      message = tostring(result)
    })
  end
  return success, result
end

function Client:updateToggles(callback)
  if self.offline then
    self:_safeCallCallback(callback)
    return
  end

  if self.fetchTimer ~= nil or self.fetchedFromServer then
    self:_cancelFetchTimer()
    self:_fetchToggles(callback)
    return
  end

  if self.started then
    self:once(Events.READY, function()
      self:_cancelFetchTimer()
      self:_fetchToggles(function()
        self:_safeCallCallback(callback)
      end)
    end)
  else
    -- If not started yet, we'll fetch toggles after start anyway,
    -- so we can skip fetching toggles here.
    self:_safeCallCallback(callback)
  end
end

function Client:updateContext(context, callback)
  if self.offline then
    self:_safeCallCallback(callback)
    return
  end

  for _, field in ipairs(STATIC_CONTEXT_FIELDS) do
    if context[field] then
      self.logger:warn("`%s` is a static field name. It can't be updated with updateContext.", field)
    end
  end

  local staticContext = {
    environment = self.context.environment,
    appName = self.context.appName,
    sessionId = self.context.sessionId,
  }

  -- TODO If there are no changes in the context, return

  self.context = Util.deepClone(staticContext, context)

  if self.logger:isEnabled(Logger.LogLevel.Debug) then
    self.logger:debug("Context is updated: %s", Json.encode(self.context))
  end

  self:updateToggles(callback)
end

function Client:getContext()
  return Util.deepClone(self.context)
end

function Client:setContextField(field, value, callback)
  if self.offline then
    self:_safeCallCallback(callback)
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
    self:updateToggles(callback)
  else
    self:_safeCallCallback(callback)
  end
end

function Client:removeContextField(field, callback)
  if self.offline then
    self:_safeCallCallback(callback)
    return
  end

  if isDefinedContextField(field) then
    if not self.context[field] then
      self:_safeCallCallback(callback)
      return
    end

    self.context[field] = nil
  elseif self.context.properties and type(self.context.properties) == "table" then
    if not self.context.properties[field] then
      self:_safeCallCallback(callback)
      return
    end

    table.remove(self.context.properties, field)
  end

  self:updateToggles(callback)
end

function Client:_setReady()
  if not self.readyEventEmitted then
    self.readyEventEmitted = true
    self:_emit(Events.READY)
  end
end

function Client:_init(callback)
  self.logger:debug("Initializing...")

  self:_resolveSessionId(function(sessionId)
    self.context.sessionId = sessionId

    self.storage:get(TOGGLES_KEY, function(toggles)
      self.toggleMap = convertToggleArrayToMap(toggles or {})
      if self.useExplicitSyncMode then
        self.synchronizedToggleMap = Util.deepClone(self.toggleMap)
      end

      self.storage:get(ETAG_KEY, function(etag)
        self.etag = etag
      end)

      self:_loadLastRefreshTimestamp(function(timestamp)
        self.lastRefreshTimestamp = timestamp

        if self.bootstrap and (self.bootstrapOverride or Util.isEmptyTable(self.toggleMap)) then
          self.storage:save(TOGGLES_KEY, self.bootstrap, function()
            self.toggleMap = convertToggleArrayToMap(self.bootstrap)
            if self.useExplicitSyncMode then
              self.synchronizedToggleMap = Util.deepClone(self.toggleMap)
            end
            self.sdkState = "healthy"
            self.etags = nil

            self:_storeLastRefreshTimestamp(function()
              -- _setReady() 가 먼저인가?
              self:_setReady()
              self:_emit(Events.INIT)
              self:_safeCallCallback(callback)
            end)
          end)
        else
          self.sdkState = "healthy"
          self:_emit(Events.INIT)
          self:_safeCallCallback(callback)
        end
      end)
    end)
  end)
end

-- TODO callback 인자로 error를 전달해주는게 좋을듯
function Client:start(callback)
  if self.started then
    -- TODO error 이벤트를 발생시켜줘야하나?

    self.logger:error("Client has already started, call stop() before restarting.")
    self:_safeCallCallback(callback)
    return
  end

  self.started = true

  -- initialize asynchronously with a callback
  self:_init(function(err)
    if err then
      self.logger:error(tostring(err))

      self.sdkState = "error"
      self:_emit(Events.ERROR, err)
      self.lastError = err
    end

    -- initial fetch toggles
    if not self.offline then
      self:_initialFetchToggles(function()
        self.logger:info("Client is started. (environment=%s)", self.context.environment)

        self.metricsReporter:start()

        self:_safeCallCallback(callback)
      end)
    else
      self.logger:info("Client is started as OFFLINE mode. (environment=%s)", self.context.environment)
      self:_setReady()
    end
  end)
end

function Client:_handleErrorCases(url, statusCode)
  if statusCode == 401 or     -- unauthorized
      statusCode == 403 then  -- forbidden
    return self:_handleConfigurationError(url, statusCode)
  elseif statusCode == 404 or -- not found
      statusCode == 429 or    -- too many request
      statusCode == 500 or    -- internal server error
      statusCode == 502 or    -- bad gate way
      statusCode == 503 or    -- service unavailable
      statusCode == 504 then  -- gateway timeout
    return self:_handleRecoverableError(url, statusCode)
  else
    return self.refreshInterval
  end
end

function Client:_handleConfigurationError(url, statusCode)
  self.failures = self.failures + 1

  self:_emit(Events.ERROR, {
    type = "ConfigurationError",
    message = url ..
        " responded " ..
        statusCode .. " which means your API key is not allowed to connect. Stopping refresh of toggles",
    code = statusCode,
  })

  -- stop fetching
  self.logger:error("No more fetches will be performed. Please check that the token for API calls is correct!")
  return 0
end

function Client:_handleRecoverableError(url, statusCode)
  local nextFetchDelay = self:_backoff()

  if statusCode == 429 then -- too many request
    self:_emit(Events.ERROR, {
      type = "RateLimitError",
      message = url ..
          " responded " ..
          statusCode ..
          " which means you are being rate limited. Stopping refresh of toggles for " .. nextFetchDelay .. " seconds",
      code = statusCode,
    })
  elseif statusCode == 404 then -- not found
    self:_emit(Events.ERROR, {
      type = "NotFoundError",
      message = url ..
          " responded " ..
          statusCode ..
          " which means the resource was not found. Stopping refresh of toggles for " .. nextFetchDelay .. " seconds",
      code = statusCode,
    })
  elseif statusCode == 500 or -- internal server error
      statusCode == 502 or    -- bad gate way
      statusCode == 503 or    -- service unavailable
      statusCode == 504 then  -- gateway timeout
    self:_emit(Events.ERROR, {
      type = "ServerError",
      message = url ..
          " responded " ..
          statusCode ..
          " which means the server is having issues. Stopping refresh of toggles for " .. nextFetchDelay .. " seconds",
      code = statusCode,
    })
  end

  return nextFetchDelay
end

function Client:_getNextFetchDelay()
  local delay = self.refreshInterval
  local extra = 0
  if self.failures > 0 then
    extra = math.pow(2, self.failures)

    if self.backoffParams.jitter > 0 then
      local rand = math.random() * 2 - 1
      extra = extra + rand * self.backoffParams.jitter * extra
    end

    extra = math.min(extra, self.backoffParams.max)
    extra = math.max(extra, self.backoffParams.min)
  end

  return delay + extra
end

function Client:_backoff()
  self.failures = math.min(self.failures + 1, 10)
  return self:_getNextFetchDelay()
end

function Client:_countSuccess()
  self.failures = math.max(self.failures - 1, 0)
  return self:_getNextFetchDelay()
end

function Client:_timedFetch(interval)
  -- interval이 0보다 작거나 같으면, timer를 예약하지 않음.
  -- (의도된 동작임. 복구 불가능한 에러가 발생했을 경우에는 더이상 시도하지 않음. 토큰 오류 같은 경우)

  -- if interval > 0 and self.mode.type == "polling" then
  if interval > 0 then
    self.logger:debug("Timed fetching toggles in " .. interval .. " seconds.")

    self.fetchTimer = self.timer:timeout(interval, function()
      self:_fetchToggles(function(err) end)
    end)
  end
end

function Client:_cancelFetchTimer()
  if self.fetchTimer then
    self.logger:debug("Cancel fetch timer.");

    self.timer:remove(self.fetchTimer)
    self.fetchTimer = nil
  end
end

function Client:stop()
  if self.offline then
    return
  end

  if not self.started then
    self.logger:warn("Client is not stated.")
    return
  end

  self:_cancelFetchTimer()

  self.metricsReporter:stop()

  self.timer:removeAll()

  self.started = false

  self.logger:info("Client is stopped.")
end

function Client:isReady()
  if self.offline then
    return true
  end

  return self.readyEventEmitted
end

function Client:getError()
  if self.offline then
    return nil
  end

  return (self.sdkState == 'error' and self.lastError) or nil
end

function Client:sendMetrics()
  return self.metricsReporter:sendMetrics()
end

function Client:_resolveSessionId(callback)
  if self.context.sessionId then
    self:_safeCallCallback(callback, self.context.sessionId)
    return
  end

  self.storage:get(SESSION_ID_KEY, function(sessionId)
    if not sessionId then
      sessionId = tostring(math.random(1, 1000000000))
      -- sessionId = Util.uuid()
      self.storage:save(SESSION_ID_KEY, sessionId, function()
        self:_safeCallCallback(callback, sessionId)
      end)
    else
      self:_safeCallCallback(callback, sessionId)
    end
  end)
end

function Client:_getHeaders()
  local headers = {
    [self.headerName] = self.clientKey,
    Accept = "application/json",
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

function Client:_storeToggles(toggles, callback)
  local newToggleArray = toggles or {}

  local oldToggleMap = self.toggleMap or {}
  local newToggleMap = convertToggleArrayToMap(newToggleArray)

  if self.logger:isEnabled(Logger.LogLevel.Debug) then
    self.logger:debug("Toggles updated: oldToggles=%s", Json.encode(oldToggleMap))
    self.logger:debug("Toggles updated: newToggles=%s", Json.encode(newToggleMap))
  end

  self.toggleMap = newToggleMap

  self:_emit(Events.UPDATE, newToggleArray)
  self.storage:save(TOGGLES_KEY, newToggleArray, callback)

  -- Detects disabled flags
  for _, oldToggle in pairs(oldToggleMap) do
    local newToggle = newToggleMap[oldToggle.name]
    local toggleIsDisabled = newToggle == nil
    if toggleIsDisabled then
      self.logger:info("Feature flag `%s` is disabled.", oldToggle.name)

      if self.eventSystem:isWatchingEvent(oldToggle.name) then
        local disabledToggle = _makeDisabledToggle(oldToggle.name)
        self.eventSystem:emit(oldToggle.name, disabledToggle)
      end
    end
  end

  -- Detects enabled or variant changed flags
  for _, newToggle in pairs(newToggleMap) do
    local emitEvent = false

    local oldToggle = oldToggleMap[newToggle.name]
    if not oldToggle then
      self.logger:info("Feature flag `%s` is enabled.", newToggle.name)
      emitEvent = true
    elseif Util.calculateHash(oldToggle) ~= Util.calculateHash(newToggle) then
      self.logger:info("Feature flag `%s` is enabled and variants changed.", newToggle.name)
      emitEvent = true
    end

    if emitEvent then
      if self.eventSystem:isWatchingEvent(newToggle.name) then
        self.eventSystem:emit(newToggle.name, newToggle)
      end
    end
  end
end

function Client:_isTogglesStorageTTLEnabled()
  return self.experimental.togglesStorageTTL and self.experimental.togglesStorageTTL > 0
end

function Client:_isUpToDate()
  if not self:_isTogglesStorageTTLEnabled() then
    return false
  end

  local now = os.time()
  local ttl = self.experimental.togglesStorageTTL or 0
  return self.lastRefreshTimestamp > 0 and
      self.lastRefreshTimestamp <= now and
      now - self.lastRefreshTimestamp <= ttl
end

function Client:_loadLastRefreshTimestamp(callback)
  if self:_isTogglesStorageTTLEnabled() then
    self.storage:get(LAST_UPDATE_KEY, function(lastRefresh)
      local contextHash = Util.computeContextHashValue(self.context)
      local timestamp = (lastRefresh and lastRefresh.key == contextHash) and lastRefresh.timestamp or 0
      self:_safeCallCallback(callback, timestamp)
    end)
  else
    self:_safeCallCallback(callback, 0)
  end
end

function Client:_storeLastRefreshTimestamp(callback)
  if self:_isTogglesStorageTTLEnabled() then
    self.lastRefreshTimestamp = os.time()
    local contextHash = Util.computeContextHashValue(self.context)
    local lastUpdateValue = {
      key = contextHash,
      timestamp = self.lastRefreshTimestamp
    }
    self.storage:save(LAST_UPDATE_KEY, lastUpdateValue, callback)
  else
    self:_safeCallCallback(callback)
  end
end

function Client:_initialFetchToggles(callback)
  self.logger:debug("Initial fetching toggles...")

  if self:_isUpToDate() then
    if not self.fetchedFromServer then
      self.fetchedFromServer = true
      self:_setReady()
    end

    self:_timedFetch(self.refreshInterval)

    self:_safeCallCallback(callback)
  else
    self:_fetchToggles(function(err)
      if not err and self.useExplicitSyncMode then
        self.synchronizedToggleMap = Util.deepClone(self.toggleMap)
      end

      self:_safeCallCallback(callback, err)
    end)
  end
end

function Client:_fetchToggles(callback)
  local isPOST = self.usePOSTrequests
  local url = isPOST and self.url or Util.urlWithContextAsQuery(self.url, self.context)
  local body = isPOST and Json.encode({ context = self.context }) or nil
  local method = isPOST and "POST" or "GET"

  local headers = self:_getHeaders()

  -- Note: When using the POST method, the Content-Length header must be set.
  if isPOST then
    headers["Content-Length"] = body and #body or 0
  end

  if self.logger:isEnabled(Logger.LogLevel.Debug) then
    self.logger:debug("Fetch feature flags: %s", Json.encode(Util.urlDecode(url)))
  end

  self.request(url, method, headers, body, function(response)
    if self.sdkState == "error" and response.status < 400 then
      self.sdkState = "healthy"
      self:_emit(Events.RECOVERED)
    end

    if response.status >= 200 and response.status < 300 then
      self.etag = Util.findCaseInsensitive(response.headers, "ETag") or nil

      local data, err = Json.decode(response.body)
      if not data then
        self.logger:error("JSON decode failed: %s", tostring(err))

        local error = {
          type = "JsonError",
          message = tostring(err)
        }

        self.sdkState = "error"
        self:_emit(Events.ERROR, error)
        self.lastError = error

        self:_safeCallCallback(callback, error)

        -- stop fetching
        return
      end

      self:_storeToggles(data.toggles, function()
        if self.sdkState ~= "healthy" then
          self.sdkState = "healthy"
        end

        -- 서버에서 처음으로 가져온경우에는 준비되었음으로 표시
        if not self.fetchedFromServer then
          self.fetchedFromServer = true
          self:_setReady()
        end

        self:_storeLastRefreshTimestamp(function()
          self.storage:save(ETAG_KEY, self.etag, function()
            local nextFetchDelay = self:_countSuccess()
            self:_timedFetch(nextFetchDelay)

            self:_safeCallCallback(callback, nil)
          end)
        end)
      end)
    elseif response.status == 304 then
      self.logger:debug("[304] No changes in feature flags, using cached data. etag=%s", tostring(self.etag))

      -- REMARKS
      --  etag가 캐싱된 경우, 서버에서 실제로 가져온건 아니지만
      --  이미 최신이므로 가져온걸로 처리해줘야함
      if not self.fetchedFromServer then
        self.fetchedFromServer = true
        self:_setReady()
      end

      self:_storeLastRefreshTimestamp(function()
        self:_safeCallCallback(callback) -- 304도 성공으로 처리
      end)

      local nextFetchDelay = self:_countSuccess()
      self:_timedFetch(nextFetchDelay)
    else
      if response.status <= 0 then
        self.logger:warn("Fetching flags did not have an OK response: " .. response.status)
      else
        self.logger:warn("Fetching flags did not have an OK response: " .. response.status .. "\n\n" .. response.body)
      end

      local error = { type = "HttpError", code = response.status }

      self.sdkState = "error"
      self:_emit(Events.ERROR, error)
      self.lastError = error

      -- 401, 403 오류인 경우에는 더이상 fetch를 하지 않는다.
      local nextFetchDelay = self:_handleErrorCases(url, response.status)
      self:_timedFetch(nextFetchDelay)

      self:_safeCallCallback(callback, error)
    end
  end)
end

function Client:_emit(event, ...)
  if self.eventEmitter:hasListeners(event) then
    if self.logger:isEnabled(Logger.LogLevel.Debug) then
      local argCount = select("#", ...)
      if argCount > 0 then
        local args = ...
        self.logger:debug("`" .. event .. "` event is emitted: %s", Json.encode(args))
      else
        self.logger:debug("`" .. event .. "` event is emitted.")
      end
    end

    self.eventEmitter:emit(event, ...)
  end
end

function Client:on(event, callback)
  self.eventEmitter:on(event, callback)
end

function Client:once(event, callback)
  self.eventEmitter:once(event, callback)
end

function Client:off(event, callback)
  self.eventEmitter:off(event, callback)
end

function Client:_selectToggleMap()
  if self.useExplicitSyncMode then
    return self.synchronizedToggleMap
  else
    return self.toggleMap
  end
end

function Client:syncToggles(callback)
  if not self.synchronizedToggleMap then
    self:_safeCallCallback(callback)
    return
  end

  -- TODO background에서 이미 업데이트하고 있었는데, 또다시 업데이트를 해야하만 할까?

  self.synchronizedToggleMap = Util.deepClone(self.toggleMap)

  self:_safeCallCallback(callback)

  -- self:updateToggles(function()
  -- TODO 변경된 내용을 최신 내용에 복제를 해줘야함.

  -- self:_safeCallCallback(callback)
  -- end)
end

function Client:watch(featureName, callback, ownerWeakref)
  if not featureName or type(featureName) ~= "string" or string.len(featureName) == 0 then
    self.logger:warn("`featureName` is required")
    return
  end

  if not callback or type(callback) ~= "function" then
    self.logger:warn("`callback` is required")
    return
  end

  -- Wrap the callback to handle errors
  local safeCallback = function(...)
    self:_safeCallCallback(callback, ...)
  end

  return self.eventSystem:watch(featureName, safeCallback, ownerWeakref)
end

-- TODO toggle 접근용 인터페이스로 감싸서 전달하는게 좋을듯함!
function Client:initAndWatch(featureName, callback, ownerWeakref)
  local disabledToggle = _makeDisabledToggle(featureName)

  if not featureName or type(featureName) ~= "string" or string.len(featureName) == 0 then
    self.logger:warn("`featureName` is required")
    return disabledToggle
  end

  if not callback or type(callback) ~= "function" then
    self.logger:warn("`callback` is required")
    return disabledToggle
  end

  local action = function()
    local toggle = self.toggleMap[featureName]
    if toggle then
      self:_safeCallCallback(callback, toggle)
    else
      toggle = disabledToggle
      self:_safeCallCallback(callback, toggle)
    end

    self.logger:info("initAndWatch: feature=`%s`, initialState=%s", toggle.name, tostring(toggle.enabled))
  end

  -- If READY event has already been emitted, execute immediately
  -- If READY event has not been emitted yet, execute after the READY event occurs
  if self.readyEventEmitted then
    action()
  else
    self.logger:debug("initAndWatch: waiting for ready event. feature=`%s`", featureName)
    self:once(Events.READY, action)
  end

  -- FIXME callback을 wrap하게 되면, 해제가 안된다.

  -- Wrap the callback to handle errors
  local safeCallback = function(...)
    self:_safeCallCallback(callback, ...)
  end

  return self.eventSystem:watch(featureName, safeCallback, ownerWeakref)
end

-- FIXME callback이 wrap이 되어 있으므로, 해제가 안됨
function Client:unwatch(featureName, callback)
  if self.offline then
    return
  end

  return self.eventSystem:unwatch(featureName, callback)
end

function Client:tick()
  if self.offline then
    return
  end

  self.timer:tick()
end

-----------------------------------------------------------------------------------------------

function Client:booVariation(featureName, defaultValue)
  if not featureName or type(featureName) ~= "string" or featureName == "" then
    self.logger:warn("`featureName` is required")
    return defaultValue
  end

  defaultValue = defaultValue or false
  if type(defaultValue) ~= "boolean" then
    self.logger:warn("`defaultValue` must be a boolean")
    return defaultValue
  end

  local success, result = pcall(function()
    return self:isEnabled(featureName)
  end)

  if not success then
    self.logger:warn("Error in booVariation for feature '%s': %s", featureName, tostring(result))

    self:_emit(Events.ERROR, {
      type = "VariationError",
      message = tostring(result),
      featureName = featureName,
      variationType = "boolean"
    })

    return defaultValue
  end

  -- CHECKME 여기서 or을 해주는게 맞는걸까? 이건좀 생각해봐야할듯...
  return result or defaultValue
end

function Client:numberVariation(featureName, defaultValue)
  if not featureName or type(featureName) ~= "string" or featureName == "" then
    self.logger:warn("`featureName` is required")
    return defaultValue
  end

  defaultValue = defaultValue or 0
  if type(defaultValue) ~= "number" then
    self.logger:warn("`defaultValue` must be a number")
    return defaultValue
  end

  local success, variant = pcall(function()
    return self:getVariant(featureName)
  end)

  if not success then
    self.logger:warn("Error in numberVariation for feature '%s': %s", featureName, tostring(variant))

    self:_emit(Events.ERROR, {
      type = "VariationError",
      message = tostring(variant),
      featureName = featureName,
      variationType = "number"
    })

    return defaultValue
  end

  if variant and variant.payload and variant.payload.type == "number" then
    local numSuccess, numValue = pcall(function()
      return tonumber(variant.payload.value)
    end)

    if numSuccess and numValue then
      return numValue
    else
      self.logger:warn("Failed to convert value to number for feature '%s': %s", featureName,
      tostring(variant.payload.value))
      return defaultValue
    end
  end

  return defaultValue
end

function Client:stringVariation(featureName, defaultValue)
  if not featureName or type(featureName) ~= "string" or featureName == "" then
    self.logger:warn("`featureName` is required")
    return defaultValue
  end

  defaultValue = defaultValue or ""
  if type(defaultValue) ~= "string" then
    self.logger:warn("`defaultValue` must be a string")
    return defaultValue
  end

  local success, variant = pcall(function()
    return self:getVariant(featureName)
  end)

  if not success then
    self.logger:warn("Error in stringVariation for feature '%s': %s", featureName, tostring(variant))

    self:_emit(Events.ERROR, {
      type = "VariationError",
      message = tostring(variant),
      featureName = featureName,
      variationType = "string"
    })

    return defaultValue
  end

  if variant and variant.payload and variant.payload.type == "string" then
    if variant.payload.value ~= nil then
      local strValue = tostring(variant.payload.value)
      return strValue
    else
      self.logger:warn("Nil string value for feature '%s'", featureName)
      return defaultValue
    end
  end

  return defaultValue
end

function Client:jsonVariation(featureName, defaultValue)
  if not featureName or type(featureName) ~= "string" or featureName == "" then
    self.logger:warn("`featureName` is required")
    return defaultValue
  end

  defaultValue = defaultValue or {}
  if type(defaultValue) ~= "table" then
    self.logger:warn("`defaultValue` must be a table")
    return defaultValue
  end

  local variant = self:getVariant(featureName)
  if not variant or not variant.payload then
    self.logger:debug("No valid payload found for feature '%s'", featureName)
    return defaultValue
  end

  if variant.payload.type ~= "json" then
    self.logger:debug("Expected JSON payload for feature '%s' but got '%s'", featureName, variant.payload.type or "nil")
    return defaultValue
  end

  if not variant.payload.value then
    self.logger:warn("Empty JSON payload for feature '%s'", featureName)
    return defaultValue
  end

  local success, result = pcall(function()
    return Json.decode(variant.payload.value)
  end)

  if not success then
    self.logger:warn("Failed to decode JSON for feature '%s': %s", featureName, tostring(result))

    self:_emit(Events.ERROR, {
      type = "JsonDecodeError",
      message = tostring(result),
      featureName = featureName,
      payload = variant.payload.value
    })

    return defaultValue
  end

  if not result then
    self.logger:warn("JSON decode returned nil for feature '%s'", featureName)
    return defaultValue
  end

  return result
end

return Client
