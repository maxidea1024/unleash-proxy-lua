local MetricsReporterNoop = {}
MetricsReporterNoop.__index = MetricsReporterNoop

function MetricsReporterNoop.New(config)
  local self = setmetatable({}, MetricsReporterNoop)
  return self
end

function MetricsReporterNoop:Start()
  return Promise.Completed()
end

function MetricsReporterNoop:Stop()
  return Promise.Completed()
end

function MetricsReporterNoop:SendMetrics()
  return Promise.Completed()
end

function MetricsReporterNoop:Count(name, enabled)
  return true
end

function MetricsReporterNoop:CountVariant(name, variant)
  return true
end

return MetricsReporterNoop
