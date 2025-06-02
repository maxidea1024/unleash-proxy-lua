local timers = {}
local nextTimerId = 1
local co_pool = setmetatable({}, { __mode = "kv" })

function insertTimer(sec, fn)
  local now = os.clock()
  local expireAt = now + sec
  local pos = 1
  for i, v in ipairs(timers) do
    if v.expireAt > expireAt then
      break
    end
    pos = i + 1
  end

  local context = { id = nextTimerId, expireAt = expireAt, fn = fn }
  nextTimerId = nextTimerId + 1

  table.insert(timers, pos, context)
  return context
end

local function coresume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    error(debug.traceback(co, err))
  end
  return ok, err
end

function routine(fn)
  local co = coroutine.running()
  while true do
    fn()
    co_pool[#co_pool + 1] = co
    fn = coroutine.yield()
  end
end

function Timer.Async(fn)
  local co = table.remove(co_pool)
  if not co then
    co = coroutine.create(function()
      routine(fn)
    end)
  end

  local _, res = coresume(co, fn)
  if res then
    return res
  end

  return co
end

function Timer.NextTick(fn)
  insertTimer(0, fn)
end

function Timer.SetTimeout(seconds, fn)
  return insertTimer(seconds, fn)
end

function Timer:SetInterval(seconds, fn)
  local context
  local function intervalFn()
    if not context or context.canceled then return end

    -- Execute the function
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      print("timer error: " .. tostring(err))
    end

    -- Schedule the next execution if not canceled
    if not context.canceled then
      context = insertTimer(seconds, intervalFn)
    end
  end

  -- Start the interval
  context = insertTimer(seconds, intervalFn)
  return context
end

function Timer.Sleep(seconds)
  local co = coroutine.running()
  insertTimer(seconds, function()
    coroutine.resume(co)
  end)

  return coroutine.yield()
end

function Timer.Cancel(ctx)
  ctx.canceled = true
end

function Timer.TimerCount()
  return #timers
end

function Timer.Tick()
  local now = os.clock()
  while #timers > 0 do
    local timer = timers[1]

    if timer.expireAt <= now then
      table.remove(timers, 1)

      if not timer.canceled then
        local ok, err = xpcall(timer.fn, debug.traceback)
        if not ok then
          print("timer error: " .. tostring(err))
        end
      end
    else
      break
    end
  end
end

return Timer
