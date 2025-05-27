local Json = require("framework.3rdparty.togglet.dkjson")
local Validation = require("framework.3rdparty.togglet.validation")
local ErrorTypes = require("framework.3rdparty.togglet.error-types")

local ToggleProxy = {}
ToggleProxy.__index = ToggleProxy

-- Constants for common default values
local DEFAULT_VALUES = {
  BOOLEAN = false,
  NUMBER = 0,
  STRING = "",
  TABLE = {}
}

-- Helper function to handle payload validation
local function validatePayload(self, expectedType, defaultValue)
  if not self.variant or not self.variant.payload then
    -- TODO 로그로 출력하지 말고, detail 결과로 반환하는게 안지저분할듯
    -- self.client.logger:Warn("No valid payload found for feature `%s`", self.featureName)
    return false, defaultValue
  end

  if self.variant.payload.type ~= expectedType then
    -- TODO 로그로 출력하지 말고, detail 결과로 반환하는게 안지저분할듯
    -- self.client.logger:Warn("Expected `%s` payload for feature `%s` but got `%s`",
    --   expectedType, self.featureName, self.variant.payload.type or "nil")
    return false, defaultValue
  end

  if self.variant.payload.value == nil then
    -- TODO 로그로 출력하지 말고, detail 결과로 반환하는게 안지저분할듯
    -- self.client.logger:Warn("Empty %s payload for feature `%s`", expectedType, self.featureName)
    return false, defaultValue
  end

  return true, self.variant.payload.value
end

function ToggleProxy.New(client, featureName, variant)
  Validation.RequireValue(client, "client", "ToggleProxy.New")
  Validation.RequireName(featureName, "featureName", "ToggleProxy.New")
  Validation.RequireTable(variant, "variant", "ToggleProxy.New")

  local self = setmetatable({}, ToggleProxy)
  self.client = client
  self.featureName = featureName
  self.variant = variant
  return self
end

function ToggleProxy:FeatureName()
  return self.featureName
end

function ToggleProxy:VariantName(defaultVariantName)
  return self.variant.name or defaultVariantName or "disabled"
end

function ToggleProxy:RawVariant()
  return self.variant
end

function ToggleProxy:IsEnabled()
  return self.variant.feature_enabled or DEFAULT_VALUES.BOOLEAN
end

function ToggleProxy:BoolVariation(defaultValue)
  Validation.RequireBoolean(defaultValue, "defaultValue", "BoolVariation")

  return self.variant.feature_enabled or defaultValue
end

function ToggleProxy:NumberVariation(defaultValue)
  Validation.RequireNumber(defaultValue, "defaultValue", "NumberVariation")

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
    -- TODO 로그로 출력하지 말고, detail 결과로 반환하는게 안지저분할듯

    -- self.client.logger:Warn("Failed to convert value to number for feature `%s`: %s",
    --   self.featureName, tostring(payloadValue))

    -- self.client:emitError(
    --   ErrorTypes.CONVERSION_ERROR,
    --   "Failed to convert value to number",
    --   "ToggleProxy:NumberVariation",
    --   nil, -- use default log level
    --   {
    --     featureName = self.featureName,
    --     payload = payloadValue,
    --     expectedType = "number",
    --     prevention = "Ensure payload values are valid numbers or can be converted to numbers.",
    --     solution = "Check the feature flag configuration and make sure number values are properly formatted."
    --   }
    -- )

    return defaultValue
  end
end

function ToggleProxy:StringVariation(defaultValue)
  Validation.RequireString(defaultValue, "defaultValue", "StringVariation", true) -- allow empty

  local isPayloadValid, payloadValue = validatePayload(self, "string", defaultValue)
  if not isPayloadValid then
    return defaultValue
  end

  if payloadValue ~= nil then
    return tostring(payloadValue)
  else
    self.client.logger:Warn("nil value for feature `%s`", self.featureName)
    return defaultValue
  end
end

function ToggleProxy:JsonVariation(defaultValue)
  Validation.RequireTable(defaultValue, "defaultValue", "JsonVariation")

  local isPayloadValid, payloadValue = validatePayload(self, "json", defaultValue)
  if not isPayloadValid then
    return defaultValue
  end

  local success, result = pcall(function()
    return Json.decode(payloadValue)
  end)

  if not success or not result then
    -- TODO 로그로 출력하지 말고, detail 결과로 반환하는게 안지저분할듯

    -- self.client.logger:Warn("Failed to decode JSON for feature `%s`: %s", self.featureName, tostring(result))

    -- self.client:emitError(
    --   ErrorTypes.JSON_ERROR,
    --   "Failed to decode JSON payload",
    --   "ToggleProxy:JsonVariation",
    --   nil, -- use default log level
    --   {
    --     featureName = self.featureName,
    --     payload = payloadValue,
    --     errorMessage = tostring(result),
    --     prevention = "Ensure JSON payloads are valid and properly formatted.",
    --     solution = "Check the feature flag configuration and validate the JSON syntax."
    --   }
    -- )

    return defaultValue
  end

  return result
end

-- TODO 이름이 모호해서 일단은 기능을 막아둠.
-- function ToggleProxy:Variation(defaultValue)
--   if not self.variant or not self.variant.payload then
--     return defaultValue
--   end

--   local payloadType = self.variant.payload.type

--   if payloadType == "boolean" then
--     if type(defaultValue) ~= "boolean" then
--       self.client.logger:Warn("Expected `boolean` default value for feature `%s`, got `%s`",
--         self.featureName, type(defaultValue))
--       defaultValue = DEFAULT_VALUES.BOOLEAN
--     end
--     return self:BoolVariation(defaultValue)
--   elseif payloadType == "number" then
--     if type(defaultValue) ~= "number" then
--       self.client.logger:Warn("Expected `number` default value for feature `%s`, got `%s`",
--         self.featureName, type(defaultValue))
--       defaultValue = DEFAULT_VALUES.NUMBER
--     end
--     return self:NumberVariation(defaultValue)
--   elseif payloadType == "string" then
--     if type(defaultValue) ~= "string" then
--       self.client.logger:Warn("Expected `string` default value for feature `%s`, got `%s`",
--         self.featureName, type(defaultValue))
--       defaultValue = DEFAULT_VALUES.STRING
--     end
--     return self:StringVariation(defaultValue)
--   elseif payloadType == "json" then
--     if type(defaultValue) ~= "table" then
--       self.client.logger:Warn("Expected `table` default value for feature `%s`, got `%s`",
--         self.featureName, type(defaultValue))
--       defaultValue = DEFAULT_VALUES.TABLE
--     end
--     return self:JsonVariation(defaultValue)
--   else
--     self.client.logger:Warn("Unknown payload type `%s` for feature `%s`",
--       payloadType or "nil", self.featureName)

--     self.client:emitError(
--       ErrorTypes.INVALID_PAYLOAD_TYPE,
--       "Unknown payload type",
--       "ToggleProxy:GetVariation",
--       nil,
--       {
--         featureName = self.featureName,
--         payloadType = payloadType or "nil",
--         prevention = "Use only supported payload types: boolean, number, string, json.",
--         solution = "Check the feature flag configuration and correct the payload type."
--       }
--     )

--     return defaultValue
--   end
-- end

function ToggleProxy:GetPayloadType()
  return self.variant.payload and self.variant.payload.type or "<none>"
end

-- Cache for variant proxies to avoid creating new objects for the same feature/variant
ToggleProxy.Cache = setmetatable({}, { __mode = "v" })

-- Factory method that uses caching
function ToggleProxy.GetOrCreate(client, featureName, variant)
  local cacheKey = featureName .. ":" .. (variant and variant.name or "default")
  local cached = ToggleProxy.Cache[cacheKey]

  if cached then
    local isSameReference = cached.variant == variant
    local isSameContent = false

    if not isSameReference and variant then
      isSameContent =
          cached.variant and
          cached.variant.name == variant.name and
          cached.variant.feature_enabled == variant.feature_enabled and
          (
            (not cached.variant.payload and not variant.payload) or
            (cached.variant.payload and variant.payload and
              cached.variant.payload.type == variant.payload.type and
              cached.variant.payload.value == variant.payload.value)
          )
    end

    if isSameReference or isSameContent then
      return cached
    end
  end

  local proxy = ToggleProxy.New(client, featureName, variant)
  ToggleProxy.Cache[cacheKey] = proxy
  return proxy
end

return ToggleProxy
