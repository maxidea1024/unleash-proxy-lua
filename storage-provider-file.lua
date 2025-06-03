local Json = require("framework.3rdparty.togglet.dkjson")
local Util = require("framework.3rdparty.togglet.util")
local Promise = require("framework.3rdparty.togglet.promise")

local M = {}
M.__index = M
M.__name = "StorageProviderFile"

function M.New(backupPath, prefix)
  local self = setmetatable({}, M)
  self.backupPath = backupPath or Util.GetTempDir()
  self.prefix = prefix or ""
  return self
end

function M:Store(key, data)
  local promise = Promise.New()

  local filename = self:getStorageFilename(key)
  local success, jsonData = pcall(Json.encode, data)
  if not success or type(jsonData) ~= "string" then
    promise:Reject(jsonData)
    return promise
  end

  local file, err = io.open(filename, "w")
  if not file then
    promise:Reject(err)
    return promise
  end

  local ok, writeErr = pcall(function()
    file:write(jsonData)
    file:close()
  end)
  if not ok then
    promise:Reject(writeErr)
    return promise
  end

  promise:Resolve()
  return promise
end

function M:Load(key)
  local promise = Promise.New()

  local filename = self:getStorageFilename(key)
  local file, err = io.open(filename, "r")
  if not file then
    if err and err:match("No such file") then
      promise:Resolve(nil) -- No data found
    else
      promise:Reject(err)
    end
    return promise
  end

  local ok, rawData = pcall(function()
    local data = file:read("*all")
    file:close()
    return data
  end)
  if not ok then
    promise:Reject(rawData)
    return promise
  end

  if not rawData or rawData == "" then
    promise:Resolve(nil) -- No data found
    return promise
  end

  local success, data = pcall(Json.decode, rawData)
  if not success then
    promise:Reject(data)
    return promise
  end

  promise:Resolve(data)
  return promise
end

function M:getStorageFilename(key)
  local prefix
  if self.prefix and #self.prefix > 0 then
    prefix = self.prefix .. "-"
  else
    prefix = ""
  end

  local filename = Util.PathJoin(self.backupPath, prefix .. key .. ".json")
  return filename
end

return M
