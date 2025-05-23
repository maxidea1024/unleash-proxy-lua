local json = require("framework.3rdparty.feature-flags.dkjson")
local sha2 = require("framework.3rdparty.feature-flags.sha2")

local function UrlEncode(str)
  if str then
    str = string.gsub(str, "([^%w ])", function(c) return string.format("%%%02X", string.byte(c)) end)
    str = string.gsub(str, " ", "+")
  end
  return str
end

local function UrlDecode(str)
  str = string.gsub(str, "+", " ")
  str = string.gsub(str, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  return str
end

local function parseQueryString(query)
  local params = {}
  for param in query:gmatch("([^&]+)") do
    local key, value = param:match("([^=]+)=(.+)")
    if key and value then
      params[UrlDecode(key)] = UrlDecode(value)
    end
  end
  return params
end

local function buildQueryString(params)
  local parts = {}
  for key, value in pairs(params) do
    table.insert(parts, UrlEncode(key) .. "=" .. UrlEncode(value))
  end
  return table.concat(parts, "&")
end

local function sortEntries(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end

  table.sort(keys)

  local sorted = {}
  for _, k in ipairs(keys) do
    table.insert(sorted, { k, t[k] })
  end

  return sorted
end

local function binToHex(bin)
  return ((bin:gsub('.', function(c)
    return string.format('%02x', string.byte(c))
  end)))
end

local function computeSHA256(input)
  local hashBin = sha2.sha256(input)
  return binToHex(hashBin)
end

local function UrlWithContextAsQuery(urlStr, context)
  local queryStart = urlStr:find("?")
  local baseUrl = queryStart and urlStr:sub(1, queryStart - 1) or urlStr
  local existingQuery = queryStart and urlStr:sub(queryStart + 1) or ""
  local params = parseQueryString(existingQuery)

  for key, value in pairs(context) do
    if key ~= "properties" and value ~= nil then
      params[key] = tostring(value)
    end
  end

  if context.properties then
    for key, value in pairs(context.properties) do
      if value ~= nil then
        params["properties[" .. key .. "]"] = tostring(value)
      end
    end
  end

  local newQuery = buildQueryString(params)
  return baseUrl .. "?" .. newQuery
end

local function contextString(context)
  local fields = {}
  for k, v in pairs(context) do
    if k ~= "properties" then
      fields[k] = v
    end
  end

  local sortedFields = sortEntries(fields)
  local properties = context.properties or {}
  local sortedProperties = sortEntries(properties)
  local data = { sortedFields, sortedProperties }
  return json.encode(data)
end

local function ComputeContextHashValue(context)
  local contextStr = contextString(context)
  local success, hash = pcall(computeSHA256, contextStr)
  if success then
    return hash
  else
    return contextStr
  end
end

local function IsTable(t)
  return type(t) == "table"
end

local function DeepClone(...)
  local result = {}

  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if IsTable(t) then
      for k, v in pairs(t) do
        if IsTable(v) and IsTable(result[k]) then
          result[k] = DeepClone(result[k], v)
        else
          result[k] = v
        end
      end
    end
  end

  return result
end

local function UuidV4()
  local random = math.random
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
    return string.format('%x', v)
  end)
end

local function UuidV7()
  -- random bytes
  local value = {}
  for i = 1, 16 do
    value[i] = math.random(0, 255)
  end

  -- current timestamp in ms
  local timestamp = os.time() * 1000

  -- timestamp - using bit library functions instead of operators
  value[1] = bit.band(bit.rshift(timestamp, 40), 0xFF)
  value[2] = bit.band(bit.rshift(timestamp, 32), 0xFF)
  value[3] = bit.band(bit.rshift(timestamp, 24), 0xFF)
  value[4] = bit.band(bit.rshift(timestamp, 16), 0xFF)
  value[5] = bit.band(bit.rshift(timestamp, 8), 0xFF)
  value[6] = bit.band(timestamp, 0xFF)

  -- version and variant
  value[7] = bit.bor(bit.band(value[7], 0x0F), 0x70)
  value[9] = bit.bor(bit.band(value[9], 0x3F), 0x80)

  return binToHex(string.char(unpack(value)))
end

local ElementCountOfTable = function(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end

local IsEmptyTable = function(t)
  return not next(t)
end

local Iso8601UtcNow = function()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local Iso8601UtcNowWithMSec = function()
  local now = os.time() -- socket.gettime()
  local seconds = math.floor(now)
  local milliseconds = math.floor((now - seconds) * 1000)
  return os.date("!%Y-%m-%dT%H:%M:%S", seconds) .. string.format(".%03dZ", milliseconds)
end

-- Utility function to calculate the hash value of a table or object
-- Usage: local hash = CalculateHash(obj)
--   - Computes the hash value of the given object (table or other value) and returns it as an integer.
--   - For tables, it recursively traverses keys and values to generate the hash, while for non-table values, it converts them to strings to compute the hash.
-- Parameters:
--   - obj (any): The object (table or other value) to calculate the hash for.
-- Returns:
--   - number: The computed integer hash value.
-- Example:
--   local tbl = { a = 1, b = "test" }
--   local hash = CalculateHash(tbl) -- Returns an integer hash
--   local hash2 = CalculateHash("simple") -- Returns the hash of a string
-- Notes:
--   - Circular references in tables are not handled (an error will be raised).
--   - Complex objects (functions, userdata, etc.) rely on the tostring result.
local function CalculateHash(obj, seen)
  -- Table to prevent circular references (nil on the first call)
  seen = seen or {}

  -- Raise an error if a circular reference is detected
  if type(obj) == "table" then
    if seen[obj] then
      error("CalculateHash: circular reference detected")
    end
    seen[obj] = true
  end

  local str = ""

  if type(obj) == "table" then
    -- Sort keys to ensure consistent hash
    local keys = {}
    for k in pairs(obj) do
      table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)

    -- Recursively convert keys and values to strings
    for _, k in ipairs(keys) do
      local v = obj[k]
      str = str .. tostring(k) .. "=" .. tostring(CalculateHash(v, seen)) .. ";"
    end
  else
    -- Convert non-table values to strings
    str = tostring(obj)
  end

  -- FNV-1a hashing algorithm
  local hash = 2166136261
  for i = 1, #str do
    hash = bit.bxor(hash, str:byte(i))
    hash = bit.band(hash * 16777619, 0xFFFFFFFF)
  end

  -- Convert to a positive integer
  return math.floor(hash % 2 ^ 31)
end

local function FindCaseInsensitive(t, key)
  if type(key) ~= "string" then
    return t[key]
  end

  local fastPathCheck = t[key]
  if fastPathCheck ~= nil then
    return fastPathCheck
  end

  for k, v in pairs(t) do
    if type(k) == "string" and k:lower() == key:lower() then
      return v
    end
  end

  return nil
end

--[[

  print(PathJoin("C:", "folder", "/subdir\\", "file.txt"))
    → C:\folder\subdir\file.txt (Windows)

  print(PathJoin("/usr", "local", "\\bin"))
    → /usr/local/bin (Unix)

 ]]
local function PathJoin(...)
  -- Determine the directory separator for the current OS
  local sep = package.config:sub(1, 1) -- '/' (Unix) or '\' (Windows)

  local parts = { ... }
  local cleaned = {}
  local is_windows = sep == "\\"

  for i, part in ipairs(parts) do
    part = tostring(part)

    -- First part is a drive letter (e.g., 'C:' or 'C:\')
    if i == 1 and is_windows and part:match("^%a:[/\\]?$") then
      -- Normalize: C: → C:\
      part = part:sub(1, 2) .. sep
    else
      -- Standardize slashes
      part = part:gsub("[/\\]+", sep)
      -- Remove leading and trailing separators (to prevent duplicates)
      part = part:gsub("^" .. sep .. "+", ""):gsub(sep .. "+$", "")
    end

    table.insert(cleaned, part)
  end

  -- Special handling if the first part is a drive letter (C:\ + the rest)
  if is_windows and cleaned[1] and cleaned[1]:match("^%a:" .. sep .. "?$") then
    return cleaned[1] .. table.concat(cleaned, sep, 2)
  else
    return table.concat(cleaned, sep)
  end
end

local function GetTempDir()
  return os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
end

local function ToJson(obj)
  return json.encode(obj)
end

local function FromJson(jsonStr)
  return json.decode(jsonStr)
end

local function MergeArrays(...)
  local result = {}
  for i = 1, select("#", ...) do
    local arr = select(i, ...)
    if type(arr) == "table" then
      for _, v in ipairs(arr) do
        table.insert(result, v)
      end
    end
  end
  return result
end

return {
  UrlWithContextAsQuery = UrlWithContextAsQuery,
  ComputeContextHashValue = ComputeContextHashValue,
  DeepClone = DeepClone,
  ElementCountOfTable = ElementCountOfTable,
  IsTable = IsTable,
  IsEmptyTable = IsEmptyTable,
  UuidV4 = UuidV4,
  UuidV7 = UuidV7,
  Iso8601UtcNow = Iso8601UtcNow,
  Iso8601UtcNowWithMSec = Iso8601UtcNowWithMSec,
  CalculateHash = CalculateHash,
  FindCaseInsensitive = FindCaseInsensitive,
  PathJoin = PathJoin,
  GetTempDir = GetTempDir,
  UrlEncode = UrlEncode,
  UrlDecode = UrlDecode,
  ToJson = ToJson,
  FromJson = FromJson,
  MergeArrays = MergeArrays,
}
