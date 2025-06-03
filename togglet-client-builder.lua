local Validation = require("framework.3rdparty.togglet.validation")
local Logging = require("framework.3rdparty.togglet.logging")

local M = {}
M.__index = M
M.__name = "ToggletClientBuilder"

function M.New(appName)
  Validation.RequireString(appName, "appName", "ToggletClientBuilder.New")

  local self = setmetatable({}, M)

  self.config = {
    appName = appName
  }

  return self
end

function M:Url(url)
  Validation.RequireString(url, "url", "ToggletClientBuilder:Url")
  self.config.url = url
  return self
end

function M:ClientKey(clientKey)
  Validation.RequireString(clientKey, "clientKey", "ToggletClientBuilder:ClientKey")
  self.config.clientKey = clientKey
  return self
end

function M:Request(requestFn)
  Validation.RequireFunction(requestFn, "requestFn", "ToggletClientBuilder:Request")
  self.config.request = requestFn
  return self
end

function M:Environment(environment)
  Validation.RequireString(environment, "environment", "ToggletClientBuilder:Environment")
  self.config.environment = environment
  return self
end

function M:Context(context)
  Validation.RequireTable(context, "context", "ToggletClientBuilder:Context")
  self.config.context = context
  return self
end

function M:Bootstrap(bootstrap, bootstrapOverride)
  Validation.RequireTable(bootstrap, "bootstrap", "ToggletClientBuilder:Bootstrap")
  self.config.bootstrap = bootstrap
  self.config.bootstrapOverride = override or true
  return self
end

function M:Offline(offline)
  self.config.offline = offline or true
  return self
end

function M:DevMode(devMode)
  self.config.enableDevMode = devMode or true
  return self
end

function M:DisableAutoStart(disable)
  self.config.disableAutoStart = disable or true
  return self
end

function M:ExplicitSyncMode(explicitSync)
  self.config.useExplicitSyncMode = explicitSync or true
  return self
end

function M:RefreshInterval(interval)
  Validation.RequireNumber(interval, "interval", "ToggletClientBuilder:RefreshInterval", 0, 180)
  self.config.refreshInterval = interval
  return self
end

function M:DisableRefresh(disable)
  self.config.disableRefresh = disable or true
  return self
end

function M:DisableMetrics(disable)
  self.config.disableMetrics = disable or true
  return self
end

function M:MetricsIntervalInitial(interval)
  Validation.RequireNumber(interval, "interval", "ToggletClientBuilder:MetricsIntervalInitial", 0, 180)
  self.config.metricsIntervalInitial = interval
  return self
end

function M:MetricsInterval(interval)
  Validation.RequireNumber(interval, "interval", "ToggletClientBuilder:MetricsInterval", 0, 300)
  self.config.metricsInterval = interval
  return self
end

function M:ImpressionDataAll(enable)
  self.config.impressionDataAll = enable or true
  return self
end

-- TODO 로깅시스템 개편과 더불어 수정해줘야함
function M:LoggerFactory(loggerFactory)
  self.config.loggerFactory = loggerFactory
  return self
end

-- TODO 로깅시스템 개편과 더불어 수정해줘야함
function M:LogLevel(logLevel)
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
function M:StorageProvider(storageProvider)
  self.config.storageProvider = storageProvider
  return self
end

function M:Backoff(min, max, factor, jitter)
  self.config.backoff = {
    min = min or 1,
    max = max or 10,
    factor = factor or 2,
    jitter = jitter or 0.2
  }
  return self
end

function M:HeaderName(headerName)
  Validation.RequireString(headerName, "headerName", "ToggletClientBuilder:HeaderName")
  self.config.headerName = headerName
  return self
end

function M:CustomHeaders(headers)
  Validation.RequireTable(headers, "headers", "ToggletClientBuilder:CustomHeaders")
  self.config.customHeaders = headers
  return self
end

function M:UsePOSTRequests(usePOST)
  self.config.usePOSTrequests = usePOST or true
  return self
end

function M:Experimental(experimental)
  Validation.RequireTable(experimental, "experimental", "ToggletClientBuilder:Experimental")
  self.config.experimental = experimental
  return self
end

function M:TogglesStorageTTL(ttl)
  Validation.RequireNumber(ttl, "ttl", "ToggletClientBuilder:TogglesStorageTTL", 0, 3600)

  if not self.config.experimental then
    self.config.experimental = {}
  end

  self.config.experimental.togglesStorageTTL = ttl
  return self
end

function M:OnError(callback)
  if self.onErrorCallbacks then
    table.insert(self.onErrorCallbacks, callback)
  else
    self.onErrorCallbacks = { callback }
  end
  return self
end

function M:OnInit(callback)
  if self.onInitCallbacks then
    table.insert(self.onInitCallbacks, callback)
  else
    self.onInitCallbacks = { callback }
  end
  return self
end

function M:OnReady(callback)
  if self.onReadyCallbacks then
    table.insert(self.onReadyCallbacks, callback)
  else
    self.onReadyCallbacks = { callback }
  end
  return self
end

function M:OnUpdate(callback)
  if self.onUpdateCallbacks then
    table.insert(self.onUpdateCallbacks, callback)
  else
    self.onUpdateCallbacks = { callback }
  end
  return self
end

function M:OnSent(callback)
  if self.onSentCallbacks then
    table.insert(self.onSentCallbacks, callback)
  else
    self.onSentCallbacks = { callback }
  end
  return self
end

function M:WatchToggle(featureName, callback)
  -- TODO
  return self
end

function M:WatchToggleWithInitialState(featureName, callback)
  -- TODO
  return self
end

function M:Build()
  local config = self.config

-- client.New() 에서 체크하니까 여기서 할필요는 없어보임

--  if not config.offline then
--    if not config.url then
--      error("`url` is required when not in offline mode")
--    end
--
--    if not config.clientKey then
--      error("`clientKey` is required when not in offline mode")
--    end
--  end
--
--  if config.offline and not config.bootstrap then
--    error("`bootstrap` data is required in offline mode")
--  end

  local ToggletClient = require("framework.3rdparty.togglet.togglet-client")
  return ToggletClient.New(config)
end

return M
