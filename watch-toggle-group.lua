local WatchToggleGroup = {}
WatchToggleGroup.__index = WatchToggleGroup

function WatchToggleGroup.New(client)
  local self = setmetatable({}, WatchToggleGroup)
  self.client = client
  self.unregisters = {}
  return self
end

function WatchToggleGroup:WatchToggle(featureName, callback)
  self.client:WatchToggle(featureName, callback)
  return self
end

function WatchToggleGroup:WatchToggleWithInitialState(featureName, callback)
  self.client:WatchToggleWithInitialState(featureName, callback)
  return self
end

function WatchToggleGroup:UnwatchAll()
  for _, unregister ipairs(self.unregisters) do
    unregister()
  end
  self.unregisters = {}
end

return WatchToggleGroup
