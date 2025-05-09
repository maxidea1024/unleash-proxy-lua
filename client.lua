-- TODO request 실패시 backoff
-- TODO 실시간으로 반영 가능한 부분과 수동으로 변경된 내용을 반영하는 부분을 나눌수 있도록 재설계.
-- TODO 폴링 외에 실시간 스트리밍 처리
-- TODO static context fields 와 user context fields를 구분해주고, user context fields를 한번에 지울수 있는 기능을 넣어주는게 좋을듯!
-- TODO 로컬에 캐싱할때 etag도 같이 캐싱하는게 좋을듯함.
-- TODO 응답을 기다리는 도중 다시 요청하는것을 막거나, 큐잉하는게 좋을듯함.

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

  if (variantName and variantName ~= "") then
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

  -- Validate required fields
  if not config.url then error("`url` is required") end
  if not config.clientKey then error("`clientKey` is required") end
  if not config.appName then error("`appName` is required") end
  if not config.request then error("`request` is required") end

  self.loggerFactory = config.loggerFactory or Logger.DefaultLoggerFactory.new(Logger.LogLevel.Log)
  self.logger = self.loggerFactory:createLogger("FFClient")

  self.disabled = config.disabled or false
  if self.disabled then
    self.logger:warn("The client is disabled. All flags will be evaluated as disabled!")
    return self
  end

  self.toggles = config.bootstrap or {}

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
  self.request = config.request -- TODO 지정하지 않았을때 처리
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
  self.fetching = false
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

  -- initialize asynchronously with a callback
  self.ready = function(callback)
    self:_init(function(err)
      if err then
        self.logger:error(tostring(err))

        self.sdkState = "error"
        self:_emit(Events.ERROR, err)
        self.lastError = err
      end

      callback()
    end)
  end

  -- auto start
  if config.autoStart then
    self.logger:info("Starting automatically...")
    self:start()
  end

  return self
end

-- 활성화된 플래그들만 반환하므로, 이름을 바꿔주는게 좋을듯..
function Client:getAllToggles()
  local result = {}

  if self.disabled then
    return result
  end

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

function Client:isEnabled(toggleName)
  if not toggleName or string.len(toggleName) == 0 then
    self.logger:error("`toggleName` is required")
    return false
  end

  if self.disabled then
    return false
  end

  local toggle = nil
  for _, t in ipairs(self.toggles) do
    if t.name == toggleName then
      toggle = t
      break
    end
  end

  local enabled = (toggle and toggle.enabled) or false
  self.metricsReporter:count(toggleName, enabled)

  local impressionData = (toggle and toggle.impressionData) or self.impressionDataAll
  if impressionData then
    local event = createImpressionEvent(
      self.context,
      enabled,
      toggleName,
      IMPRESSION_EVENTS.IS_ENABLED,
      (toggle and toggle.impressionData) or nil,
      nil -- variant name is not applicable here
    )
    self:_emit(Events.IMPRESSION, event)
  end

  return enabled
end

function Client:getVariant(toggleName)
  if not toggleName or string.len(toggleName) == 0 then
    self.logger:warn("`featureName` is required")
    return DEFAULT_DISABLED_VARIANT
  end

  if self.disabled then
    return DEFAULT_DISABLED_VARIANT
  end

  local toggle = nil
  for _, t in ipairs(self.toggles) do
    if t.name == toggleName then
      toggle = t
      break
    end
  end

  local enabled = (toggle and toggle.enabled) or false
  local variant = (toggle and toggle.variant) or DEFAULT_DISABLED_VARIANT

  if variant.name then
    self.metricsReporter:countVariant(toggleName, variant.name)
  end

  self.metricsReporter:count(toggleName, enabled)

  local impressionData = (toggle and toggle.impressionData) or self.impressionDataAll
  if impressionData then
    local event = createImpressionEvent(
      self.context,
      enabled,
      toggleName,
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
  if self.disabled then
    return
  end

  callback = callback or function() end

  -- 이미 한번이상 서버에서 플래그들을 가져온 상태일 경우에는 fetchToggles() 만 수행함.
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

function Client:updateContext(context, callback)
  if self.disabled then
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

  self.logger:debug("Context is updated: " .. Json.encode(self.context))

  self:updateToggles(callback)
end

function Client:getContext()
  return Util.deepClone(self.context)
end

function Client:setContextField(field, value)
  if self.disabled then
    return
  end

  -- Predefined fields are stored directly in the context,
  -- while others are stored in properties.
  if isDefinedContextField(field) then
    if value == self.context[field] then
      return
    end

    self.context[field] = value
  else
    if self.context.properties and self.context.properties[field] == value then
      return
    end

    self.context.properties = self.context.properties or {}
    self.context.properties[field] = value
  end

  self:updateToggles()
end

function Client:removeContextField(field)
  if self.disabled then
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

  self:updateToggles(function() end)
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

      self.storage:get(ETAG_KEY, function(etag)
        self.etag = etag
      end)

      self:_loadLastRefreshTimestamp(function(timestamp)
        self.lastRefreshTimestamp = timestamp

        if self.bootstrap and (self.bootstrapOverride or #self.toggles == 0) then
          self.storage:save(TOGGLES_KEY, self.bootstrap, function()
            self.toggles = self.bootstrap
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
  if self.disabled then
    return
  end

  callback = callback or function() end

  self.started = true

  if self.timerRunning then
    self.logger:error("Client has already started, call stop() before restarting.")
    callback()
    return
  end

  self.ready(function()
    self:_initialFetchToggles(function()
      if self.refreshInterval > 0 then
        self.timerRunning = true

        -- 0.5초마다 루프를 돌면서 처리하는 형태로 하는게 좋을듯.

        -- Start the timer loop
        self.timer:async(function()
          -- initial delay
          -- 최신화를 위해서 먼저 가져오는게 맞지 않을까?
          -- 아, 이미 한번 가져온후에 타이머가 시작되므로, 초기 딜레이를 가져가는게 맞다.
          self.timer:sleep(self.refreshInterval)

          while self.timerRunning do
            -- TODO: callback이 호출된 시점에서 sleep을 부여해야함

            -- 마지막으로 fetch한 시간을 기록한 뒤 일정간격 후에만 호출하는 형태로 바꿔주자.
            -- 외부에서 호출할 경우에는 현재 fetching중인지 여부를 구분해서 처리하자.
            self:_fetchToggles(function() end)

            -- sleep은 상황에 맞춰서..
            self.timer:sleep(self.refreshInterval)
          end
        end)
      end

      self.logger:info("Client is started. (environment=`" .. self.context.environment .. "`)")

      callback()
    end)

    self.metricsReporter:start()
  end)
end

function Client:stop()
  if self.disabled then
    return
  end

  if not self.started then
    self.logger:warn("Client is not stated.")
    return
  end

  if self.timerRunning then
    self.timerRunning = false -- Signal the timer thread to stop
    self.timer:tick()         -- Update the timer loop to exit
  end

  self.metricsReporter:stop()

  self.started = false

  self.logger:info("Client is stopped.")
end

function Client:isReady()
  if self.disabled then
    return false
  end

  return self.readyEventEmitted
end

function Client:getError()
  if self.disabled then
    return nil
  end

  return (self.sdkState == 'error' and self.lastError) or nil
end

-- 외부에서 직접 호출할 필요는 없을듯?
-- function Client:sendMetrics()
--   return self.metricsReporter:sendMetrics()
-- end

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
  self:_emit(Events.UPDATE, newToggles)
  self.storage:save(TOGGLES_KEY, newToggles, callback)

  if self.logger:isEnabled(Logger.LogLevel.Verbose) then
    self.logger:debug("Toggles updated: oldToggles=" .. Json.encode(oldToggles))
    self.logger:debug("Toggles updated: newToggles=" .. Json.encode(newToggles))
  end

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
  --   self.logger:debug("Initial enabled toggles: " .. Json.encode(self.toggles))
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
    self.storage:save(self.context.sessionId .. "-" .. LAST_UPDATE_KEY, lastUpdateValue, callback)
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

    callback()
    return
  end

  self:_fetchToggles(callback)
end

function Client:_fetchToggles(callback)
  self.fetching = true

  local isPOST = self.usePOSTrequests
  local url = isPOST and self.url or Util.urlWithContextAsQuery(self.url, self.context)
  local body = isPOST and Json.encode({ context = self.context }) or nil
  local method = isPOST and "POST" or "GET"

  local headers = self:_getHeaders()

  -- Note: When using the POST method, the Content-Length header must be set.
  if isPOST then
    headers["Content-Length"] = body and #body or 0
  end

  if self.logger:isEnabled(Logger.LogLevel.Verbose) then
    self.logger:debug("Fetch feature flags: " .. Json.encode(Util.urlDecode(url)))
  end

  self.request(url, method, headers, body, function(response)
    self.fetching = false

    if self.sdkState == "error" and response.status < 400 then
      self.sdkState = "healthy"
      self:_emit(Events.RECOVERED)

      self.backoffs = 0
    end

    if response.status >= 200 and response.status < 300 then
      self.etag = Util.findCaseInsensitive(response.headers, "ETag") or ""

      local data, err = Json.decode(response.body)
      if not data then
        self.logger:error("JSON decode failed: " .. tostring(err))

        self.sdkState = "error"
        self:_emit(Events.ERROR, { type = "JsonError", message = tostring(err) })
        self.lastError = { type = "JsonError", message = tostring(err) }

        callback()
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

        self:_storeLastRefreshTimestamp(callback)

        self.storage:save(ETAG_KEY, self.etag)
      end)
    elseif response.status == 304 then
      self.logger:debug("[304] No changes in feature flags, using cached data. etag=" .. tostring(self.etag))

      -- REMARKS
      --   etag가 캐싱된 경우, 서버에서 실제로 가져온건 아니지만
      --   이미 최신이므로 가져온걸로 처리해줘야함
      if not self.fetchedFromServer then
        self.fetchedFromServer = true
        self:_setReady()
      end

      self:_storeLastRefreshTimestamp(callback)
    else
      if response.status <= 0 then
        self.logger:warn("Fetching flags did not have an OK response: " .. response.status)
      else
        self.logger:warn("Fetching flags did not have an OK response: " .. response.status .. "\n\n" .. response.body)
      end

      self.sdkState = "error"
      self:_emit(Events.ERROR, { type = "HttpError", code = response.status })
      self.lastError = { type = "HttpError", code = response.status }
      self.backoffs = self.backoffs + 1

      callback()
    end
  end)
end

function Client:_emit(event, ...)
  local argCount = select("#", ...)
  if argCount > 0 then
    self.logger:debug("`" .. event .. "` event is emitted: " .. Json.encode(...))
  else
    self.logger:debug("`" .. event .. "` event is emitted.")
  end

  self.eventEmitter:emit(event, ...)
end

function Client:on(event, callback)
  if self.disabled then
    return
  end

  self.eventEmitter:on(event, callback)
end

function Client:once(event, callback)
  if self.disabled then
    return
  end

  self.eventEmitter:once(event, callback)
end

function Client:off(event, callback)
  if self.disabled then
    return
  end

  self.eventEmitter:off(event, callback)
end

function Client:applyChanges()
  -- 실시간으로 변경된 내용을 외부에서 액세스하는 값에 반영이 되도록 함.

  -- TODO
  -- self.appliedToggles = Util.deepClone(self.toggles)
end

function Client:watch(featureName, callback, ownerWeakref)
  if self.disabled then
    return
  end

  return self.eventSystem:watch(featureName, callback, ownerWeakref)
end

function Client:initAndWatch(featureName, callback, ownerWeakref)
  -- 플래그가 초기화된 상태에서 일괄로 처리해주는게 좋을까?

  local toggle = not self.disabled and _findToggleInArray(self.toggles, featureName)
  if toggle then
    callback(toggle)
  else
    toggle = _makeDisabledToggle(featureName)
    callback(toggle)
  end

  self.logger:info("initAndWatch: feature=`" .. toggle.name .. "`, initialState=" .. tostring(toggle.enabled))

  return self:watch(featureName, callback, ownerWeakref)
end

function Client:unwatch(featureName, callback)
  if self.disabled then
    return
  end

  return self.eventSystem:unwatch(featureName, callback)
end

function Client:tick()
  if self.disabled then
    return
  end

  self.timer:tick()
end

return Client
