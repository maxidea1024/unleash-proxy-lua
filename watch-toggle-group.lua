local M = {}
M.__index = M
M.__name = "WatchToggleGroup"

function M.New(client)
  local self = setmetatable({}, M)
  self.client = client
  self.unregisters = {}
  return self
end

function M:WatchToggle(featureName, callback)
  local unregister = self.client:WatchToggle(featureName, callback)
  table.insert(self.unregisters, unregister)
  return self
end

function M:WatchToggleWithInitialState(featureName, callback)
  local unregister = self.client:WatchToggleWithInitialState(featureName, callback)
  table.insert(self.unregisters, unregister)
  return self
end

function M:UnwatchAll()
  for _, unregister in ipairs(self.unregisters) do
    unregister()
  end
  self.unregisters = {}
end

return M
