local Validation = require("framework.3rdparty.unleash.validation")
local Logging = require("framework.3rdparty.unleash.logging")

local UnleashConfigBuilder = {}
UnleashConfigBuilder.__index = UnleashConfigBuilder

function UnleashConfigBuilder.New(appName)
  Validation.RequireString(appName, "appName", "UnleashConfigBuilder.New")

  local self = setmetatable({}, UnleashConfigBuilder)

  self.config = {
    appName = appName
  }

  return self
end

function UnleashConfigBuilder:Url(url)
  Validation.RequireString(url, "url", "UnleashConfigBuilder.Url")
  self.config.url = url
  return self
end

function UnleashConfigBuilder:ClientKey(clientKey)
  Validation.RequireString(clientKey, "clientKey", "UnleashConfigBuilder.ClientKey")
  self.config.clientKey = clientKey
  return self
end

function UnleashConfigBuilder:Request(requestFn)
  Validation.RequireFunction(requestFn, "requestFn", "UnleashConfigBuilder.Request")
  self.config.request = requestFn
  return self
end

function UnleashConfigBuilder:Environment(environment)
  Validation.RequireString(environment, "environment", "UnleashConfigBuilder.Environment")
  self.config.environment = environment
  return self
end

function UnleashConfigBuilder:Context(context)
  Validation.RequireTable(context, "context", "UnleashConfigBuilder.Context")
  self.config.context = context
  return self
end

function UnleashConfigBuilder:Bootstrap(bootstrap)
  Validation.RequireTable(bootstrap, "bootstrap", "UnleashConfigBuilder.Bootstrap")
  self.config.bootstrap = bootstrap
  return self
end

function UnleashConfigBuilder:BootstrapOverride(override)
  Validation.RequireBoolean(override, "override", "UnleashConfigBuilder.BootstrapOverride")
  self.config.bootstrapOverride = override
  return self
end

function UnleashConfigBuilder:Offline(offline)
  Validation.RequireBoolean(offline, "offline", "UnleashConfigBuilder.Offline")
  self.config.offline = offline
  return self
end

function UnleashConfigBuilder:DevMode(devMode)
  Validation.RequireBoolean(devMode, "devMode", "UnleashConfigBuilder.DevMode")
  self.config.enableDevMode = devMode
  return self
end

function UnleashConfigBuilder:ExplicitSyncMode(explicitSync)
  Validation.RequireBoolean(explicitSync, "explicitSync", "UnleashConfigBuilder.ExplicitSyncMode")
  self.config.useExplicitSyncMode = explicitSync
  return self
end

function UnleashConfigBuilder:RefreshInterval(interval)
  Validation.RequireNumber(interval, "interval", "UnleashConfigBuilder.RefreshInterval")
  self.config.refreshInterval = interval
  return self
end

function UnleashConfigBuilder:DisableRefresh(disable)
  Validation.RequireBoolean(disable, "disable", "UnleashConfigBuilder.DisableRefresh")
  self.config.disableRefresh = disable
  return self
end

function UnleashConfigBuilder:DisableMetrics(disable)
  Validation.RequireBoolean(disable, "disable", "UnleashConfigBuilder.DisableMetrics")
  self.config.disableMetrics = disable
  return self
end

function UnleashConfigBuilder:MetricsIntervalInitial(interval)
  Validation.RequireNumber(interval, "interval", "UnleashConfigBuilder.MetricsIntervalInitial")
  self.config.metricsIntervalInitial = interval
  return self
end

function UnleashConfigBuilder:MetricsInterval(interval)
  Validation.RequireNumber(interval, "interval", "UnleashConfigBuilder.MetricsInterval")
  self.config.metricsInterval = interval
  return self
end

function UnleashConfigBuilder:ImpressionDataAll(enable)
  Validation.RequireBoolean(enable, "enable", "UnleashConfigBuilder.ImpressionDataAll")
  self.config.impressionDataAll = enable
  return self
end

function UnleashConfigBuilder:LoggerFactory(loggerFactory)
  self.config.loggerFactory = loggerFactory
  return self
end

function UnleashConfigBuilder:LogLevel(logLevel)
  local level = Logging.LogLevel[logLevel:gsub("^%l", string.upper)]
  if not level then
    error("Invalid log level: " .. tostring(logLevel))
  end

  if not self.config.loggerFactory then
    self.config.loggerFactory = Logging.DefaultLoggerFactory.New(level)
  end

  return self
end

function UnleashConfigBuilder:StorageProvider(storageProvider)
  self.config.storageProvider = storageProvider
  return self
end

function UnleashConfigBuilder:Backoff(min, max, factor, jitter)
  self.config.backoff = {
    min = min or 1,
    max = max or 10,
    factor = factor or 2,
    jitter = jitter or 0.2
  }
  return self
end

function UnleashConfigBuilder:HeaderName(headerName)
  Validation.RequireString(headerName, "headerName", "UnleashConfigBuilder.HeaderName")
  self.config.headerName = headerName
  return self
end

function UnleashConfigBuilder:CustomHeaders(headers)
  Validation.RequireTable(headers, "headers", "UnleashConfigBuilder.CustomHeaders")
  self.config.customHeaders = headers
  return self
end

function UnleashConfigBuilder:UsePOSTRequests(usePOST)
  Validation.RequireBoolean(usePOST, "usePOST", "UnleashConfigBuilder.UsePOSTRequests")
  self.config.usePOSTrequests = usePOST
  return self
end

function UnleashConfigBuilder:Experimental(experimental)
  Validation.RequireTable(experimental, "experimental", "UnleashConfigBuilder.Experimental")
  self.config.experimental = experimental
  return self
end

function UnleashConfigBuilder:TogglesStorageTTL(ttl)
  Validation.RequireNumber(ttl, "ttl", "UnleashConfigBuilder.TogglesStorageTTL")

  if not self.config.experimental then
    self.config.experimental = {}
  end

  self.config.experimental.togglesStorageTTL = ttl
  return self
end

function UnleashConfigBuilder:Build()
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
        local Client = require("framework.3rdparty.unleash.client")
        return Client.New(config)
      end
    }
  })

  return config
end

function UnleashConfigBuilder:NewClient()
  local UnleashClient = require("framework.3rdparty.unleash.unleash-client")
  return UnleashClient.New(self:Build())
end

return UnleashConfigBuilder
