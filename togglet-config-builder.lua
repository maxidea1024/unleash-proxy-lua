local Validation = require("framework.3rdparty.togglet.validation")
local Logging = require("framework.3rdparty.togglet.logging")

local ToggletConfigBuilder = {}
ToggletConfigBuilder.__index = ToggletConfigBuilder

function ToggletConfigBuilder.New(appName)
  Validation.RequireString(appName, "appName", "ToggletConfigBuilder.New")

  local self = setmetatable({}, ToggletConfigBuilder)

  self.config = {
    appName = appName
  }

  return self
end

function ToggletConfigBuilder:Url(url)
  Validation.RequireString(url, "url", "ToggletConfigBuilder.Url")
  self.config.url = url
  return self
end

function ToggletConfigBuilder:ClientKey(clientKey)
  Validation.RequireString(clientKey, "clientKey", "ToggletConfigBuilder.ClientKey")
  self.config.clientKey = clientKey
  return self
end

function ToggletConfigBuilder:Request(requestFn)
  Validation.RequireFunction(requestFn, "requestFn", "ToggletConfigBuilder.Request")
  self.config.request = requestFn
  return self
end

function ToggletConfigBuilder:Environment(environment)
  Validation.RequireString(environment, "environment", "ToggletConfigBuilder.Environment")
  self.config.environment = environment
  return self
end

function ToggletConfigBuilder:Context(context)
  Validation.RequireTable(context, "context", "ToggletConfigBuilder.Context")
  self.config.context = context
  return self
end

function ToggletConfigBuilder:Bootstrap(bootstrap)
  Validation.RequireTable(bootstrap, "bootstrap", "ToggletConfigBuilder.Bootstrap")
  self.config.bootstrap = bootstrap
  return self
end

function ToggletConfigBuilder:BootstrapOverride(override)
  -- Validation.RequireBoolean(override, "override", "ToggletConfigBuilder.BootstrapOverride")
  self.config.bootstrapOverride = override or true
  return self
end

function ToggletConfigBuilder:Offline(offline)
  -- Validation.RequireBoolean(offline, "offline", "ToggletConfigBuilder.Offline")
  self.config.offline = offline or true
  return self
end

function ToggletConfigBuilder:DevMode(devMode)
  -- Validation.RequireBoolean(devMode, "devMode", "ToggletConfigBuilder.DevMode")
  self.config.enableDevMode = devMode or true
  return self
end

function ToggletConfigBuilder:ExplicitSyncMode(explicitSync)
  -- Validation.RequireBoolean(explicitSync, "explicitSync", "ToggletConfigBuilder.ExplicitSyncMode")
  self.config.useExplicitSyncMode = explicitSync or true
  return self
end

function ToggletConfigBuilder:RefreshInterval(interval)
  Validation.RequireNumber(interval, "interval", "ToggletConfigBuilder.RefreshInterval")
  self.config.refreshInterval = interval
  return self
end

function ToggletConfigBuilder:DisableRefresh(disable)
  -- Validation.RequireBoolean(disable, "disable", "ToggletConfigBuilder.DisableRefresh")
  self.config.disableRefresh = disable or true
  return self
end

function ToggletConfigBuilder:DisableMetrics(disable)
  -- Validation.RequireBoolean(disable, "disable", "ToggletConfigBuilder.DisableMetrics")
  self.config.disableMetrics = disable or true
  return self
end

function ToggletConfigBuilder:MetricsIntervalInitial(interval)
  Validation.RequireNumber(interval, "interval", "ToggletConfigBuilder.MetricsIntervalInitial")
  self.config.metricsIntervalInitial = interval
  return self
end

function ToggletConfigBuilder:MetricsInterval(interval)
  Validation.RequireNumber(interval, "interval", "ToggletConfigBuilder.MetricsInterval")
  self.config.metricsInterval = interval
  return self
end

function ToggletConfigBuilder:ImpressionDataAll(enable)
  -- Validation.RequireBoolean(enable, "enable", "ToggletConfigBuilder.ImpressionDataAll")
  self.config.impressionDataAll = enable or true
  return self
end

function ToggletConfigBuilder:LoggerFactory(loggerFactory)
  self.config.loggerFactory = loggerFactory
  return self
end

function ToggletConfigBuilder:LogLevel(logLevel)
  local level = Logging.LogLevel[logLevel:gsub("^%l", string.upper)]
  if not level then
    error("Invalid log level: " .. tostring(logLevel))
  end

  if not self.config.loggerFactory then
    self.config.loggerFactory = Logging.DefaultLoggerFactory.New(level)
  end

  return self
end

function ToggletConfigBuilder:StorageProvider(storageProvider)
  self.config.storageProvider = storageProvider
  return self
end

function ToggletConfigBuilder:Backoff(min, max, factor, jitter)
  self.config.backoff = {
    min = min or 1,
    max = max or 10,
    factor = factor or 2,
    jitter = jitter or 0.2
  }
  return self
end

function ToggletConfigBuilder:HeaderName(headerName)
  Validation.RequireString(headerName, "headerName", "ToggletConfigBuilder.HeaderName")
  self.config.headerName = headerName
  return self
end

function ToggletConfigBuilder:CustomHeaders(headers)
  Validation.RequireTable(headers, "headers", "ToggletConfigBuilder.CustomHeaders")
  self.config.customHeaders = headers
  return self
end

function ToggletConfigBuilder:UsePOSTRequests(usePOST)
  -- Validation.RequireBoolean(usePOST, "usePOST", "ToggletConfigBuilder.UsePOSTRequests")
  self.config.usePOSTrequests = usePOST or true
  return self
end

function ToggletConfigBuilder:Experimental(experimental)
  Validation.RequireTable(experimental, "experimental", "ToggletConfigBuilder.Experimental")
  self.config.experimental = experimental
  return self
end

function ToggletConfigBuilder:TogglesStorageTTL(ttl)
  Validation.RequireNumber(ttl, "ttl", "ToggletConfigBuilder.TogglesStorageTTL")

  if not self.config.experimental then
    self.config.experimental = {}
  end

  self.config.experimental.togglesStorageTTL = ttl
  return self
end

function ToggletConfigBuilder:Build()
  local config = self.config

  if not config.offline then
    if not config.url then
      error("URL is required when not in offline mode")
    end

    if not config.clientKey then
      error("Client key is required when not in offline mode")
    end

    if not config.request then
      error("Request function is required when not in offline mode")
    end
  end

  if config.offline and not config.bootstrap then
    error("Bootstrap data is required in offline mode")
  end

  setmetatable(config, {
    __index = {
      CreateClient = function()
        local Client = require("framework.3rdparty.togglet.client")
        return Client.New(config)
      end
    }
  })

  return config
end

function ToggletConfigBuilder:NewClient()
  local ToggletClient = require("framework.3rdparty.togglet.togglet-client")
  return ToggletClient.New(self:Build())
end

return ToggletConfigBuilder
