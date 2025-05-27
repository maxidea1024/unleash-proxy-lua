local ErrorTypes = require("framework.3rdparty.togglet.error-types")

local PREFIX = "__listener__"
local PREFIX_LENGTH = #PREFIX
local DEFAULT_MAX_LISTENERS = 10

local EventEmitter = {}
EventEmitter.__index = EventEmitter

local function removeEntry(t, pred)
  local i = 1
  while i <= #t do
    local trusy = false
    if type(pred) == "function" then
      trusy = pred(t[i])
    else
      trusy = t[i] == pred
    end

    if trusy then
      table.remove(t, i)
    else
      i = i + 1
    end
  end

  return t
end

local function normalizeEventName(event)
  return PREFIX .. tostring(event)
end

local eventNameCache = setmetatable({}, { __mode = "k" })

local function getCachedEventName(event)
  local cached = eventNameCache[event]
  if not cached then
    cached = normalizeEventName(event)
    eventNameCache[event] = cached
  end
  return cached
end

function EventEmitter.New(config)
  local self = {}

  self.logger = config.loggerFactory:CreateLogger("EventEmitter")
  self.client = config.client
  self.on = {}
  self.currentMaxListeners = DEFAULT_MAX_LISTENERS

  return _G.setmetatable_gc(self, {
    __index = EventEmitter,
    __gc = function(instance)
      if instance.on then
        for _, listeners in pairs(instance.on) do
          if type(listeners) == "table" then
            for i = 1, #listeners do
              listeners[i] = nil
            end
          end
        end
        instance.on = nil
      end
      instance.logger = nil
      instance.client = nil
    end
  })
end

function EventEmitter:getSafeEventTable(event)
  if type(self.on[event]) ~= "table" then
    self.on[event] = {}
  end

  return self.on[event]
end

function EventEmitter:getEventTable(event)
  return self.on[event]
end

function EventEmitter:hasListener(event, listener)
  local eventTable = self:getEventTable(event)
  if not eventTable then
    return false
  end

  for _, existingListener in ipairs(eventTable) do
    if existingListener == listener then
      return true
    end
  end

  return false
end

function EventEmitter:AddListener(event, listener)
  if type(listener) ~= "function" then
    self.client:emitError(
      ErrorTypes.INVALID_ARGUMENT,
      "Listener must be a function",
      "EventEmitter:AddListener",
      nil, -- use default log level
      { providedType = type(listener), event = tostring(event) }
    )
    return function() end
  end

  local eventPrefix = getCachedEventName(event)
  local eventTable = self:getSafeEventTable(eventPrefix)

  if self:hasListener(eventPrefix, listener) then
    self.logger:Warn("Listener already added for event: " .. tostring(event))
    return function()
      self:RemoveListener(event, listener)
    end
  end

  local maxListeners = self.currentMaxListeners or DEFAULT_MAX_LISTENERS
  local listenerCount = self:ListenerCount(event)

  table.insert(eventTable, listener)

  if listenerCount > maxListeners then
    self.logger:Warn("Number of " ..
      string.sub(eventPrefix, PREFIX_LENGTH + 1) .. " event listeners: " .. tostring(listenerCount))
  end

  return function()
    self:RemoveListener(event, listener)
  end
end

function EventEmitter:On(event, listener)
  return self:AddListener(event, listener)
end

function EventEmitter:OnWeak(event, listener)
  if type(listener) ~= "function" then
    self.client:emitError(
      ErrorTypes.INVALID_ARGUMENT,
      "Listener must be a function",
      "EventEmitter:OnWeak",
      nil, -- use default log level
      { providedType = type(listener), event = tostring(event) }
    )
    return function() end
  end

  local eventPrefix = getCachedEventName(event) .. "_weak"
  local eventTable = self:getSafeEventTable(eventPrefix)

  if not getmetatable(eventTable) or getmetatable(eventTable).__mode ~= "v" then
    self.on[eventPrefix] = setmetatable({}, { __mode = "v" })
    eventTable = self.on[eventPrefix]
  end

  for i = 1, #eventTable do
    if eventTable[i] == listener then
      return function()
        self:RemoveListener(event, listener)
      end
    end
  end

  table.insert(eventTable, listener)

  return function()
    self:RemoveListener(event, listener)
  end
end

function EventEmitter:Once(event, listener)
  if type(listener) ~= "function" then
    self.client:emitError(
      ErrorTypes.INVALID_ARGUMENT,
      "Listener must be a function",
      "EventEmitter:Once",
      nil, -- use default log level
      { providedType = type(listener), event = tostring(event) }
    )
    return function() end
  end

  local eventPrefix = getCachedEventName(event) .. ":once"
  local eventTable = self:getSafeEventTable(eventPrefix)

  if self:hasListener(eventPrefix, listener) then
    self.logger:Warn("Once listener already added for event: " .. tostring(event))
    return function()
      self:RemoveListener(event, listener)
    end
  end

  local maxListeners = self.currentMaxListeners or DEFAULT_MAX_LISTENERS
  local listenerCount = self:ListenerCount(event)

  if listenerCount > maxListeners then
    self.logger:Warn("Number of " ..
      string.sub(eventPrefix, PREFIX_LENGTH + 1) .. " event listeners: " .. tostring(listenerCount))
  end

  table.insert(eventTable, listener)

  return function()
    self:RemoveListener(event, listener)
  end
end

function EventEmitter:Off(event, listener)
  self:RemoveListener(event, listener)
end

function EventEmitter:OffAll(event)
  return self:RemoveAllListeners(event)
end

function EventEmitter:Emit(event, ...)
  local args = { ... }
  local eventName = tostring(event)
  local status, error

  local eventPrefix = getCachedEventName(event)
  local eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    local listeners = {}
    for i = 1, #eventTable do
      listeners[i] = eventTable[i]
    end

    for i, listener in ipairs(listeners) do
      status, error = pcall(function()
        listener(unpack(args))
      end)

      if not status then
        self.client:emitError(
          ErrorTypes.EVENT_EMITTER_CALLBACK_ERROR,
          "Event listener callback failed: " .. tostring(error),
          "EventEmitter:Emit",
          nil, -- use default log level
          {
            event = eventName,
            listenerIndex = i,
            totalListeners = #listeners,
            argCount = #args,
            listenerType = "normal"
          }
        )
      end
    end
  end

  eventPrefix = getCachedEventName(event) .. "_weak"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    local listeners = {}
    local count = 0

    for i = 1, #eventTable do
      if eventTable[i] then
        count = count + 1
        listeners[count] = eventTable[i]
      end
    end

    for i = 1, count do
      local listener = listeners[i]
      if listener then
        status, error = pcall(function()
          listener(unpack(args))
        end)

        if not status then
          self.client:emitError(
            ErrorTypes.EVENT_EMITTER_CALLBACK_ERROR,
            "Weak event listener callback failed: " .. tostring(error),
            "EventEmitter:Emit",
            nil, -- use default log level
            {
              event = eventName,
              listenerIndex = i,
              totalListeners = count,
              argCount = #args,
              listenerType = "weak"
            }
          )
        end
      end
    end
  end

  eventPrefix = getCachedEventName(event) .. ":once"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable and #eventTable > 0 then
    local listeners = {}
    for i = 1, #eventTable do
      listeners[i] = eventTable[i]
    end

    self.on[eventPrefix] = nil

    for i, listener in ipairs(listeners) do
      status, error = pcall(function()
        listener(unpack(args))
      end)

      if not status then
        self.client:emitError(
          ErrorTypes.EVENT_EMITTER_CALLBACK_ERROR,
          "Once event listener callback failed: " .. tostring(error),
          "EventEmitter:Emit",
          nil, -- use default log level
          {
            event = eventName,
            listenerIndex = i,
            totalListeners = #listeners,
            argCount = #args,
            listenerType = "once"
          }
        )
      end
    end
  end

  return self
end

function EventEmitter:GetMaxListeners()
  return self.currentMaxListeners or DEFAULT_MAX_LISTENERS
end

function EventEmitter:ListenerCount(event)
  local totalNum = 0
  local eventPrefix = getCachedEventName(event)
  local eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    totalNum = totalNum + #eventTable
  end

  eventPrefix = getCachedEventName(event) .. "_weak"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    for i = 1, #eventTable do
      if eventTable[i] then
        totalNum = totalNum + 1
      end
    end
  end

  eventPrefix = getCachedEventName(event) .. ":once"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    totalNum = totalNum + #eventTable
  end

  return totalNum
end

function EventEmitter:HasListeners(event)
  return self:ListenerCount(event) > 0
end

function EventEmitter:Listeners(event)
  local clone = {}
  local count = 0

  local eventPrefix = getCachedEventName(event)
  local eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    for _, listener in ipairs(eventTable) do
      count = count + 1
      clone[count] = listener
    end
  end

  eventPrefix = getCachedEventName(event) .. "_weak"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    for i = 1, #eventTable do
      if eventTable[i] then
        count = count + 1
        clone[count] = eventTable[i]
      end
    end
  end

  eventPrefix = getCachedEventName(event) .. ":once"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    for _, listener in ipairs(eventTable) do
      count = count + 1
      clone[count] = listener
    end
  end

  return clone
end

function EventEmitter:RemoveAllListeners(event)
  if event then
    local eventPrefix = getCachedEventName(event)
    self.on[eventPrefix] = nil
    self.on[eventPrefix .. "_weak"] = nil
    self.on[eventPrefix .. ":once"] = nil
  else
    self.on = {}
  end

  return self
end

function EventEmitter:RemoveListener(event, listener)
  if not listener then
    self.client:emitError(
      ErrorTypes.INVALID_ARGUMENT,
      "Listener cannot be nil",
      "EventEmitter:RemoveListener",
      nil,   -- use default log level
      { event = tostring(event) }
    )
    return self
  end

  local eventPrefix = getCachedEventName(event)
  local eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    removeEntry(eventTable, listener)

    if #eventTable == 0 then
      self.on[eventPrefix] = nil
    end
  end

  eventPrefix = getCachedEventName(event) .. "_weak"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    removeEntry(eventTable, listener)

    if #eventTable == 0 then
      self.on[eventPrefix] = nil
    end
  end

  eventPrefix = getCachedEventName(event) .. ":once"
  eventTable = self:getEventTable(eventPrefix)

  if eventTable then
    removeEntry(eventTable, listener)

    if #eventTable == 0 then
      self.on[eventPrefix] = nil
    end
  end

  return self
end

function EventEmitter:SetMaxListeners(n)
  if type(n) == "number" and n >= 0 then
    self.currentMaxListeners = n
  else
    self.client:emitError(
      ErrorTypes.INVALID_ARGUMENT,
      "MaxListeners must be a non-negative number",
      "EventEmitter:SetMaxListeners",
      nil, -- use default log level
      { providedValue = tostring(n), providedType = type(n) }
    )
  end
  return self
end

function EventEmitter:CleanupWeakListeners()
  for eventPrefix, eventTable in pairs(self.on) do
    if string.find(eventPrefix, "_weak$") and type(eventTable) == "table" then
      local hasValidListeners = false

      for i = 1, #eventTable do
        if eventTable[i] then
          hasValidListeners = true
          break
        end
      end

      if not hasValidListeners then
        self.on[eventPrefix] = nil
      end
    end
  end

  return self
end

return EventEmitter
