local Promise = require("framework.3rdparty.togglet.promise")

local M = {}
M.__index = M
M.__name = "MetricsReporterNoop"

function M.New(config)
  local self = setmetatable({}, M)
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
