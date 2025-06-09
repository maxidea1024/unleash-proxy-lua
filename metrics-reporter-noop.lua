local Promise = require("framework.3rdparty.togglet.promise")

local M = {}

function M.New(config)
  local self = setmetatable({}, {
    __index = M,
    __name = "MetricsReporterNoop"
  })
  return self
end

function M:Start()
  return Promise.Completed()
end

function M:Stop()
  return Promise.Completed()
end

function M:SendMetrics()
  return Promise.Completed()
end

function M:Count(name, enabled)
  return true
end

function M:CountVariant(name, variant)
  return true
end

return M
