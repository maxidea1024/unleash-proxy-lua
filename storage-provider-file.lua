local Json = require("framework.3rdparty.feature-flags.dkjson")
local Util = require("framework.3rdparty.feature-flags.util")

local FileStorageProvider = {}
FileStorageProvider.__index = FileStorageProvider

function FileStorageProvider.New(backupPath, prefix, loggerFactory)
  if not loggerFactory then error("`loggerFactory` is required") end

  local self = setmetatable({}, FileStorageProvider)
  self.backupPath = backupPath or Util.GetTempDir()
  self.prefix = prefix or ""
  self.logger = loggerFactory:CreateLogger("UnleashFileStorageProvider")
  return self
end

function FileStorageProvider:Store(key, data, callback)
  callback = callback or function(err) end

  local filename = self:getStorageFilename(key)
  local success, jsonData = pcall(Json.encode, data)
  if not success or type(jsonData) ~= "string" then
    self.logger:error("Failed to encode JSON: " .. tostring(jsonData))
    callback(jsonData)
    return
  end

  local file, err = io.open(filename, "w")
  if not file then
    self.logger:Error("Failed to open file for writing: " .. tostring(err))
    callback(err)
    return
  end

  local ok, writeErr = pcall(function()
    file:write(jsonData)
    file:close()
  end)
  if not ok then
    self.logger:Error("Failed to write to file: " .. tostring(writeErr))
    callback(writeErr)
    return
  end

  callback(nil)
end

function FileStorageProvider:Load(key, callback)
  local filename = self:getStorageFilename(key)
  local file, err = io.open(filename, "r")
  if not file then
    if err and err:match("No such file") then
      callback(nil, nil) -- No data found
    else
      self.logger:Error("Failed to open file for reading: " .. tostring(err))
      callback(nil, err)
    end
    return
  end

  local ok, rawData = pcall(function()
    local data = file:read("*all")
    file:close()
    return data
  end)
  if not ok then
    self.logger:Error("Failed to read file: " .. tostring(rawData))
    callback(nil, rawData)
    return
  end

  if not rawData or rawData == "" then
    callback(nil, nil) -- No data found
    return
  end

  local success, data = pcall(Json.decode, rawData)
  if not success then
    self.logger:Error("Failed to decode JSON: " .. tostring(data))
    callback(nil, data)
    return
  end

  callback(data, nil)
end

function FileStorageProvider:StoreSync(key, data)
  local filename = self:getStorageFilename(key)
  local success, jsonData = pcall(Json.encode, data)
  if not success or type(jsonData) ~= "string" then
    self.logger:Error("Failed to encode JSON: " .. tostring(jsonData))
    return false, jsonData
  end

  local file, err = io.open(filename, "w")
  if not file then
    self.logger:Error("Failed to open file for writing: " .. tostring(err))
    return false, err
  end

  local ok, writeErr = pcall(function()
    file:write(jsonData)
    file:close()
  end)
  if not ok then
    self.logger:Error("Failed to write to file: " .. tostring(writeErr))
    return false, writeErr
  end

  return true, nil
end

function FileStorageProvider:LoadSync(key)
  local filename = self:getStorageFilename(key)
  local file, err = io.open(filename, "r")
  if not file then
    if err and err:match("No such file") then
      return nil, nil -- No data found
    else
      self.logger:Error("Failed to open file for reading: " .. tostring(err))
      return nil, err
    end

    return nil, nil
  end

  local ok, rawData = pcall(function()
    local data = file:read("*all")
    file:close()
    return data
  end)
  if not ok then
    self.logger:Error("Failed to read file: " .. tostring(rawData))
    return nil, rawData
  end

  if not rawData or rawData == "" then
    return nil, nil -- No data found
  end

  local success, data = pcall(Json.decode, rawData)
  if not success then
    self.logger:Error("Failed to decode JSON: " .. tostring(data))
    return nil, data
  end

  return data, nil
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
