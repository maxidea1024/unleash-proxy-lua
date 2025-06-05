local Timer = {}

local timers = {}
local nextTimerId = 1
local MAX_TIMER_ID = 2 ^ 30
local co_pool = setmetatable({}, { __mode = "kv" })
local MAX_POOL_SIZE = 100

local function logError(message)
  print("[TIMER ERROR] " .. tostring(message))
end

local function generateTimerId()
  local id = nextTimerId
  nextTimerId = nextTimerId + 1

  if nextTimerId >= MAX_TIMER_ID then
    nextTimerId = 1
  end

  return id
end

local function insertTimer(sec, fn)
  local now = os.clock()
  local expireAt = now + sec
  local pos = 1
  for i, v in ipairs(timers) do
    if v.expireAt > expireAt then
      break
    end
    pos = i + 1
  end

  local context = {
    isTimer = true,
    id = generateTimerId(),
    expireAt = expireAt,
    fn = fn,
    canceled = false
  }

  table.insert(timers, pos, context)
  return context
end

local function coresume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    logError(debug.traceback(co, err))
    return false, err
  end
  return ok, err
end

local function routine(fn)
  local co = coroutine.running()
  while true do
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      logError(err)
    end

    if #co_pool < MAX_POOL_SIZE then
      co_pool[#co_pool + 1] = co
      fn = coroutine.yield()
    else
      return
    end
  end
end

function Timer.Async(fn)
  if type(fn) ~= "function" then
    logError("Timer.Async requires a function argument")
    return nil
  end

  local co = table.remove(co_pool)
  if not co then
    co = coroutine.create(function()
      routine(fn)
    end)
  end

  local ok, res = coresume(co, fn)
  if not ok then
    return nil
  end

  if res then
    return res
  end

  return co
end

function Timer.NextTick(fn)
  if type(fn) ~= "function" then
    logError("Timer.NextTick requires a function argument")
    return nil
  end

  return insertTimer(0, fn)
end

function Timer.SetTimeout(seconds, fn)
  if type(fn) ~= "function" then
    logError("Timer.SetTimeout requires a function argument")
    return nil
  end

  if type(seconds) ~= "number" or seconds < 0 then
    logError("Timer.SetTimeout requires a non-negative number as first argument")
    return nil
  end

  return insertTimer(seconds, fn)
end

function Timer.SetInterval(seconds, fn)
  if type(fn) ~= "function" then
    logError("Timer.SetInterval requires a function argument")
    return nil
  end

  if type(seconds) ~= "number" or seconds < 0 then
    logError("Timer.SetInterval requires a non-negative number as first argument")
    return nil
  end

  local context
  local function intervalFn()
    if not context or context.canceled then return end

    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      logError(err)
    end

    if not context.canceled then
      context = insertTimer(seconds, intervalFn)
    end
  end

  context = insertTimer(seconds, intervalFn)
  return context
end

function Timer.Sleep(seconds)
  if type(seconds) ~= "number" or seconds < 0 then
    logError("Timer.Sleep requires a non-negative number argument")
    return nil
  end

  local co = coroutine.running()
  if not co then
    logError("Timer.Sleep must be called from within a coroutine")
    return nil
  end

  insertTimer(seconds, function()
    coroutine.resume(co)
  end)

  return coroutine.yield()
end

function Timer.Cancel(context)
  if not context then
    logError("Timer.Cancel requires a timer context")
    return false
  end

  if not context.isTimer then
    logError("Timer.Cancel requires a timer context")
    return false
  end

  context.canceled = true
  return true
end

function Timer.TimerCount()
  return #timers
end

function Timer.CleanupCanceled()
  local i = 1
  while i <= #timers do
    if timers[i].canceled then
      table.remove(timers, i)
    else
      i = i + 1
    end
  end
end

function Timer.Update()
  local now = os.clock()
  while #timers > 0 do
    local timer = timers[1]

    if timer.expireAt <= now then
      table.remove(timers, 1)

      if not timer.canceled then
        local ok, err = xpcall(timer.fn, debug.traceback)
        if not ok then
          logError(err)
        end
      end
    else
      break
    end
  end

  if #timers > 100 then
    Timer.CleanupCanceled()
  end
end

return Timer
