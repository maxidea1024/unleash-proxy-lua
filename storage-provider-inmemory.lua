local Promise = require("framework.3rdparty.togglet.promise")

local M = {}

function M.New()
  local self = setmetatable({}, {
    __index = M,
    __name = "InMemoryStorageProvider"
  })

  self.store = {}

  return self
end

function M:Store(key, data)
  local promise = Promise.New()

  if type(key) ~= "string" then
    promise:Reject(string.format("Invalid key type: %s", type(key)))
    return promise
  end

  self.store[key] = data
  promise:Resolve()
  return promise
end

function M:Load(key)
  local promise = Promise.New()

  if type(key) ~= "string" then
    promise:Reject(string.format("Invalid key type: %s", type(key)))
    return promise
  end

  local data = self.store[key]
  promise:Resolve(data)
  return promise
end

return M
