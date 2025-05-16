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
local Backoff = require("framework.3rdparty.feature-flags.backoff")

local DEFINED_FIELDS = {
  "userId",
  "sessionId",
  "remoteAddress",
  "currentTime"
}

-- 개선: 이것뿐만 아니라 추가적으로 static context field 목록을 관리하는게 좋을것 같다.
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

------------------------------------------------------------------
-- Client implementation
------------------------------------------------------------------

local Client = {}
Client.__index = Client

function Client.new(config)
  local self = setmetatable({}, Client)

  self.loggerFactory = config.loggerFactory or Logger.DefaultLoggerFactory.new(Logger.LogLevel.Log)
  self.logger = self.loggerFactory:createLogger("Client")

  self.offline = config.offline or false
  self.toggles = config.bootstrap or {}
  self:_updateTogglesMap()

  if self.offline then
    return self
  end

  -- Validate required fields
  if not config.appName then error("`appName` is required") end
  if not config.url then error("`url` is required") end
  if not config.request then error("`request` is required") end
  if not config.clientKey then error("`clientKey` is required") end

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

  self.storage = config.storageProvider or InMemoryStorageProvider.new(self.loggerFactory)
  self.impressionDataAll = config.impressionDataAll or false
  self.refreshInterval = (config.disableRefresh and 0) or (config.refreshInterval or 30)
  self.request = config.request
  self.usePOSTrequests = config.usePOSTrequests or false
  self.sdkState = "initializing"
  self.backoffs = 0
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
  self.timerRunning = false

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

  -- backoff 설정
  self.backoff = Backoff.new({
    min = config.backoff and config.backoff.min or 1,        -- 1초부터 시작
    max = config.backoff and config.backoff.max or 10,       -- 10초까지 증가
    factor = config.backoff and config.backoff.factor or 2,  -- exponential backoff
    jitter = config.backoff and config.backoff.jitter or 0.2 -- 20% jitter
  })

  -- auto start
  if config.autoStart then
    self.logger:info("Starting automatically...")
    self:start()
  end

  return self
end

function Client:_updateTogglesMap()
  self.togglesMap = {}
  for _, toggle in ipairs(self.toggles) do
    self.togglesMap[toggle.name] = toggle
  end
end

-- 활성화된 플래그들만 반환하므로, 이름을 바꿔주는게 좋을듯..
function Client:getAllToggles()
  local result = {}
  for _, toggle in ipairs(self.toggles) do
    local flag = {
      name = toggle.name,
      enabled = toggle.enabled,
      variant = toggle.variant,
      impressionData = toggle.impressionData
    }
    table.insert(result, flag)
  end
  return result
end

function Client:isEnabled(key)
  if not key or type(key) ~= "string" or string.len(key) == 0 then
    self.logger:error("`key` is required")
    return false
  end

  local toggle = self.togglesMap[key]
  local enabled = (toggle and toggle.enabled) or false
  self.metricsReporter:count(key, enabled)

  local impressionData = self.impressionDataAll or (toggle and toggle.impressionData)
  if impressionData then
    local event = createImpressionEvent(
      self.context,
      enabled,
      key,
      IMPRESSION_EVENTS.IS_ENABLED,
      (toggle and toggle.impressionData) or nil,
      nil -- variant name is not applicable here
    )
    self:_emit(Events.IMPRESSION, event)
  end

  return enabled
end

function Client:getVariant(key)
  if not key or type(key) ~= "string" or string.len(key) == 0 then
    self.logger:warn("`key` is required")
    return DEFAULT_DISABLED_VARIANT
  end

  local toggle = self.togglesMap[key]
  local enabled = (toggle and toggle.enabled) or false
  local variant = (toggle and toggle.variant) or DEFAULT_DISABLED_VARIANT

  if variant.name then
    self.metricsReporter:countVariant(key, variant.name)
  end

  self.metricsReporter:count(key, enabled)

  local impressionData = self.impressionDataAll or (toggle and toggle.impressionData)
  if impressionData then
    local event = createImpressionEvent(
      self.context,
      enabled,
      key,
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

function Client:updateToggles(callback)
  if self.offline then
    if callback then
      callback()
    end
    return
  end

  callback = callback or function() end

  -- 이미 한번이상 서버에서 플래그들을 가져온
  -- 상태일 경우에는 fetchToggles() 만 수행함.
  if self.timerRunning or self.fetchedFromServer then
    self:_fetchToggles(callback)
    return
  end

  if self.started then
    self:once(Events.READY, function()
      self:_fetchToggles(function()
        callback()
      end)
    end)
  else
    -- 아직 start가 안된 상태에서는 어짜피 start후에 fetchToggles를
    -- 할것이기 때문에 fetchToggles를 생략한다.
    callback()
  end
end

-- fetch 중인 상태에서 updateContext()를 호출하게 되면 어떻게되나?
function Client:updateContext(context, callback)
  if self.offline then
    return
  end

  for _, field in ipairs(STATIC_CONTEXT_FIELDS) do
    if context[field] then
      self.logger:warn("`" .. field .. "` is a static field name. It can't be updated with updateContext.")
    end
  end

  local staticContext = {
    environment = self.context.environment,
    appName = self.context.appName,
    sessionId = self.context.sessionId,
  }

  self.context = Util.deepClone(staticContext, context)

  self.logger:debugLambda(function()
    return "Context is updated: " .. Json.encode(self.context)
  end)

  self:updateToggles(callback)
end

function Client:getContext()
  return Util.deepClone(self.context)
end

function Client:setContextField(field, value, callback)
  if self.offline then
    if callback then
      callback()
    end
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
    if callback then
      callback()
    end
  end
end

function Client:removeContextField(field, callback)
  if self.offline then
    if callback then
      callback()
    end
    return
  end

  if isDefinedContextField(field) then
    if not self.context[field] then
      return
    end

    self.context[field] = nil
  elseif self.context.properties and type(self.context.properties) == "table" then
    if not self.context.properties[field] then
      return
    end

    table.remove(self.context.properties, field)
  end

  self:updateToggles(callback)
end

function Client:_setReady()
  self.readyEventEmitted = true
  self:_emit(Events.READY)
end

function Client:_init(callback)
  self:_resolveSessionId(function(sessionId)
    self.context.sessionId = sessionId

    self.storage:get(TOGGLES_KEY, function(toggles)
      self.toggles = toggles or {}
      self:_updateTogglesMap()

      self.storage:get(ETAG_KEY, function(etag)
        self.etag = etag
      end)

      self:_loadLastRefreshTimestamp(function(timestamp)
        self.lastRefreshTimestamp = timestamp

        if self.bootstrap and (self.bootstrapOverride or #self.toggles == 0) then
          self.storage:save(TOGGLES_KEY, self.bootstrap, function()
            self.toggles = self.bootstrap
            self:_updateTogglesMap()

            self.sdkState = "healthy"
            self.etags = nil

            self:_storeLastRefreshTimestamp(function()
              self:_setReady()
              self:_emit(Events.INIT)
              callback()
            end)
          end)
        else
          self.sdkState = "healthy"
          self:_emit(Events.INIT)
          callback()
        end
      end)
    end)
  end)
end

function Client:start(callback)
  if self.offline then
    if callback then
      callback()
    end
    return
  end

  callback = callback or function() end

  self.started = true

  if self.timerRunning then
    self.logger:error("Client has already started, call stop() before restarting.")
    callback()
    return
  end

  -- initialize asynchronously with a callback
  -- bootstrapping?
  self:_init(function(err)
    if err then
      self.logger:error(tostring(err))

      self.sdkState = "error"
      self:_emit(Events.ERROR, err)
      self.lastError = err
    end

    -- initial fetch toggles
    self:_initialFetchToggles(function()
      self.logger:info("Client is started. (environment=`" .. self.context.environment .. "`)")

      self.metricsReporter:start()

      callback()
      end)
  end)
end

function Client:_handleErrorCases(url, statusCode)
  if statusCode == 401 or statusCode == 403 then
    return self:_handleConfigurationError(url, statusCode)
  elseif statusCode == 404 or
      statusCode == 429 or
      statusCode == 500 or
      statusCode == 502 or
      statusCode == 503 or
      statusCode == 504 then
    return self:_handleReceoverableError(url, statusCode)
  else
    return self.refreshInterval
  end
end

function Client:_handleConfigurationError(url, statusCode)
  self.failures = self.failures + 1

  if statusCode == 401 or statusCode == 403 then
    self:_emit(Events.ERROR, {
      type = "ConfigurationError",
      message = url ..
      " responded " .. statusCode .. " which means your API key is not allowed to connect. Stopping refresh of toggles",
      code = statusCode,
    })
  end

  return 0
end

function Client:_handleRecoverableError(url, statusCode)
  local nextFetch = self:_backoff()

  if statusCode == 429 then -- too many request
    self:_emit(Events.ERROR, {
      type = "RateLimitError",
      message = url .. " responded " .. statusCode .. " which means you are being rate limited. Stopping refresh of toggles for " .. nextFetch .. " seconds",
      code = statusCode,
    })
  elseif statusCode == 404 then -- not found
    self:_emit(Events.ERROR, {
      type = "NotFoundError",
      message = url .. " responded " .. statusCode .. " which means the resource was not found. Stopping refresh of toggles for " .. nextFetch .. " seconds",
      code = statusCode,
    })
  elseif statusCode == 500 or   -- internal server error
      statusCode == 502 or      -- bad gate way
      statusCode == 503 or      -- service unavailable
      statusCode == 504 then    -- gateway timeout
    self:_emit(Events.ERROR, {
      type = "ServerError",
      message = url .. " responded " .. statusCode .. " which means the server is having issues. Stopping refresh of toggles for " .. nextFetch .. " seconds",
      code = statusCode,
    })
  end

  return nextFetch
end

function Client:_nextFetch()
  -- TODO 지수, jitter처리
  return self.refreshInterval + self.failures * self.refreshInterval
end

function Client:_backoff()
  self.failures = math.min(self.failures + 1, 10)
  return self:_nextFetch()
end

function Client:_countSuccess()
  self.failures = math.max(self.failures - 1, 0)
  return self:_nextFetch()
end

function Client:_timedFetch(interval)
  self.logger:info("Timed fetching toggles in " .. interval .. " seconds.")

  -- TODO
  -- if refresh > 0 and self.mode.type == "polling" then
    self.timer:timeout(interval, function()
      self:_fetchToggles(function(err) end)
    end)
  -- end
end

function Client:stop()
  if self.offline then
    return
  end

  if not self.started then
    self.logger:warn("Client is not stated.")
    return
  end

  -- timeout context를 가지고 있다가, 그걸로 중지처리하던지..
  -- 그냥 모두 중지 처리하던지...
  if self.timerRunning then
    self.timerRunning = false
    self.timer:removeAll() -- 모든 timer callback을 강제 취소시킴
  end

  self.metricsReporter:stop()

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
    callback(self.context.sessionId)
    return
  end

  self.storage:get(SESSION_ID_KEY, function(sessionId)
    if not sessionId then
      sessionId = tostring(math.random(1, 1000000000))
      -- sessionId = Util.uuid()
      self.storage:save(SESSION_ID_KEY, sessionId, function()
        callback(sessionId)
      end)
    else
      callback(sessionId)
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

local function _findToggleInArray(array, name)
  for _, item in ipairs(array) do
    if item and item.name == name then
      return item
    end
  end
  return nil
end

local function _makeDisabledToggle(name)
  return {
    name = name,
    enabled = false,
    variant = DEFAULT_DISABLED_VARIANT,
    impressionData = false,
  }
end

function Client:_storeToggles(toggles, callback)
  local oldToggles = self.toggles or {}
  local newToggles = toggles or {}

  self.toggles = newToggles
  self:_updateTogglesMap()

  self:_emit(Events.UPDATE, newToggles)
  self.storage:save(TOGGLES_KEY, newToggles, callback)

  self.logger:debugLambda(function() return "Toggles updated: oldToggles=" .. Json.encode(oldToggles) end)
  self.logger:debugLambda(function() return "Toggles updated: newToggles=" .. Json.encode(newToggles) end)

  -- if self.hasPreviousStates then
  -- Detects disabled flags
  for _, oldToggle in ipairs(oldToggles) do
    local newToggle = _findToggleInArray(newToggles, oldToggle.name)
    local toggleIsDisabled = newToggle == nil
    if toggleIsDisabled then
      self.logger:info("Feature flag `" .. oldToggle.name .. "` is disabled.")

      if self.eventSystem:isWatchingEvent(oldToggle.name) then
        local disabledToggle = _makeDisabledToggle(oldToggle.name)
        self.eventSystem:emit(oldToggle.name, disabledToggle)
      end
    end
  end

  -- Detects enabled or variant changed flags
  for _, newToggle in ipairs(newToggles) do
    local emitEvent = false
    local oldToggle = _findToggleInArray(oldToggles, newToggle.name)
    if not oldToggle then
      self.logger:info("Feature flag `" .. newToggle.name .. "` is enabled.")
      emitEvent = true
    elseif Util.calculateHash(oldToggle) ~= Util.calculateHash(newToggle) then
      self.logger:info("Feature flag `" .. newToggle.name .. "` is enabled and variants changed.")
      emitEvent = true
    end

    if emitEvent then
      if self.eventSystem:isWatchingEvent(newToggle.name) then
        self.eventSystem:emit(newToggle.name, newToggle)
      end
    end
  end
  -- else
  --   self.hasPreviousStates = true
  --   self.logger:debugLambda(function() return "Initial enabled toggles: " .. Json.encode(self.toggles) end)
  -- end
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
      callback(timestamp)
    end)
  else
    callback(0)
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
    callback()
  end
end

function Client:_initialFetchToggles(callback)
  if self:_isUpToDate() then
    if not self.fetchedFromServer then
      self.fetchedFromServer = true
      self:_setReady()
    end

    self:_timedFetch(self.refreshInterval)

    callback()
    return
  end

  self:_fetchToggles(callback)
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

  self.logger:debugLambda(function()
    return "Fetch feature flags: " .. Json.encode(Util.urlDecode(url))
  end)

  self.request(url, method, headers, body, function(response)
    if self.sdkState == "error" and response.status < 400 then
      self.sdkState = "healthy"
      self:_emit(Events.RECOVERED)
    end

    if response.status >= 200 and response.status < 300 then
      self.etag = Util.findCaseInsensitive(response.headers, "ETag") or ""

      local data, err = Json.decode(response.body)
      if not data then
        self.logger:error("JSON decode failed: " .. tostring(err))

        self.sdkState = "error"
        self:_emit(Events.ERROR, { type = "JsonError", message = tostring(err) })
        self.lastError = { type = "JsonError", message = tostring(err) }

        callback({ type = "JsonError", message = tostring(err) })
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
          callback() -- 성공 시 오류 없이 콜백
        end)

        self.storage:save(ETAG_KEY, self.etag)

        self:_timedFetch(self.refreshInterval)
      end)
    elseif response.status == 304 then
      self.logger:debugLambda(function()
        return "[304] No changes in feature flags, using cached data. etag=" ..
            tostring(self.etag)
      end)

      -- REMARKS
      --   etag가 캐싱된 경우, 서버에서 실제로 가져온건 아니지만
      --   이미 최신이므로 가져온걸로 처리해줘야함
      if not self.fetchedFromServer then
        self.fetchedFromServer = true
        self:_setReady()
      end

      self:_storeLastRefreshTimestamp(function()
        callback() -- 304도 성공으로 처리
      end)

      self:_timedFetch(self.refreshInterval)
    else
      if response.status <= 0 then
        self.logger:warn("Fetching flags did not have an OK response: " .. response.status)
      else
        self.logger:warn("Fetching flags did not have an OK response: " .. response.status .. "\n\n" .. response.body)
      end

      self.sdkState = "error"
      local errorObj = { type = "HttpError", code = response.status }
      self:_emit(Events.ERROR, errorObj)
      self.lastError = errorObj

      local nextFetch = self:_handleErrorCases(url, response.status)
      self:_timedFetch(nextFetch)

      callback(errorObj) -- 오류 객체 전달
    end
  end)
end

function Client:_emit(event, ...)
  if self.eventEmitter:hasListeners(event) then
    local argCount = select("#", ...)
    if argCount > 0 then
      local args = ...
      self.logger:debugLambda(function() return "`" .. event .. "` event is emitted: " .. Json.encode(args) end)
    else
      self.logger:debugLambda(function() return "`" .. event .. "` event is emitted." end)
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

function Client:applyChanges()
  -- 실시간으로 변경된 내용을 외부에서 액세스하는 값에 반영이 되도록 함.

  -- TODO
  -- self.appliedToggles = Util.deepClone(self.toggles)
end

function Client:watch(key, callback, ownerWeakref)
  if not key or type(key) ~= "string" or string.len(key) == 0 then
    self.logger:warn("`key` is required")
    return
  end

  if not callback or type(callback) ~= "function" then
    self.logger:warn("`callback` is required")
    return
  end

  return self.eventSystem:watch(key, callback, ownerWeakref)
end

function Client:initAndWatch(key, callback, ownerWeakref)
  -- 플래그가 초기화된 상태에서 일괄로 처리해주는게 좋을까?

  -- if not self:isReady() then
  --   self.logger:warn("Client is not ready yet. Please call `ready()` before using this method.")
  --   -- 준비되었을때 callback을 호출해주기 위해서 대기시킴
  --   return
  -- end

  local disabledToggle = _makeDisabledToggle(key)

  if not key or type(key) ~= "string" or string.len(key) == 0 then
    self.logger:warn("`key` is required")
    return disabledToggle
  end

  if not callback or type(callback) ~= "function" then
    self.logger:warn("`callback` is required")
    return disabledToggle
  end

  local toggle = _findToggleInArray(self.toggles, key)
  if toggle then
    callback(toggle)
  else
    toggle = disabledToggle
    callback(toggle)
  end

  self.logger:info("initAndWatch: feature=`" .. toggle.name .. "`, initialState=" .. tostring(toggle.enabled))

  return self:watch(key, callback, ownerWeakref)
end

function Client:unwatch(key, callback)
  if self.offline then
    return
  end

  return self.eventSystem:unwatch(key, callback)
end

function Client:tick()
  if self.offline then
    return
  end

  self.timer:tick()
end

-----------------------------------------------------------------------------------------------

function Client:booVariation(key, defaultValue)
  if not key or type(key) ~= "string" or key == "" then
    self.logger:warn("`key` is required")
    return defaultValue
  end

  defaultValue = defaultValue or false
  if type(defaultValue) ~= "boolean" then
    self.logger:warn("`defaultValue` must be a boolean")
    return defaultValue
  end

  local success, result = pcall(function()
    return self:isEnabled(key)
  end)

  if not success then
    self.logger:warn(string.format(
      "Error in booVariation for feature '%s': %s",
      key,
      tostring(result)
    ))

    self:_emit(Events.ERROR, {
      type = "VariationError",
      message = tostring(result),
      featureName = key,
      variationType = "boolean"
    })

    return defaultValue
  end

  --여기서 or을 해주는게 맞는걸까? 이건좀 생각해봐야할듯...
  return result or defaultValue
end

function Client:numberVariation(key, defaultValue)
  if not key or type(key) ~= "string" or key == "" then
    self.logger:warn("`key` is required")
    return defaultValue
  end

  defaultValue = defaultValue or 0
  if type(defaultValue) ~= "number" then
    self.logger:warn("`defaultValue` must be a number")
    return defaultValue
  end

  local success, variant = pcall(function()
    return self:getVariant(key)
  end)

  if not success then
    self.logger:warn(string.format(
      "Error in numberVariation for feature '%s': %s",
      key,
      tostring(variant)
    ))

    self:_emit(Events.ERROR, {
      type = "VariationError",
      message = tostring(variant),
      featureName = key,
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
      self.logger:warn(string.format(
        "Failed to convert value to number for feature '%s': %s",
        key,
        tostring(variant.payload.value)
      ))
      return defaultValue
    end
  end

  return defaultValue
end

function Client:stringVariation(key, defaultValue)
  if not key or type(key) ~= "string" or key == "" then
    self.logger:warn("`key` is required")
    return defaultValue
  end

  defaultValue = defaultValue or ""
  if type(defaultValue) ~= "string" then
    self.logger:warn("`defaultValue` must be a string")
    return defaultValue
  end

  local success, variant = pcall(function()
    return self:getVariant(key)
  end)

  if not success then
    self.logger:warn(string.format(
      "Error in stringVariation for feature '%s': %s",
      key,
      tostring(variant)
    ))

    self:_emit(Events.ERROR, {
      type = "VariationError",
      message = tostring(variant),
      featureName = key,
      variationType = "string"
    })

    return defaultValue
  end

  if variant and variant.payload and variant.payload.type == "string" then
    if variant.payload.value ~= nil then
      local strValue = tostring(variant.payload.value)
      return strValue
    else
      self.logger:warn(string.format(
        "Nil string value for feature '%s'",
        key
      ))
      return defaultValue
    end
  end

  return defaultValue
end

function Client:jsonVariation(key, defaultValue)
  if not key or type(key) ~= "string" or key == "" then
    self.logger:warn("`key` is required")
    return defaultValue
  end

  defaultValue = defaultValue or {}
  if type(defaultValue) ~= "table" then
    self.logger:warn("`defaultValue` must be a table")
    return defaultValue
  end

  local variant = self:getVariant(key)
  if not variant or not variant.payload then
    self.logger:debug(string.format("No valid payload found for feature '%s'", key))
    return defaultValue
  end

  if variant.payload.type ~= "json" then
    self.logger:debug(string.format(
      "Expected JSON payload for feature '%s' but got '%s'",
      key,
      variant.payload.type or "nil"
    ))
    return defaultValue
  end

  if not variant.payload.value then
    self.logger:warn(string.format("Empty JSON payload for feature '%s'", key))
    return defaultValue
  end

  local success, result = pcall(function()
    return Json.decode(variant.payload.value)
  end)

  if not success then
    self.logger:warn(string.format(
      "Failed to decode JSON for feature '%s': %s",
      key,
      tostring(result)
    ))

    self:_emit(Events.ERROR, {
      type = "JsonDecodeError",
      message = tostring(result),
      featureName = key,
      payload = variant.payload.value
    })

    return defaultValue
  end

  if not result then
    self.logger:warn(string.format("JSON decode returned nil for feature '%s'", key))
    return defaultValue
  end

  return result
end

return Client
