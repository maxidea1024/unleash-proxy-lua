local Validation = require("framework.3rdparty.togglet.validation")
local Logging = require("framework.3rdparty.togglet.logging")

local ToggletClientBuilder = {}
ToggletClientBuilder.__index = ToggletClientBuilder

function ToggletClientBuilder.New(appName)
  Validation.RequireString(appName, "appName", "ToggletClientBuilder.New")

  local self = setmetatable({}, ToggletClientBuilder)

  self.config = {
    appName = appName
  }

  return self
end

function ToggletClientBuilder:Url(url)
  Validation.RequireString(url, "url", "ToggletClientBuilder:Url")
  self.config.url = url
  return self
end

function ToggletClientBuilder:ClientKey(clientKey)
  Validation.RequireString(clientKey, "clientKey", "ToggletClientBuilder:ClientKey")
  self.config.clientKey = clientKey
  return self
end

function ToggletClientBuilder:Request(requestFn)
  Validation.RequireFunction(requestFn, "requestFn", "ToggletClientBuilder:Request")
  self.config.request = requestFn
  return self
end

function ToggletClientBuilder:Environment(environment)
  Validation.RequireString(environment, "environment", "ToggletClientBuilder:Environment")
  self.config.environment = environment
  return self
end

function ToggletClientBuilder:Context(context)
  Validation.RequireTable(context, "context", "ToggletClientBuilder:Context")
  self.config.context = context
  return self
end

function ToggletClientBuilder:Bootstrap(bootstrap)
  Validation.RequireTable(bootstrap, "bootstrap", "ToggletClientBuilder:Bootstrap")
  self.config.bootstrap = bootstrap
  return self
end

function ToggletClientBuilder:BootstrapOverride(override)
  self.config.bootstrapOverride = override or true
  return self
end

function ToggletClientBuilder:Offline(offline)
  self.config.offline = offline or true
  return self
end

function ToggletClientBuilder:DevMode(devMode)
  self.config.enableDevMode = devMode or true
  return self
end

function ToggletClientBuilder:DisableAutoStart(disable)
  self.config.disableAutoStart = disable or true
  return self
end

function ToggletClientBuilder:ExplicitSyncMode(explicitSync)
  self.config.useExplicitSyncMode = explicitSync or true
  return self
end

function ToggletClientBuilder:RefreshInterval(interval)
  Validation.RequireNumber(interval, "interval", "ToggletClientBuilder:RefreshInterval", 0, 180)
  self.config.refreshInterval = interval
  return self
end

function ToggletClientBuilder:DisableRefresh(disable)
  self.config.disableRefresh = disable or true
  return self
end

function ToggletClientBuilder:DisableMetrics(disable)
  self.config.disableMetrics = disable or true
  return self
end

function ToggletClientBuilder:MetricsIntervalInitial(interval)
  Validation.RequireNumber(interval, "interval", "ToggletClientBuilder:MetricsIntervalInitial", 0, 180)
  self.config.metricsIntervalInitial = interval
  return self
end

function ToggletClientBuilder:MetricsInterval(interval)
  Validation.RequireNumber(interval, "interval", "ToggletClientBuilder:MetricsInterval", 0, 300)
  self.config.metricsInterval = interval
  return self
end

function ToggletClientBuilder:ImpressionDataAll(enable)
  self.config.impressionDataAll = enable or true
  return self
end

-- TODO 로깅시스템 개편과 더불어 수정해줘야함
function ToggletClientBuilder:LoggerFactory(loggerFactory)
  self.config.loggerFactory = loggerFactory
  return self
end

-- TODO 로깅시스템 개편과 더불어 수정해줘야함
function ToggletClientBuilder:LogLevel(logLevel)
  local level = Logging.LogLevel[logLevel:gsub("^%l", string.upper)]
  if not level then
    error("Invalid log level: " .. tostring(logLevel))
  end

  if not self.config.loggerFactory then
    self.config.loggerFactory = Logging.DefaultLoggerFactory.New(level)
  end

  return self
end

-- TODO 외부로 노출하는게 바람직할까?
function ToggletClientBuilder:StorageProvider(storageProvider)
  self.config.storageProvider = storageProvider
  return self
end

function ToggletClientBuilder:Backoff(min, max, factor, jitter)
  self.config.backoff = {
    min = min or 1,
    max = max or 10,
    factor = factor or 2,
    jitter = jitter or 0.2
  }
  return self
end

function ToggletClientBuilder:HeaderName(headerName)
  Validation.RequireString(headerName, "headerName", "ToggletClientBuilder:HeaderName")
  self.config.headerName = headerName
  return self
end

function ToggletClientBuilder:CustomHeaders(headers)
  Validation.RequireTable(headers, "headers", "ToggletClientBuilder:CustomHeaders")
  self.config.customHeaders = headers
  return self
end

function ToggletClientBuilder:UsePOSTRequests(usePOST)
  self.config.usePOSTrequests = usePOST or true
  return self
end

function ToggletClientBuilder:Experimental(experimental)
  Validation.RequireTable(experimental, "experimental", "ToggletClientBuilder:Experimental")
  self.config.experimental = experimental
  return self
end

function ToggletClientBuilder:TogglesStorageTTL(ttl)
  Validation.RequireNumber(ttl, "ttl", "ToggletClientBuilder:TogglesStorageTTL", 0, 3600)

  if not self.config.experimental then
    self.config.experimental = {}
  end

  self.config.experimental.togglesStorageTTL = ttl
  return self
end

function ToggletClientBuilder:OnError(callback)
  if self.onErrorCallbacks then
    table.insert(self.onErrorCallbacks, callback)
  else
    self.onErrorCallbacks = { callback }
  end
  return self
end

function ToggletClientBuilder:OnInit(callback)
  if self.onInitCallbacks then
    table.insert(self.onInitCallbacks, callback)
  else
    self.onInitCallbacks = { callback }
  end
  return self
end

function ToggletClientBuilder:OnReady(callback)
  if self.onReadyCallbacks then
    table.insert(self.onReadyCallbacks, callback)
  else
    self.onReadyCallbacks = { callback }
  end
  return self
end

function ToggletClientBuilder:OnUpdate(callback)
  if self.onUpdateCallbacks then
    table.insert(self.onUpdateCallbacks, callback)
  else
    self.onUpdateCallbacks = { callback }
  end
  return self
end

function ToggletClientBuilder:OnSent(callback)
  if self.onSentCallbacks then
    table.insert(self.onSentCallbacks, callback)
  else
    self.onSentCallbacks = { callback }
  end
  return self
end

function ToggletClientBuilder:WatchToggle(featureName, callback)
  -- TODO
  return self
end

function ToggletClientBuilder:Build()
  local config = self.config

  if not config.offline then
    if not config.url then
      error("`url` is required when not in offline mode")
    end

    if not config.clientKey then
      error("`clientKey` is required when not in offline mode")
    end
  end

  if config.offline and not config.bootstrap then
    error("`bootstrap` data is required in offline mode")
  end

  local ToggletClient = require("framework.3rdparty.togglet.togglet-client")
  return ToggletClient.New(config)
end

return ToggletClientBuilder
