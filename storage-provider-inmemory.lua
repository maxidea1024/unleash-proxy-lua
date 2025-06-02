local Promise = require("framework.3rdparty.togglet.promise")

local InMemoryStorageProvider = {}
InMemoryStorageProvider.__index = InMemoryStorageProvider

function InMemoryStorageProvider.New()
  local self = setmetatable({}, InMemoryStorageProvider)
  self.store = {}
  return self
end

function InMemoryStorageProvider:Store(key, data)
  local promise = Promise.New()

  if type(key) ~= "string" then
    promise:Reject(string.format("Invalid key type: %s", type(key)))
    return promise
  end

  self.store[key] = data
  promise:Resolve()
  return promise
end

function InMemoryStorageProvider:Load(key)
  local promise = Promise.New()

  if type(key) ~= "string" then
    promise:Reject(string.format("Invalid key type: %s", type(key)))
    return promise
  end

  local data = self.store[key]
  promise:Resolve(data)
  return promise
end

return InMemoryStorageProvider
