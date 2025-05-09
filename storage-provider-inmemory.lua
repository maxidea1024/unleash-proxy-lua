local InMemoryStorageProvider = {}
InMemoryStorageProvider.__index = InMemoryStorageProvider

function InMemoryStorageProvider.new(loggerFactory)
  if not loggerFactory then error("`loggerFactory` is required") end

  local self = setmetatable({}, InMemoryStorageProvider)
  self.store = {}
  self.logger = loggerFactory:createLogger("InMemoryStorageProvider")
  return self
end

function InMemoryStorageProvider:save(name, data, callback)
  if type(name) ~= "string" then
    self.logger:error("Invalid key type: " .. type(name))
    callback("Invalid key type")
    return
  end

  self.store[name] = data

  callback(nil)
end

function InMemoryStorageProvider:get(name, callback)
  if type(name) ~= "string" then
    self.logger:error("Invalid key type: " .. type(name))
    callback(nil, "Invalid key type")
    return
  end

  local data = self.store[name]

  callback(data, nil)
end

function InMemoryStorageProvider:saveSync(name, data)
  if type(name) ~= "string" then
    self.logger:error("Invalid key type: " .. type(name))
    return false, "Invalid key type"
  end

  self.store[name] = data
  return true, nil
end

function InMemoryStorageProvider:getSync(name)
  if type(name) ~= "string" then
    self.logger:error("Invalid key type: " .. type(name))
    return nil, "Invalid key type"
  end

  local data = self.store[name]
  return data, nil
end

return InMemoryStorageProvider
