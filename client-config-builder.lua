local Validation = require("framework.3rdparty.feature-flags.validation")
local Logger = require("framework.3rdparty.feature-flags.logger")

local ClientConfigBuilder = {}
ClientConfigBuilder.__index = ClientConfigBuilder

function ClientConfigBuilder.New(appName)
  Validation.RequireString(appName, "appName", "ClientConfigBuilder.New")

  local self = setmetatable({}, ClientConfigBuilder)

  self.config = {
    appName = appName
  }

  return self
end

function ClientConfigBuilder:Url(url)
  Validation.RequireString(url, "url", "ClientConfigBuilder.Url")
  self.config.url = url
  return self
end

function ClientConfigBuilder:ClientKey(clientKey)
  Validation.RequireString(clientKey, "clientKey", "ClientConfigBuilder.ClientKey")
  self.config.clientKey = clientKey
  return self
end

function ClientConfigBuilder:Request(requestFn)
  Validation.RequireFunction(requestFn, "requestFn", "ClientConfigBuilder.Request")
  self.config.request = requestFn
  return self
end

function ClientConfigBuilder:Environment(environment)
  Validation.RequireString(environment, "environment", "ClientConfigBuilder.Environment")
  self.config.environment = environment
  return self
end

function ClientConfigBuilder:Context(context)
  Validation.RequireTable(context, "context", "ClientConfigBuilder.Context")
  self.config.context = context
  return self
end

function ClientConfigBuilder:Bootstrap(bootstrap)
  Validation.RequireTable(bootstrap, "bootstrap", "ClientConfigBuilder.Bootstrap")
  self.config.bootstrap = bootstrap
  return self
end

function ClientConfigBuilder:BootstrapOverride(override)
  Validation.RequireBoolean(override, "override", "ClientConfigBuilder.BootstrapOverride")
  self.config.bootstrapOverride = override
  return self
end

function ClientConfigBuilder:Offline(offline)
  Validation.RequireBoolean(offline, "offline", "ClientConfigBuilder.Offline")
  self.config.offline = offline
  return self
end

function ClientConfigBuilder:DevMode(devMode)
  Validation.RequireBoolean(devMode, "devMode", "ClientConfigBuilder.DevMode")
  self.config.enableDevMode = devMode
  return self
end

function ClientConfigBuilder:ExplicitSyncMode(explicitSync)
  Validation.RequireBoolean(explicitSync, "explicitSync", "ClientConfigBuilder.ExplicitSyncMode")
  self.config.useExplicitSyncMode = explicitSync
  return self
end

function ClientConfigBuilder:RefreshInterval(interval)
  Validation.RequireNumber(interval, "interval", "ClientConfigBuilder.RefreshInterval")
  self.config.refreshInterval = interval
  return self
end

function ClientConfigBuilder:DisableRefresh(disable)
  Validation.RequireBoolean(disable, "disable", "ClientConfigBuilder.DisableRefresh")
  self.config.disableRefresh = disable
  return self
end

function ClientConfigBuilder:DisableMetrics(disable)
  Validation.RequireBoolean(disable, "disable", "ClientConfigBuilder.DisableMetrics")
  self.config.disableMetrics = disable
  return self
end

function ClientConfigBuilder:MetricsIntervalInitial(interval)
  Validation.RequireNumber(interval, "interval", "ClientConfigBuilder.MetricsIntervalInitial")
  self.config.metricsIntervalInitial = interval
  return self
end

function ClientConfigBuilder:MetricsInterval(interval)
  Validation.RequireNumber(interval, "interval", "ClientConfigBuilder.MetricsInterval")
  self.config.metricsInterval = interval
  return self
end

function ClientConfigBuilder:ImpressionDataAll(enable)
  Validation.RequireBoolean(enable, "enable", "ClientConfigBuilder.ImpressionDataAll")
  self.config.impressionDataAll = enable
  return self
end

function ClientConfigBuilder:LoggerFactory(loggerFactory)
  self.config.loggerFactory = loggerFactory
  return self
end

function ClientConfigBuilder:LogLevel(logLevel)
  local level = Logger.LogLevel[logLevel:gsub("^%l", string.upper)]
  if not level then
    error("Invalid log level: " .. tostring(logLevel))
  end

  if not self.config.loggerFactory then
    self.config.loggerFactory = Logger.DefaultLoggerFactory.New(level)
  end

  return self
end

function ClientConfigBuilder:StorageProvider(storageProvider)
  self.config.storageProvider = storageProvider
  return self
end

function ClientConfigBuilder:Backoff(min, max, factor, jitter)
  self.config.backoff = {
    min = min or 1,
    max = max or 10,
    factor = factor or 2,
    jitter = jitter or 0.2
  }
  return self
end

function ClientConfigBuilder:HeaderName(headerName)
  Validation.RequireString(headerName, "headerName", "ClientConfigBuilder.HeaderName")
  self.config.headerName = headerName
  return self
end

function ClientConfigBuilder:CustomHeaders(headers)
  Validation.RequireTable(headers, "headers", "ClientConfigBuilder.CustomHeaders")
  self.config.customHeaders = headers
  return self
end

function ClientConfigBuilder:UsePOSTRequests(usePOST)
  Validation.RequireBoolean(usePOST, "usePOST", "ClientConfigBuilder.UsePOSTRequests")
  self.config.usePOSTrequests = usePOST
  return self
end

function ClientConfigBuilder:Experimental(experimental)
  Validation.RequireTable(experimental, "experimental", "ClientConfigBuilder.Experimental")
  self.config.experimental = experimental
  return self
end

function ClientConfigBuilder:TogglesStorageTTL(ttl)
  Validation.RequireNumber(ttl, "ttl", "ClientConfigBuilder.TogglesStorageTTL")

  if not self.config.experimental then
    self.config.experimental = {}
  end

  self.config.experimental.togglesStorageTTL = ttl
  return self
end

function ClientConfigBuilder:Build()
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
        local Client = require("framework.3rdparty.feature-flags.client")
        return Client.New(config)
      end
    }
  })

  return config
end

function ClientConfigBuilder:CreateClient()
  local Client = require("framework.3rdparty.feature-flags.client")
  return Client.New(self:Build())
end

return ClientConfigBuilder

