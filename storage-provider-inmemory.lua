local InMemoryStorageProvider = {}
InMemoryStorageProvider.__index = InMemoryStorageProvider

function InMemoryStorageProvider.new(loggerFactory)
  if not loggerFactory then error("`loggerFactory` is required") end

  local self = setmetatable({}, InMemoryStorageProvider)
  self.store = {}
  self.logger = loggerFactory:createLogger("UnleashInMemoryStorageProvider")
  return self
end

function InMemoryStorageProvider:save(key, data, callback)
  if type(key) ~= "string" then
    self.logger:error("Invalid key type: " .. type(key))
    callback("Invalid key type")
    return
  end

  self.store[key] = data
  callback(nil)
end

function InMemoryStorageProvider:get(key, callback)
  if type(key) ~= "string" then
    self.logger:error("Invalid key type: " .. type(key))
    callback(nil, "Invalid key type")
    return
  end

  local data = self.store[key]
  callback(data, nil)
end

function InMemoryStorageProvider:saveSync(key, data)
  if type(key) ~= "string" then
    self.logger:error("Invalid key type: " .. type(key))
    return false, "Invalid key type"
  end

  self.store[key] = data
  return true, nil
end

function InMemoryStorageProvider:getSync(key)
  if type(key) ~= "string" then
    self.logger:error("Invalid key type: " .. type(key))
    return nil, "Invalid key type"
  end

  local data = self.store[key]
  return data, nil
end

return InMemoryStorageProvider
