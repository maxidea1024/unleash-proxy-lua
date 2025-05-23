-- TODO backoff 처리

local json = require("framework.3rdparty.feature-flags.dkjson")
local util = require("framework.3rdparty.feature-flags.util")
local logger = require("framework.3rdparty.feature-flags.logger")
local ErrorTypes = require("framework.3rdparty.feature-flags.error-types")
local ErrorHelper = require("framework.3rdparty.feature-flags.error-helper")

local MetricsReporter = {}
MetricsReporter.__index = MetricsReporter

function MetricsReporter.New(config)
  if not config.client then error("`client` is required") end
  if not config.appName then error("`appName` is required") end
  if not config.connectionId then error("`connectionId` is required") end
  if not config.url then error("`url` is required") end
  if not config.clientKey then error("`clientKey` is required") end
  if not config.request then error("`request` is required") end
  if not config.loggerFactory then error("`loggerFactory` is required") end

  local self = setmetatable({}, MetricsReporter)
  self.logger = config.loggerFactory:CreateLogger("UnleashMetricsReporter")
  self.client = config.client
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
  self.connectionId = config.connectionId
  self.bucket = self:createEmptyBucket()
  self.timer = config.timer
  self.timerRunning = false
  self.backoffs = 0

  return self
end

function MetricsReporter:Start()
  if self.disabled then
    return false
  end

  if type(self.metricsInterval) == "number" and self.metricsInterval > 0 then
    -- Check for already timer was started.
    if self.timerRunning then
      self.logger:Warn("Timer already running")
      return false
    end

    self.timerRunning = true

    -- TODO timeout으로 변경하자.

    -- self.timer:Async(function()
    --   -- Initial delay before starting the metrics collection
    --   if self.metricsIntervalInitial > 0 then
    --     self.timer:Sleep(self.metricsIntervalInitial)
    --   end

    --   -- Start the metrics collection loop
    --   while self.timerRunning do
    --     self:SendMetrics()
    --     self.timer:Sleep(self.metricsInterval)
    --   end
    -- end)

    return true
  end

  return false
end

function MetricsReporter:Stop()
  if self.timerRunning then
    self.timerRunning = false
    -- self.timer:Tick() -- Update the timer to ensure it stops
  end
end

function MetricsReporter:createEmptyBucket()
  return {
    start = util.Iso8601UtcNowWithMSec(),
    stop = nil,
    toggles = {},
  }
end

function MetricsReporter:getHeaders()
  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
    ["Cache"] = "no-cache",
    [self.headerName] = self.clientKey,
    ["unleash-appname"] = self.appName,
    ["unleash-connection-id"] = self.connectionId,
    ["unleash-sdk"] = self.sdkName,
  }

  -- TODO customHeadersFunction
  for name, value in pairs(self.customHeaders) do
    if value then
      headers[name] = value
    end
  end

  return headers
end

function MetricsReporter:SendMetrics()
  local url = self.url .. "/client/metrics"
  local payload = self:getPayload()

  if util.IsEmptyTable(payload.bucket.toggles) then
    return
  end

  local headers = self:getHeaders()

  if self.logger:IsEnabled(logger.LogLevel.Debug) then
    self.logger:Debug("Sending metrics: " .. json.encode({
      url = url,
      headers = headers,
      payload = payload,
    }))
  end

  local success, jsonBody = pcall(json.encode, payload)
  if not success then
    self.client:emitError(
      ErrorTypes.JSON_ERROR,
      "Failed to encode metrics JSON: " .. tostring(jsonBody),
      "MetricsReporter:SendMetrics",
      logger.LogLevel.Error,
      util.MergeTable({
        payload = payload,
        errorMessage = tostring(jsonBody)
      }, ErrorHelper.GetJsonEncodingErrorDetail(tostring(jsonBody), "payload"))
    )
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

      self.client:emitError(
        ErrorTypes.HTTP_ERROR,
        "Failed to send metrics: " .. response.status,
        "MetricsReporter:SendMetrics",
        logger.LogLevel.Error,
        ErrorHelper.BuildHttpErrorDetail(url, response.status, {
          context = "metrics",
          responseBody = response.body,
          backoffs = self.backoffs,
          retryInfo = {
            currentBackoffs = self.backoffs,
            willRetry = self.backoffs < 10,
            nextRetryDelay = self:calculateNextRetryDelay()
          }
        })
      )
    end
  end)
end

function MetricsReporter:Count(name, enabled)
  if self.disabled or not self.bucket then
    return false
  end

  self:ensureBucketExists(name)

  local yesOrNo = enabled and "yes" or "no"
  self.bucket.toggles[name][yesOrNo] = self.bucket.toggles[name][yesOrNo] + 1
  return true
end

function MetricsReporter:CountVariant(name, variant)
  if self.disabled or not self.bucket then
    return false
  end

  self:ensureBucketExists(name)

  self.bucket.toggles[name].variants[variant] = (self.bucket.toggles[name].variants[variant] or 0) + 1
  return true
end

function MetricsReporter:ensureBucketExists(name)
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

function MetricsReporter:getPayload()
  -- take
  local bucket = {
    start = self.bucket.start,
    stop = util.Iso8601UtcNowWithMSec(),
    toggles = self.bucket.toggles,
  }

  -- reset
  self.bucket = self:createEmptyBucket()

  return {
    bucket = bucket,
    appName = self.appName,
    instanceId = "lua-proxy-client",
  }
end

function MetricsReporter:calculateNextRetryDelay()
  if self.backoffs >= 10 then
    return 0 -- No more retries
  end

  -- Simple exponential backoff calculation
  local baseDelay = 1  -- 1 second base
  local maxDelay = 300 -- 5 minutes max
  local delay = math.min(baseDelay * (2 ^ self.backoffs), maxDelay)

  return delay
end

return MetricsReporter
