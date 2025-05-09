local LogLevel = {
  VeryVerbose = 0,
  Verbose = 1,
  Log = 2,
  Warning = 3,
  Error = 4,
  Fatal = 5,
  None = 6
}

local levelNames = {
  [0] = "VeryVerbose",
  [1] = "Verbose",
  [2] = "Log",
  [3] = "Warning",
  [4] = "Error",
  [5] = "Fatal",
  [6] = "None"
}

local function getLevelName(level)
  return levelNames[level] or "Unknown"
end

local function defaultFormatter(time, level, category, message)
  -- return string.format("[%s] [%s] [%s] %s", time, getLevelName(level), category, message)
  -- return string.format("[%s] [%s] %s", getLevelName(level), category, message)
  return string.format("[%s] %s", category, message)
end

local function getTime()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local ConsoleSink = {}
ConsoleSink.__index = ConsoleSink

function ConsoleSink.new(minLevel, formatter)
  return setmetatable({
    minLevel = minLevel or LogLevel.Log,
    formatter = formatter or defaultFormatter
  }, ConsoleSink)
end

function ConsoleSink:write(time, level, category, message)
  if level < self.minLevel then return end
  local out = self.formatter(time, level, category, message)
  io.write(out .. "\n")
end

local FileSink = {}
FileSink.__index = FileSink

function FileSink.new(path, minLevel, formatter)
  local f = assert(io.open(path, "a"))
  return setmetatable({
    file = f,
    minLevel = minLevel or LogLevel.Log,
    formatter = formatter or defaultFormatter
  }, FileSink)
end

function FileSink:write(time, level, category, message)
  if level < self.minLevel then return end
  local out = self.formatter(time, level, category, message)
  self.file:write(out .. "\n")
  self.file:flush()
end

local FunctionSink = {}
FunctionSink.__index = FunctionSink

function FunctionSink.new(callback, minLevel, formatter)
  return setmetatable({
    callback = callback,
    minLevel = minLevel or LogLevel.Log,
    formatter = formatter or defaultFormatter
  }, FunctionSink)
end

function FunctionSink:write(time, level, category, message)
  if level < self.minLevel then return end
  local out = self.formatter(time, level, category, message)
  self.callback(time, level, category, out)
end

local UnrealEngineSink = {}
UnrealEngineSink.__index = UnrealEngineSink

function UnrealEngineSink.new(logFunc, minLevel, formatter)
  return setmetatable({
    logFunc = logFunc,
    minLevel = minLevel or LogLevel.Log,
    formatter = formatter or defaultFormatter
  }, UnrealEngineSink)
end

function UnrealEngineSink:write(time, level, category, message)
  if level < self.minLevel then return end
  local out = self.formatter(time, level, category, message)
  local unrealLevel = getLevelName(level)
  self.logFunc(unrealLevel, category, out)
end

local Logger = {}
Logger.__index = Logger

function Logger.new(category, minLevel, sinks)
  return setmetatable({
    category = category,
    minLevel = minLevel or LogLevel.Log,
    sinks = sinks or {}
  }, Logger)
end

function Logger:isEnabled(level)
  return level >= self.minLevel
end

function Logger:log(level, message, ...)
  if not self:isEnabled(level) then return end
  local formatted = string.format(message, ...)
  local time = getTime()
  for _, sink in ipairs(self.sinks) do
    sink:write(time, level, self.category, formatted)
  end
end

function Logger:trace(msg, ...) self:log(LogLevel.VeryVerbose, msg, ...) end

function Logger:debug(msg, ...) self:log(LogLevel.Verbose, msg, ...) end

function Logger:info(msg, ...) self:log(LogLevel.Log, msg, ...) end

function Logger:warn(msg, ...) self:log(LogLevel.Warning, msg, ...) end

function Logger:error(msg, ...) self:log(LogLevel.Error, msg, ...) end

function Logger:critical(msg, ...) self:log(LogLevel.Fatal, msg, ...) end

local LoggerFactory = {}
LoggerFactory.__index = LoggerFactory

function LoggerFactory.new(minLevel, sinks)
  return setmetatable({
    minLevel = minLevel or LogLevel.Log,
    sinks = sinks or {}
  }, LoggerFactory)
end

function LoggerFactory:createLogger(category)
  return Logger.new(category, self.minLevel, self.sinks)
end

local DefaultLoggerFactory = {}
DefaultLoggerFactory.__index = DefaultLoggerFactory

function DefaultLoggerFactory.new(minLevel)
  local function printCallback(time, level, category, line)
    -- level 값이 unrealLevel 과 다르다. 확인 후 맵핑을 해주어야할듯하다.
    -- ULuaUtils.LogWrite(p.categoryName, writeLevel or 1, message)
    ULuaUtils.LogWrite(category, 1, line)
    -- print(line)
  end
  local sink = FunctionSink.new(printCallback, minLevel or LogLevel.Log)
  return setmetatable({
    minLevel = minLevel or LogLevel.Log,
    sinks = { sink }
  }, DefaultLoggerFactory)
end

function DefaultLoggerFactory:createLogger(category)
  return Logger.new(category, self.minLevel, self.sinks)
end

local SilentLoggerFactory = {}
SilentLoggerFactory.__index = SilentLoggerFactory

function SilentLoggerFactory.new(minLevel)
  return setmetatable({
    minLevel = minLevel or LogLevel.Log,
    sinks = {}
  }, SilentLoggerFactory)
end

function SilentLoggerFactory:createLogger(category)
  return Logger.new(category, self.minLevel, self.sinks)
end

return {
  LogLevel = LogLevel,
  ConsoleSink = ConsoleSink,
  FileSink = FileSink,
  FunctionSink = FunctionSink,
  UnrealEngineSink = UnrealEngineSink,
  Logger = Logger,
  LoggerFactory = LoggerFactory,
  DefaultLoggerFactory = DefaultLoggerFactory,
  SilentLoggerFactory = SilentLoggerFactory
}

--[[

local logger = require("logger")

local ueSink = logger.UnrealEngineSink.new(function(level, tag, msg)
    print(string.format("[UE-%s] [%s] %s", level, tag, msg))
end, logger.LogLevel.Warning)

local factory = logger.LoggerFactory.new(logger.LogLevel.Verbose, {
    logger.ConsoleSink.new(logger.LogLevel.Verbose),
    logger.FileSink.new("game.log", logger.LogLevel.Debug),
    ueSink
})

local log = factory:createLogger("Game")
log:info("Hello from %s!", "Lua")
log:warn("Low health: %d%%", 30)
log:error("Fatal error!")
]]
