local function createCaseInsensitiveTable()
  local t = {}
  local data = {}
  local mt = {
    __index = function(_, key)
      if type(key) == "string" then
        return data[key:lower()]
      end
      return data[key]
    end,
    __newindex = function(_, key, value)
      if type(key) == "string" then
        data[key:lower()] = value
      else
        data[key] = value
      end
    end
  }
  setmetatable(t, mt)
  return t
end

local function createWeakTable()
  local t = {}
  setmetatable(t, { __mode = "v" })
  return t
end

local EventSystem = {}
EventSystem.__index = EventSystem

function EventSystem.New(loggerFactory)
  local self = setmetatable({}, EventSystem)
  self.logger = loggerFactory:CreateLogger("UnleashEventSystem")
  self.events = createCaseInsensitiveTable()
  return self
end

function EventSystem:Watch(eventName, callback, ownerWeakref)
  if type(eventName) ~= "string" then
    self.logger:Error("`eventName` must be a string")
  end

  if type(callback) ~= "function" then
    self.logger:Error("`callback` must be a function")
  end

  if not self.events[eventName] then
    self.events[eventName] = createWeakTable()
  end

  local entry = {
    callback = callback,
    hasOwnerWeakref = ownerWeakref ~= nil,
    ownerWeakref = ownerWeakref -- Optional object managed as a weak reference
  }

  table.insert(self.events[eventName], entry)

  return function()
    self:Unwatch(eventName, callback)
  end
end

function EventSystem:Unwatch(eventName, callback)
  if type(eventName) ~= "string" then
    self.logger:Error("`eventName` must be a string")
  end

  if type(callback) ~= "function" then
    self.logger:Error("`callback` must be a function")
  end

  local callbacks = self.events[eventName]
  if callbacks then
    for i, entry in ipairs(callbacks) do
      if entry.callback == callback then
        table.remove(callbacks, i)
        return true
      end
    end
  end
  return false
end

function EventSystem:IsWatching(eventName, callback)
  if type(eventName) ~= "string" then
    self.logger:Error("`eventName` must be a string")
  end

  if type(callback) ~= "function" then
    self.logger:Error("`callback` must be a function")
  end

  local callbacks = self.events[eventName]
  if callbacks then
    for _, entry in ipairs(callbacks) do
      if entry.callback == callback then
        return true
      end
    end
  end
  return false
end

function EventSystem:IsWatchingEvent(eventName)
  if type(eventName) ~= "string" then
    self.logger:Error("`eventName` must be a string")
  end

  local callbacks = self.events[eventName]
  return callbacks and #callbacks > 0
end

function EventSystem:Emit(eventName, ...)
  if type(eventName) ~= "string" then
    self.logger:Error("`eventName` must be a string")
  end

  self.logger:Debug("Emit event: `" .. eventName .. "`")

  local callbacks = self.events[eventName]
  if callbacks then
    local activeCallbacks = {}
    for _, entry in ipairs(callbacks) do
      if entry.callback and (not entry.hasOwnerWeakref or entry.ownerWeakref ~= nil) then
        table.insert(activeCallbacks, entry.callback)
      end
    end

    for _, cb in ipairs(activeCallbacks) do
      cb(...)
    end

    local i = 1
    while i <= #callbacks do
      local entry = callbacks[i]
      if entry.callback == nil or (entry.hasOwnerWeakref and entry.ownerWeakref == nil) then
        table.remove(callbacks, i)
      else
        i = i + 1
      end
    end

    if #callbacks == 0 then
      self.events[eventName] = nil
    end
  end
end

return EventSystem
