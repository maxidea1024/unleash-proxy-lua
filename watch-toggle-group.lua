local M = {}

function M.New(client, name)
  local self = setmetatable({}, M)
  self.client = client
  self.name = name
  self.unregisters = {}

  return _G.setmetatable_gc(self, {
    __index = M,
    __tostring = function() return "WatchToggleGroup:" .. name end,
    __gc = function(instance)
      -- Stop() 호출 이후에 gc 정리가 일어나게 되면, 문제가 발생할수 있음.
      -- gc 발생시 처리를 제거하고 Stop() 함수에서 정리하는 형태로 변경하는게 좋을듯.
      if instance.unregisters then
        instance:UnwatchAll()
      end
    end
  })
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
  self.client.logger:Debug("👀 WatchToggleGroup:UnwatchAll: name=`%s`", self.name)

  for _, unregister in ipairs(self.unregisters) do
    unregister()
  end
  self.unregisters = {}
end

function M:Destroy()
  self:UnwatchAll()
end

return M
