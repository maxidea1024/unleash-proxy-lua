-- TODO backoff 처리

local json = require("framework.3rdparty.feature-flags.dkjson")
local util = require("framework.3rdparty.feature-flags.util")

local MetricsReporter = {}
MetricsReporter.__index = MetricsReporter

function MetricsReporter.new(config)
  if not config.onError then error("`onError` is required") end
  if not config.appName then error("`appName` is required") end
  if not config.url then error("`url` is required") end
  if not config.clientKey then error("`clientKey` is required") end
  if not config.request then error("`request` is required") end
  if not config.loggerFactory then error("`loggerFactory` is required") end

  local self = setmetatable({}, MetricsReporter)
  self.logger = config.loggerFactory:createLogger("MetricsReporter")
  self.onError = config.onError
  self.onSent = config.onSent or function() end
  self.disabled = config.disableMetrics or false
  self.metricsInterval = config.metricsInterval or 30
  self.metricsIntervalInitial = config.metricsIntervalInitial or 10
  self.appName = config.appName
  self.url = config.url
  self.request = config.request
  self.clientKey = config.clientKey
  self.headerName = config.headerName or "Authorization"
  self.customHeaders = config.customHeaders or {}
  self.bucket = self:_createEmptyBucket()
  self.timer = config.timer
  self.timerRunning = false
  self.backoffs = 0

  return self
end

function MetricsReporter:start()
  if self.disabled then
    return false
  end

  if type(self.metricsInterval) == "number" and self.metricsInterval > 0 then
    -- Check for already timer was started.
    if self.timerRunning then
      self.logger:warn("Timer already running")
      return false
    end

    self.timerRunning = true

    -- timeout으로 변경하자.

    self.timer:async(function()
      -- Initial delay before starting the metrics collection
      if self.metricsIntervalInitial > 0 then
        self.timer:sleep(self.metricsIntervalInitial)
      end

      -- Start the metrics collection loop
      while self.timerRunning do
        self:sendMetrics()
        self.timer:sleep(self.metricsInterval)
      end
    end)

    return true
  end

  return false
end

function MetricsReporter:stop()
  if self.timerRunning then
    self.timerRunning = false
    -- self.timer:tick() -- Update the timer to ensure it stops
  end
end

function MetricsReporter:_createEmptyBucket()
  return {
    start = util.iso8601UtcNowWithMSec(),
    stop = nil,
    toggles = {},
  }
end

function MetricsReporter:_getHeaders()
  local headers = {
    [self.headerName] = self.clientKey,
    Accept = "application/json",
    ["Content-Type"] = "application/json",
  }

  -- TODO customHeadersFunction
  for name, value in pairs(self.customHeaders) do
    if value then
      headers[name] = value
    end
  end

  return headers
end

function MetricsReporter:sendMetrics()
  local url = self.url .. "/client/metrics"
  local payload = self:_getPayload()

  if util.isEmptyTable(payload.bucket.toggles) then
    return
  end

  local headers = self:_getHeaders()

  self.logger:debug("Sending metrics: " .. json.encode({
    url = url,
    headers = headers,
    payload = payload,
  }))

  local success, jsonBody = pcall(json.encode, payload)
  if not success then
    self.logger:error("Failed to encode JSON: " .. tostring(jsonBody))
    self.onError(jsonBody)
    return
  end

  -- Note: When using the POST method, you must specify the Content-Length
  headers["Content-Length"] = tostring(#jsonBody)

  self.request(url, "POST", headers, jsonBody, function(response)
    if response.status >= 200 and response.status < 300 then
      self.backoffs = 0

      self.onSent(payload)
    else
      self.backoffs = self.backoffs + 1

      self.onError({
        type = "HttpError",
        code = response.status,
        message = response.body
      })
    end
  end)
end

function MetricsReporter:count(name, enabled)
  if self.disabled or not self.bucket then
    return false
  end

  self:_ensureBucketExists(name)

  local yesOrNo = enabled and "yes" or "no"
  self.bucket.toggles[name][yesOrNo] = self.bucket.toggles[name][yesOrNo] + 1
  return true
end

function MetricsReporter:countVariant(name, variant)
  if self.disabled or not self.bucket then
    return false
  end

  self:_ensureBucketExists(name)

  self.bucket.toggles[name].variants[variant] = (self.bucket.toggles[name].variants[variant] or 0) + 1
  return true
end

function MetricsReporter:_ensureBucketExists(name)
  if self.disabled or not self.bucket then
    return false
  end

  if not self.bucket.toggles[name] then
    self.bucket.toggles[name] = {
      yes = 0,
      no = 0,
      variants = setmetatable({}, { __jsontype = 'object' }), -- Must be recognized as an object, not an array.
    }
  end

  return true
end

function MetricsReporter:_getPayload()
  -- take
  local bucket = {
    start = self.bucket.start,
    stop = util.iso8601UtcNowWithMSec(),
    toggles = self.bucket.toggles,
  }

  -- reset
  self.bucket = self:_createEmptyBucket()

  return {
    bucket = bucket,
    appName = self.appName,
    instanceId = "lua-proxy-client",
  }
end

return MetricsReporter
