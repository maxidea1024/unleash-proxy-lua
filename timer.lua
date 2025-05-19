-- Original source code:
--   https://github.com/sniper00/lua_timer/blob/master/timer.lua

local Timer = {}
Timer.__index = Timer

function Timer.New(loggerFactory)
  if not loggerFactory then error("`loggerFactory` is required") end

  local self = setmetatable({}, Timer)
  self.timers = {}
  self.co_pool = setmetatable({}, { __mode = "kv" })
  self.logger = loggerFactory.CreateLogger("UnleashTimer")
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

  local context = { expireAt = expireAt, fn = fn }
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
  return self:insertTimer(seconds, fn)
end

function Timer:Sleep(seconds)
  local co = coroutine.running()
  self:insertTimer(seconds, function()
    coroutine.resume(co)
  end)

  return coroutine.yield()
end

function Timer:Remove(ctx)
  ctx.remove = true
end

function Timer:RemoveAll()
  self.timers = {}
end

function Timer:Tick()
  local now = os.clock()
  while #self.timers > 0 do
    local timer = self.timers[1]

    if timer.expireAt <= now then
      table.remove(self.timers, 1)

      if not timer.remove then
        local ok, err = xpcall(timer.fn, debug.traceback)
        if not ok then
          self.logger:error("timer error:", err)
        end
      end
    else
      break
    end
  end
end

return Timer
