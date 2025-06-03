-- TODO backoff 처리

local Json = require("framework.3rdparty.togglet.dkjson")
local Util = require("framework.3rdparty.togglet.util")
local Logging = require("framework.3rdparty.togglet.logging")
local ErrorTypes = require("framework.3rdparty.togglet.error-types")
local ErrorHelper = require("framework.3rdparty.togglet.error-helper")
local Validation = require("framework.3rdparty.togglet.validation")
local Timer = require("framework.3rdparty.togglet.timer")
local Promise = require("framework.3rdparty.togglet.promise")

local M = {}
M.__index = M
M.__name = "MetricsReporter"

function M.New(config)
  Validation.RequireTable(config, "config", "M.New")
  Validation.RequireField(config, "client", "config", "M.New")
  Validation.RequireField(config, "appName", "config", "M.New")
  Validation.RequireField(config, "connectionId", "config", "M.New")
  Validation.RequireField(config, "url", "config", "M.New")
  Validation.RequireField(config, "clientKey", "config", "M.New")
  Validation.RequireField(config, "request", "config", "M.New")
  Validation.RequireField(config, "loggerFactory", "config", "M.New")

  if config.metricsInterval ~= nil then
    Validation.RequireNumber(config.metricsInterval, "config.metricsInterval", "M.New", 0)
  end

  if config.metricsIntervalInitial ~= nil then
    Validation.RequireNumber(config.metricsIntervalInitial, "config.metricsIntervalInitial", "M.New", 0)
  end

  if config.disableMetrics ~= nil then
    Validation.RequireBoolean(config.disableMetrics, "config.disableMetrics", "M.New")
  end

  if config.customHeaders ~= nil then
    Validation.RequireTable(config.customHeaders, "config.customHeaders", "M.New")
  end

  if config.onSent ~= nil then
    Validation.RequireFunction(config.onSent, "config.onSent", "M.New")
  end

  local self = setmetatable({}, M)
  self.logger = config.loggerFactory:CreateLogger("MetricsReporter")
  self.client = config.client
  self.onSent = config.onSent or function() end
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
  self.timerRunning = false
  self.backoffs = 0

  return self
end

function M:Start()
  if type(self.metricsInterval) == "number" and self.metricsInterval > 0 then
    -- Check for already timer was started.
    if self.timerRunning then
      self.logger:Warn("Timer already running")
      return Promise.Completed()
    end

    self.timerRunning = true

    -- TODO timeout으로 변경하자.

    Timer.Async(function()
      -- Initial delay before starting the metrics collection
      if self.metricsIntervalInitial > 0 then
        Timer.Sleep(self.metricsIntervalInitial)
      end

      -- Start the metrics collection loop
      while self.timerRunning do
        self:SendMetrics()
        Timer.Sleep(self.metricsInterval)
      end
    end)

    return Promise.Completed()
  end

  return Promise.Completed()
end

function M:Stop()
  self.timerRunning = false
  return Promise.Completed()
end

function M:createEmptyBucket()
  return {
    start = Util.Iso8601UtcNowWithMSec(),
    stop = nil,
    toggles = {},
  }
end

function M:getHeaders()
  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
    ["Cache"] = "no-cache",
    [self.headerName] = self.clientKey,
    ["unleash-appname"] = self.appName,
    ["unleash-connection-id"] = self.connectionId,
    ["unleash-sdk"] = self.sdkName,
  }

  for name, value in pairs(self.customHeaders) do
    if value then
      headers[name] = value
    end
  end

  return headers
end

function M:SendMetrics()
  local url = self.url .. "/client/metrics"
  local payload = self:getPayload()

  if Util.IsEmptyTable(payload.bucket.toggles) then
    return Promise.Completed()
  end

  local headers = self:getHeaders()

  if self.logger:IsEnabled(Logging.LogLevel.Debug) then
    self.logger:Debug("Sending metrics: " .. Json.encode({
      url = url,
      headers = headers,
      payload = payload,
    }))
  end

  local success, jsonBody = pcall(Json.encode, payload)
  if not success then
    local error = self.client:emitError(
      ErrorTypes.JSON_ERROR,
      "Failed to encode metrics JSON: " .. tostring(jsonBody),
      "M:SendMetrics",
      Logging.LogLevel.Error,
      Util.MergeTable({
        payload = payload,
        errorMessage = tostring(jsonBody)
      }, ErrorHelper.GetJsonEncodingErrorDetail(tostring(jsonBody), "payload"))
    )
    return Promise.FromError(error)
  end

  -- Note: When using the POST method, you must specify the Content-Length
  headers["Content-Length"] = tostring(#jsonBody)

  local promise = Promise.New()
  self.request(url, "POST", headers, jsonBody, function(response)
    promise:Resolve()

    if response.status >= 200 and response.status < 300 then
      self.backoffs = 0

      self.onSent(payload)
    else
      self.backoffs = self.backoffs + 1

      self.client:emitError(
        ErrorTypes.HTTP_ERROR,
        "Failed to send metrics: " .. response.status,
        "M:SendMetrics",
        Logging.LogLevel.Error,
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

  return promise
end

function M:Count(name, enabled)
  self:ensureBucketExists(name)

  local yesOrNo = enabled and "yes" or "no"
  self.bucket.toggles[name][yesOrNo] = self.bucket.toggles[name][yesOrNo] + 1
  return true
end

function M:CountVariant(name, variant)
  self:ensureBucketExists(name)

  self.bucket.toggles[name].variants[variant] = (self.bucket.toggles[name].variants[variant] or 0) + 1
  return true
end

function M:ensureBucketExists(name)
  if not self.bucket.toggles[name] then
    self.bucket.toggles[name] = {
      yes = 0,
      no = 0,
      variants = setmetatable({}, { __jsontype = 'object' }), -- Must be recognized as an object, not an array.
    }
  end
  return true
end

function M:getPayload()
  -- take
  local bucket = {
    start = self.bucket.start,
    stop = Util.Iso8601UtcNowWithMSec(),
    toggles = self.bucket.toggles,
  }

  -- reset
  self.bucket = self:createEmptyBucket()

  return {
    bucket = bucket,
    appName = self.appName,
    instanceId = "lua-proxy-client", -- CHECKME 이게 맞는걸까?
  }
end

function M:calculateNextRetryDelay()
  if self.backoffs >= 10 then
    return 0 -- No more retries
  end

  -- Simple exponential backoff calculation
  local baseDelay = 1  -- 1 second base
  local maxDelay = 300 -- 5 minutes max
  local delay = math.min(baseDelay * (2 ^ self.backoffs), maxDelay)

  return delay
end

return M
