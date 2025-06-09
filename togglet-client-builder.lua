-- ToggleClient.New() 함수에 전달할 값들을 채우기 위한 용도이지 Validation은 하지 않는다.
-- ToggleClient.New() 함수에서 Validation을 하기 때문

-- local Validation = require("framework.3rdparty.togglet.validation")
-- local Logging = require("framework.3rdparty.togglet.logging")

local FileStorageProvider = require("framework.3rdparty.togglet.storage-provider-file")
local InMemoryStorageProvider = require("framework.3rdparty.togglet.storage-provider-inmemory")

local M = {}

function M.New()
  local self = setmetatable({}, {
    __index = M,
    __name = "ToggletClientBuilder",
  })

  self.config = {
    appName = "togglet-frontend-client-lua"
  }

  return self
end

function M:AppName(appName)
  self.config.appName = appName
  return self
end

function M:Url(url)
  self.config.url = url
  return self
end

function M:ClientKey(clientKey)
  self.config.clientKey = clientKey
  return self
end

function M:Request(requestFn)
  self.config.request = requestFn
  return self
end

function M:Environment(environment)
  self.config.environment = environment
  return self
end

function M:Context(context)
  self.config.context = context
  return self
end

function M:Bootstrap(bootstrap, bootstrapOverride)
  self.config.bootstrap = bootstrap
  self.config.bootstrapOverride = bootstrapOverride or true
  return self
end

function M:OfflineMode(offlineMode)
  self.config.offlineMode = offlineMode or true
  return self
end

function M:DevMode(devMode)
  self.config.devMode = devMode or true
  return self
end

function M:DisableAutoStart(disable)
  self.config.disableAutoStart = disable or true
  return self
end

function M:ExplicitSyncMode(explicitSync)
  self.config.explicitSyncMode = explicitSync or true
  return self
end

function M:RefreshInterval(interval)
  self.config.refreshInterval = interval
  return self
end

function M:DisableRefresh(disable)
  self.config.disableRefresh = disable or true
  return self
end

function M:MetricsInterval(interval, initialDelay)
  self.config.metricsInterval = interval
  self.config.metricsIntervalInitial = interval
  return self
end

function M:DisableMetrics(disable)
  self.config.disableMetrics = disable or true
  return self
end

function M:ImpressionDataAll(enable)
  self.config.impressionDataAll = enable or true
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
  self.config.headerName = headerName
  return self
end

function M:CustomHeaders(headers)
  self.config.customHeaders = headers
  return self
end

function M:UsePOSTRequests(usePOST)
  self.config.usePOSTrequests = usePOST or true
  return self
end

function M:Experimental(experimental)
  self.config.experimental = experimental
  return self
end

function M:TogglesStorageTTL(ttl)
  if not self.config.experimental then
    self.config.experimental = {}
  end

  self.config.experimental.togglesStorageTTL = ttl
  return self
end

function M:OnError(callback)
  if self.config.onErrorCallbacks then
    table.insert(self.config.onErrorCallbacks, callback)
  else
    self.config.onErrorCallbacks = { callback }
  end
  return self
end

function M:OnInit(callback)
  if self.config.onInitCallbacks then
    table.insert(self.config.onInitCallbacks, callback)
  else
    self.config.onInitCallbacks = { callback }
  end
  return self
end

function M:OnReady(callback)
  if self.config.onReadyCallbacks then
    table.insert(self.config.onReadyCallbacks, callback)
  else
    self.config.onReadyCallbacks = { callback }
  end
  return self
end

function M:OnUpdate(callback)
  if self.config.onUpdateCallbacks then
    table.insert(self.config.onUpdateCallbacks, callback)
  else
    self.config.onUpdateCallbacks = { callback }
  end
  return self
end

function M:OnSent(callback)
  if self.config.onSentCallbacks then
    table.insert(self.config.onSentCallbacks, callback)
  else
    self.config.onSentCallbacks = { callback }
  end
  return self
end

function M:WatchToggle(featureName, callback)
  if not self.config.watchToggles then
    self.config.watchToggles = {
      {
        featureName = featureName,
        callback = callback
      }
    }
  else
    table.insert(self.config.watchToggles, {
      featureName = featureName,
      callback = callback
    })
  end
  return self
end

function M:WatchToggleWithInitialState(featureName, callback)
  if not self.config.watchToggleWithInitialStates then
    self.config.watchToggleWithInitialStates = {
      {
        featureName = featureName,
        callback = callback
      }
    }
  else
    table.insert(self.config.watchToggleWithInitialStates, {
      featureName = featureName,
      callback = callback
    })
  end
  return self
end

function M:UseFileStorage(backupPath, backupPrefix)
  self.config.storageProvider = FileStorageProvider.New(backupPath, backupPrefix)
  return self
end

function M:UseInMemoryStorage()
  self.config.storageProvider = InMemoryStorageProvider.New()
  return self
end

function M:LogSinks(sinks)
  self.config.logSinks = sinks
  return self
end

function M:LogLevel(logLevel)
  self.config.logLevel = logLevel
  return self
end

function M:LogFormatter(formatter)
  self.config.logFormatter = formatter
  return self
end

function M:Build()
  local ToggletClient = require("framework.3rdparty.togglet.togglet-client")
  return ToggletClient.New(self.config)
end

return M
