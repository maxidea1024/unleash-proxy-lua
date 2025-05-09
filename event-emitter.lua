------------------------------------------------------------------------------
-- EventEmitter Class in Node.js Style
-- LICENSE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------

local PREFIX = "__listener__"
local PREFIX_LENGTH = #PREFIX
local DEFAULT_MAX_LISTENERS = 10

local EventEmitter = {}
EventEmitter.__index = EventEmitter

local function removeEntry(t, pred)
  local x, len = 0, #t
  for i = 1, len do
    local trusy, index = false, (i - x)
    if (type(pred) == "function") then
      trusy = pred(t[index])
    else
      trusy = t[index] == pred
    end

    if (t[index] ~= nil and trusy) then
      t[index] = nil
      table.remove(t, index)
      x = x + 1
    end
  end

  return t
end

function EventEmitter.new(loggerFactory)
  local self = setmetatable({}, EventEmitter)
  self.logger = loggerFactory:createLogger("FFEventEmitter")
  self._on = {}
  return self
end

function EventEmitter:getSafeEventTable(event)
  if type(self._on[event]) ~= "table" then
    self._on[event] = {}
  end

  return self._on[event]
end

function EventEmitter:getEventTable(event)
  return self._on[event]
end

function EventEmitter:addListener(event, listener)
  local eventPrefix = PREFIX .. tostring(event)
  local eventTable = self:getSafeEventTable(eventPrefix)
  local maxListeners = self.currentMaxListeners or DEFAULT_MAX_LISTENERS
  local listenerCount = self:listenerCount(event)
  table.insert(eventTable, listener)

  if listenerCount > maxListeners then
    self.logger:warn("Number of " ..
    string.sub(eventPrefix, PREFIX_LENGTH + 1) .. " event listeners: " .. tostring(listenerCount))
  end

  return self
end

function EventEmitter:on(event, listener)
  self:addListener(event, listener)
end

function EventEmitter:once(event, listener)
  local eventPrefix = PREFIX .. tostring(event) .. ":once"
  local eventTable = self:getSafeEventTable(eventPrefix)
  local maxListeners = self.currentMaxListeners or DEFAULT_MAX_LISTENERS
  local listenerCount = self:listenerCount(event)
  if listenerCount > maxListeners then
    self.logger:warn("Number of " .. event .. " event listeners: " .. tostring(listenerCount))
  end

  table.insert(eventTable, listener)
  return self
end

function EventEmitter:off(event, listener)
  if listener == nil then
    return self:removeAllListeners(event)
  else
    self:removeListener(event, listener)
  end
end

function EventEmitter:emit(event, ...)
  local eventPrefix = PREFIX .. tostring(event)
  local eventTable = self:getEventTable(eventPrefix)
  if eventTable ~= nil then
    for _, listener in ipairs(eventTable) do
      local status, error = pcall(listener, ...)
      if not (status) then
        self.logger:error(string.sub(_, PREFIX_LENGTH + 1) .. " emit error: " .. tostring(error))
      end
    end
  end

  -- one-time listener
  eventPrefix = eventPrefix .. ":once"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable ~= nil then
    for _, listener in ipairs(eventTable) do
      local status, error = pcall(listener, ...)
      if not status then
        self.logger:error(string.sub(_, PREFIX_LENGTH + 1) .. " emit error: " .. tostring(error))
      end
    end

    -- once 인 경우에는 이벤트를 한번만 수신하고 listener자체를 제거한다.
    removeEntry(eventTable, function(v) return v ~= nil end)
    self._on[eventPrefix] = nil
  end

  return self
end

function EventEmitter:getMaxListeners()
  return self.currentMaxListeners or self.defaultMaxListeners
end

function EventEmitter:listenerCount(event)
  local totalNum = 0
  local eventPrefix = PREFIX .. tostring(event)
  local eventTable = self:getEventTable(eventPrefix)

  if eventTable ~= nil then
    totalNum = totalNum + #eventTable
  end

  eventPrefix = eventPrefix .. ":once"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable ~= nil then
    totalNum = totalNum + #eventTable
  end

  return totalNum
end

function EventEmitter:listeners(event)
  local eventPrefix = PREFIX .. tostring(event)
  local eventTable = self:getEventTable(eventPrefix)
  local clone = {}

  if eventTable ~= nil then
    for i, listener in ipairs(eventTable) do
      table.insert(clone, listener)
    end
  end

  eventPrefix = eventPrefix .. ":once"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable ~= nil then
    for i, listener in ipairs(eventTable) do
      table.insert(clone, listener)
    end
  end

  return clone
end

function EventEmitter:removeAllListeners(event)
  if event ~= nil then
    local eventPrefix = PREFIX .. tostring(event)
    local eventTable = self:getSafeEventTable(eventPrefix)
    removeEntry(eventTable, function(v) return v ~= nil end)

    eventPrefix = eventPrefix .. ":once"
    eventTable = self:getSafeEventTable(eventPrefix)
    removeEntry(eventTable, function(v) return v ~= nil end)
    self._on[eventPrefix] = nil
  else
    for eventPrefix, t in pairs(self._on) do
      self:removeAllListeners(string.sub(eventPrefix, PREFIX_LENGTH + 1))
    end
  end

  for eventPrefix, listeners in pairs(self._on) do
    if #listeners == 0 then
      self._on[eventPrefix] = nil
    end
  end

  return self
end

function EventEmitter:removeListener(event, listener)
  local eventPrefix = PREFIX .. tostring(event)
  local eventTable = self:getSafeEventTable(eventPrefix)
  if listener == nil then
    self.logger:error("listener is nil")
    return self
  end

  -- normal listener
  removeEntry(eventTable, listener)
  if #eventTable == 0 then
    self._on[eventPrefix] = nil
  end

  -- emit-once listener
  eventPrefix = eventPrefix .. ":once"
  eventTable = self:getSafeEventTable(eventPrefix)
  removeEntry(eventTable, listener)
  if #eventTable == 0 then
    self._on[eventPrefix] = nil
  end

  return self
end

function EventEmitter:setMaxListeners(n)
  self.currentMaxListeners = n
  return self
end

return EventEmitter
