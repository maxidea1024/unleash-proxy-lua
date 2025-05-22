local LogLevel = {
  Trace = 0,
  Debug = 1,
  Info = 2,
  Warning = 3,
  Error = 4,
  Fatal = 5,
  None = 6
}

local levelNames = {
  [0] = "Trace",
  [1] = "Debug",
  [2] = "Info",
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

function ConsoleSink.New(minLevel, formatter)
  return setmetatable({
    minLevel = minLevel or LogLevel.Info,
    formatter = formatter or defaultFormatter
  }, ConsoleSink)
end

function ConsoleSink:Write(time, level, category, message)
  if level < self.minLevel then return end
  local out = self.formatter(time, level, category, message)
  io.write(out .. "\n")
end

local FileSink = {}
FileSink.__index = FileSink

function FileSink.New(path, minLevel, formatter)
  local f = assert(io.open(path, "a"))
  return setmetatable({
    file = f,
    minLevel = minLevel or LogLevel.Info,
    formatter = formatter or defaultFormatter
  }, FileSink)
end

function FileSink:Write(time, level, category, message)
  if level < self.minLevel then return end
  local out = self.formatter(time, level, category, message)
  self.file:write(out .. "\n")
  self.file:flush()
end

local FunctionSink = {}
FunctionSink.__index = FunctionSink

function FunctionSink.New(callback, minLevel, formatter)
  return setmetatable({
    callback = callback,
    minLevel = minLevel or LogLevel.Info,
    formatter = formatter or defaultFormatter
  }, FunctionSink)
end

function FunctionSink:Write(time, level, category, message)
  if level < self.minLevel then return end
  local out = self.formatter(time, level, category, message)
  self.callback(time, level, category, out)
end

local UnrealEngineSink = {}
UnrealEngineSink.__index = UnrealEngineSink

function UnrealEngineSink.New(logFunc, minLevel, formatter)
  return setmetatable({
    logFunc = logFunc,
    minLevel = minLevel or LogLevel.Info,
    formatter = formatter or defaultFormatter
  }, UnrealEngineSink)
end

function UnrealEngineSink:Write(time, level, category, message)
  if level < self.minLevel then return end
  local out = self.formatter(time, level, category, message)
  local unrealLevel = getLevelName(level)
  self.logFunc(unrealLevel, category, out)
end

local Logger = {}
Logger.__index = Logger

function Logger.New(category, minLevel, sinks)
  return setmetatable({
    category = category,
    minLevel = minLevel or LogLevel.Info,
    sinks = sinks or {}
  }, Logger)
end

function Logger:IsEnabled(level)
  return level >= self.minLevel
end

function Logger:Log(level, message, ...)
  if not self:IsEnabled(level) then return end

  local formatted
  local argCount = select("#", ...)

  if argCount == 0 then
    -- No format arguments, use message as-is to prevent format string vulnerabilities
    formatted = tostring(message)
  else
    -- Format arguments provided, use string.format safely
    local success, result = pcall(string.format, tostring(message), ...)
    if success then
      formatted = result
    else
      -- If formatting fails, escape % characters and append arguments
      local safeMessage = tostring(message):gsub("%%", "%%%%")
      local args = {...}
      local argStrings = {}
      for i = 1, argCount do
        table.insert(argStrings, tostring(args[i]))
      end
      formatted = safeMessage .. " [Args: " .. table.concat(argStrings, ", ") .. "]"
    end
  end

  local time = getTime()
  for _, sink in ipairs(self.sinks) do
    sink:Write(time, level, self.category, formatted)
  end
end

function Logger:Trace(msg, ...) self:Log(LogLevel.Trace, msg, ...) end

function Logger:Debug(msg, ...) self:Log(LogLevel.Debug, msg, ...) end

function Logger:Info(msg, ...) self:Log(LogLevel.Info, msg, ...) end

function Logger:Warn(msg, ...) self:Log(LogLevel.Warning, msg, ...) end

function Logger:Error(msg, ...) self:Log(LogLevel.Error, msg, ...) end

function Logger:Fatal(msg, ...) self:Log(LogLevel.Fatal, msg, ...) end

function Logger:TraceLambda(func)
  if self:IsEnabled(LogLevel.Trace) then
    local msg = func()
    self:Log(LogLevel.Trace, msg)
  end
end

function Logger:DebugLambda(func)
  if self:IsEnabled(LogLevel.Debug) then
    local msg = func()
    self:Log(LogLevel.Debug, msg)
  end
end

function Logger:InfoLambda(func)
  if self:IsEnabled(LogLevel.Info) then
    local msg = func()
    self:Log(LogLevel.Info, msg)
  end
end

function Logger:WarnLambda(func)
  if self:IsEnabled(LogLevel.Warning) then
    local msg = func()
    self:Log(LogLevel.Warning, msg)
  end
end

function Logger:ErrorLambda(func)
  if self:IsEnabled(LogLevel.Error) then
    local msg = func()
    self:Log(LogLevel.Error, msg)
  end
end

function Logger:FatalLambda(func)
  if self:IsEnabled(LogLevel.Fatal) then
    local msg = func()
    self:Log(LogLevel.Fatal, msg)
  end
end

local LoggerFactory = {}
LoggerFactory.__index = LoggerFactory

function LoggerFactory.New(minLevel, sinks)
  return setmetatable({
    minLevel = minLevel or LogLevel.Info,
    sinks = sinks or {}
  }, LoggerFactory)
end

function LoggerFactory:CreateLogger(category)
  return Logger.New(category, self.minLevel, self.sinks)
end

local DefaultLoggerFactory = {}
DefaultLoggerFactory.__index = DefaultLoggerFactory

function DefaultLoggerFactory.New(minLevel)
  local function printCallback(time, level, category, line)
    -- level 값이 unrealLevel 과 다르다. 확인 후 맵핑을 해주어야할듯하다.
    -- ULuaUtils.LogWrite(p.categoryName, writeLevel or 1, message)
    ULuaUtils.LogWrite(category, 1, line)
    -- print(line)
  end
  local sink = FunctionSink.New(printCallback, minLevel or LogLevel.Info)
  return setmetatable({
    minLevel = minLevel or LogLevel.Info,
    sinks = { sink }
  }, DefaultLoggerFactory)
end

function DefaultLoggerFactory:CreateLogger(category)
  return Logger.New(category, self.minLevel, self.sinks)
end

local SilentLoggerFactory = {}
SilentLoggerFactory.__index = SilentLoggerFactory

function SilentLoggerFactory.New(minLevel)
  return setmetatable({
    minLevel = minLevel or LogLevel.Info,
    sinks = {}
  }, SilentLoggerFactory)
end

function SilentLoggerFactory:CreateLogger(category)
  return Logger.New(category, self.minLevel, self.sinks)
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

local ueSink = logger.UnrealEngineSink.New(function(level, tag, msg)
    print(string.format("[UE-%s] [%s] %s", level, tag, msg))
end, logger.LogLevel.Warning)

local factory = logger.LoggerFactory.New(logger.LogLevel.Debug, {
    logger.ConsoleSink.New(logger.LogLevel.Debug),
    logger.FileSink.New("game.log", logger.LogLevel.Debug),
    ueSink
})

local log = factory:CreateLogger("Game")
log:Info("Hello from %s!", "Lua")
log:Warn("Low health: %d%%", 30)
log:Error("Fatal error!")
]]
