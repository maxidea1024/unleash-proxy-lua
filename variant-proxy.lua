local json = require("framework.3rdparty.feature-flags.dkjson")
local events = require("framework.3rdparty.feature-flags.events")

local VariantProxy = {}
VariantProxy.__index = VariantProxy

-- Constants for common default values
local DEFAULT_VALUES = {
  BOOLEAN = false,
  NUMBER = 0,
  STRING = "",
  TABLE = {}
}

-- Helper function to validate type and log warning if needed
local function validateType(client, featureName, expectedType, value, defaultValue)
  if type(value) ~= expectedType then
    client.logger:Warn("`defaultValue` must be a " .. expectedType)
    return false, defaultValue
  end
  return true, value
end

-- Helper function to handle payload validation
local function validatePayload(self, expectedType, defaultValue)
  if not self.variant or not self.variant.payload then
    self.client.logger:Debug("No valid payload found for feature '%s'", self.featureName)
    return false, defaultValue
  end

  if self.variant.payload.type ~= expectedType then
    self.client.logger:Debug("Expected %s payload for feature '%s' but got '%s'",
      expectedType, self.featureName, self.variant.payload.type or "nil")
    return false, defaultValue
  end

  if self.variant.payload.value == nil then
    self.client.logger:Warn("Empty %s payload for feature '%s'", expectedType, self.featureName)
    return false, defaultValue
  end

  return true, self.variant.payload.value
end

function VariantProxy.New(client, featureName, variant)
  if not client then
    error("Client is required for VariantProxy")
  end

  if not featureName or type(featureName) ~= "string" then
    client.logger:Warn("Feature name must be a non-empty string")
    featureName = "unknown"
  end

  local self = setmetatable({}, VariantProxy)
  self.client = client
  self.featureName = featureName
  self.variant = variant or {
    name = "default",
    enabled = false,
    feature_enabled = false,
    payload = nil
  }

  return self
end

function VariantProxy:GetFeatureName()
  return self.featureName
end

function VariantProxy:GetVariantName()
  return self.variant.name or "default"
end

function VariantProxy:GetVariant()
  return self.variant
end

function VariantProxy:IsEnabled(defaultValue)
  return self.variant.feature_enabled or defaultValue or DEFAULT_VALUES.BOOLEAN
end

function VariantProxy:BoolVariation(defaultValue)
  defaultValue = defaultValue or DEFAULT_VALUES.BOOLEAN
  local isValid, validatedValue = validateType(self.client, self.featureName, "boolean", defaultValue,
    DEFAULT_VALUES.BOOLEAN)
  if not isValid then
    return validatedValue
  end

  return self.variant.feature_enabled or defaultValue
end

function VariantProxy:NumberVariation(defaultValue)
  defaultValue = defaultValue or DEFAULT_VALUES.NUMBER
  local isValid, validatedValue = validateType(self.client, self.featureName, "number", defaultValue,
    DEFAULT_VALUES.NUMBER)
  if not isValid then
    return validatedValue
  end

  local isPayloadValid, payloadValue = validatePayload(self, "number", defaultValue)
  if not isPayloadValid then
    return defaultValue
  end

  local numSuccess, numValue = pcall(function()
    return tonumber(payloadValue)
  end)

  if numSuccess and numValue then
    return numValue
  else
    self.client.logger:Warn("Failed to convert value to number for feature '%s': %s",
      self.featureName, tostring(payloadValue))

    self.client:emit(events.ERROR, {
      type = "NumberConversionError",
      message = "Failed to convert value to number",
      featureName = self.featureName,
      payload = payloadValue
    })

    return defaultValue
  end
end

function VariantProxy:StringVariation(defaultValue)
  defaultValue = defaultValue or DEFAULT_VALUES.STRING
  local isValid, validatedValue = validateType(self.client, self.featureName, "string", defaultValue,
    DEFAULT_VALUES.STRING)
  if not isValid then
    return validatedValue
  end

  local isPayloadValid, payloadValue = validatePayload(self, "string", defaultValue)
  if not isPayloadValid then
    return defaultValue
  end

  if payloadValue ~= nil then
    return tostring(payloadValue)
  else
    self.client.logger:Warn("Nil string value for feature '%s'", self.featureName)
    return defaultValue
  end
end

function VariantProxy:JsonVariation(defaultValue)
  defaultValue = defaultValue or DEFAULT_VALUES.TABLE
  local isValid, validatedValue = validateType(self.client, self.featureName, "table", defaultValue, DEFAULT_VALUES
  .TABLE)
  if not isValid then
    return validatedValue
  end

  local isPayloadValid, payloadValue = validatePayload(self, "json", defaultValue)
  if not isPayloadValid then
    return defaultValue
  end

  local success, result = pcall(function()
    return json.decode(payloadValue)
  end)

  if not success then
    self.client.logger:Warn("Failed to decode JSON for feature '%s': %s", self.featureName, tostring(result))

    self.client:emit(events.ERROR, {
      type = "JsonDecodeError",
      message = tostring(result),
      featureName = self.featureName,
      payload = payloadValue
    })

    return defaultValue
  end

  if not result then
    self.client.logger:Warn("JSON decode returned nil for feature '%s'", self.featureName)
    return defaultValue
  end

  return result
end

-- Convenience method to get any type of variation based on payload type
function VariantProxy:GetVariation(defaultValue)
  if not self.variant or not self.variant.payload then
    return defaultValue
  end

  local payloadType = self.variant.payload.type

  if payloadType == "boolean" then
    return self:BoolVariation(defaultValue)
  elseif payloadType == "number" then
    return self:NumberVariation(defaultValue)
  elseif payloadType == "string" then
    return self:StringVariation(defaultValue)
  elseif payloadType == "json" then
    return self:JsonVariation(defaultValue)
  else
    self.client.logger:Warn("Unknown payload type '%s' for feature '%s'",
      payloadType or "nil", self.featureName)
    return defaultValue
  end
end

-- Cache for variant proxies to avoid creating new objects for the same feature/variant
VariantProxy.Cache = setmetatable({}, { __mode = "v" })

-- Factory method that uses caching
function VariantProxy.GetOrCreate(client, featureName, variant)
  local cacheKey = featureName .. ":" .. (variant and variant.name or "default")
  local cached = VariantProxy.Cache[cacheKey]

  if cached and cached.variant == variant then
    return cached
  end

  local proxy = VariantProxy.New(client, featureName, variant)
  VariantProxy.Cache[cacheKey] = proxy
  return proxy
end

return VariantProxy
