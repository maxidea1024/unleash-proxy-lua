local Timer = {}
Timer.__index = Timer

local ErrorTypes = require("framework.3rdparty.feature-flags.error-types")
local Logger = require("framework.3rdparty.feature-flags.logger")

function Timer.New(loggerFactory, client)
  if not loggerFactory then error("`loggerFactory` is required") end
  if not client then error("`client` is required") end

  local self = setmetatable({}, Timer)
  self.timers = {}
  self.co_pool = setmetatable({}, { __mode = "kv" })
  self.logger = loggerFactory:CreateLogger("UnleashTimer")
  self.nextTimerId = 1
  self.client = client
  return self
end

function Timer:insertTimer(sec, fn)
  local expireAt = os.clock() + sec
  local pos = 1
  for i, v in ipairs(self.timers) do
    if v.expireAt > expireAt then
      break
    end
    pos = i + 1
  end

  local context = { id = self.nextTimerId, expireAt = expireAt, fn = fn }
  self.nextTimerId = self.nextTimerId + 1

  table.insert(self.timers, pos, context)
  return context
end

function Timer:coresume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    self.logger:error(debug.traceback(co, err))
  end
  return ok, err
end

function Timer:routine(fn)
  local co = coroutine.running()
  while true do
    fn()
    self.co_pool[#self.co_pool + 1] = co
    fn = coroutine.yield()
  end
end

function Timer:Async(fn)
  local co = table.remove(self.co_pool)
  if not co then
    co = coroutine.create(function()
      self:routine(fn)
    end)
  end

  local _, res = self:coresume(co, fn)
  if res then
    return res
  end

  return co
end

function Timer:Timeout(seconds, fn)
  local timer = self:insertTimer(seconds, fn)
  return timer
end

function Timer:Sleep(seconds)
  local co = coroutine.running()
  self:insertTimer(seconds, function()
    coroutine.resume(co)
  end)

  return coroutine.yield()
end

function Timer:Cancel(ctx)
  ctx.canceled = true
end

function Timer:CancelAll()
  self.timers = {}
end

function Timer:TimerCount()
  return #self.timers
end

function Timer:Tick()
  local now = os.clock()
  while #self.timers > 0 do
    local timer = self.timers[1]

    if timer.expireAt <= now then
      table.remove(self.timers, 1)

      if not timer.canceled then
        local ok, err = xpcall(timer.fn, debug.traceback)
        if not ok then
          self.client:emitError(
            ErrorTypes.TIMER_ERROR,
            "Timer execution failed: " .. tostring(err),
            "Timer:Tick",
            Logger.LogLevel.Error,
            {
              timerId = timer.id,
              stackTrace = err,
              prevention = "Ensure timer callbacks handle all possible error cases.",
              solution = "Review the timer callback implementation and add proper error handling.",
              troubleshooting = {
                "1. Check for nil values in the timer callback",
                "2. Ensure all required resources are available when the timer executes",
                "3. Add pcall/xpcall within the timer callback for critical operations"
              }
            }
          )
        end
      end
    else
      break
    end
  end
end

return Timer
