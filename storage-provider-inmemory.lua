local InMemoryStorageProvider = {}
InMemoryStorageProvider.__index = InMemoryStorageProvider

function InMemoryStorageProvider.New(loggerFactory)
  if not loggerFactory then error("`loggerFactory` is required") end

  local self = setmetatable({}, InMemoryStorageProvider)
  self.store = {}
  self.logger = loggerFactory:CreateLogger("InMemoryStorageProvider")
  return self
end

function InMemoryStorageProvider:Store(key, data, callback)
  if type(key) ~= "string" then
    self.logger:error("Invalid key type: " .. type(key))
    callback("Invalid key type")
    return
  end

  self.store[key] = data
  callback(nil)
end

function InMemoryStorageProvider:Load(key, callback)
  if type(key) ~= "string" then
    self.logger:error("Invalid key type: " .. type(key))
    callback(nil, "Invalid key type")
    return
  end

  local data = self.store[key]
  callback(data, nil)
end

function InMemoryStorageProvider:StoreSync(key, data)
  if type(key) ~= "string" then
    self.logger:error("Invalid key type: " .. type(key))
    return false, "Invalid key type"
  end

  self.store[key] = data
  return true, nil
end

function InMemoryStorageProvider:LoadSync(key)
  if type(key) ~= "string" then
    self.logger:error("Invalid key type: " .. type(key))
    return nil, "Invalid key type"
  end

  local data = self.store[key]
  return data, nil
end

return InMemoryStorageProvider
