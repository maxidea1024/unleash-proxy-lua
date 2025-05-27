local Json = require("framework.3rdparty.togglet.dkjson")
local Util = require("framework.3rdparty.togglet.util")
local Promise = require("framework.3rdparty.togglet.promise")

local FileStorageProvider = {}
FileStorageProvider.__index = FileStorageProvider

function FileStorageProvider.New(backupPath, prefix, loggerFactory)
  if not loggerFactory then error("`loggerFactory` is required") end

  local self = setmetatable({}, FileStorageProvider)
  self.backupPath = backupPath or Util.GetTempDir()
  self.prefix = prefix or ""
  self.logger = loggerFactory:CreateLogger("FileStorageProvider")
  return self
end

function FileStorageProvider:Store(key, data)
  local promise = Promise.New()

  local filename = self:getStorageFilename(key)
  local success, jsonData = pcall(Json.encode, data)
  if not success or type(jsonData) ~= "string" then
    -- self.logger:Error("Failed to encode JSON: " .. tostring(jsonData))
    promise:Reject(jsonData)
    return promise
  end

  local file, err = io.open(filename, "w")
  if not file then
    -- self.logger:Error("Failed to open file for writing: " .. tostring(err))
    promise:Reject(err)
    return promise
  end

  local ok, writeErr = pcall(function()
    file:write(jsonData)
    file:close()
  end)
  if not ok then
    -- self.logger:Error("Failed to write to file: " .. tostring(writeErr))
    promise:Reject(writeErr)
    return promise
  end

  promise:Resolve()
  return promise
end

function FileStorageProvider:Load(key)
  local promise = Promise.New()

  local filename = self:getStorageFilename(key)
  local file, err = io.open(filename, "r")
  if not file then
    if err and err:match("No such file") then
      promise:Resolve(nil) -- No data found
    else
      -- self.logger:Error("Failed to open file for reading: " .. tostring(err))
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
    -- self.logger:Error("Failed to read file: " .. tostring(rawData))
    promise:Reject(rawData)
    return promise
  end

  if not rawData or rawData == "" then
    promise:Resolve(nil) -- No data found
    return promise
  end

  local success, data = pcall(Json.decode, rawData)
  if not success then
    -- self.logger:Error("Failed to decode JSON: " .. tostring(data))
    promise:Reject(data)
    return promise
  end

  promise:Resolve(data)
  return promise
end

function FileStorageProvider:getStorageFilename(key)
  local prefix
  if self.prefix and #self.prefix > 0 then
    prefix = self.prefix .. "-"
  else
    prefix = ""
  end

  local filename = Util.PathJoin(self.backupPath, prefix .. key .. ".json")
  return filename
end

return FileStorageProvider
