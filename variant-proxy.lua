local json = require("framework.3rdparty.feature-flags.dkjson")
local events = require("framework.3rdparty.feature-flags.events")

local VariantProxy = {}
VariantProxy.__index = VariantProxy

function VariantProxy.New(client, featureName, variant)
  local self = setmetatable({}, VariantProxy)
  self.client = client
  self.featureName = featureName
  self.variant = variant
  return self
end

function VariantProxy:GetFeatureName()
  return self.featureName
end

function VariantProxy:GetVariantName()
  return self.variant.name
end

function VariantProxy:GetVariant()
  return self.variant
end

function VariantProxy:BoolVariation(defaultValue)
  defaultValue = defaultValue or false
  if type(defaultValue) ~= "boolean" then
    self.client.logger:Warn("`defaultValue` must be a boolean")
    return defaultValue
  end

  return self.variant.feature_enabled or defaultValue
end

function VariantProxy:NumberVariation(defaultValue)
  defaultValue = defaultValue or 0
  if type(defaultValue) ~= "number" then
    self.client.logger:Warn("`defaultValue` must be a number")
    return defaultValue
  end

  if self.variant and self.variant.payload and self.variant.payload.type == "number" then
    local numSuccess, numValue = pcall(function()
      return tonumber(self.variant.payload.value)
    end)

    if numSuccess and numValue then
      return numValue
    else
      self.client.logger:Warn("Failed to convert value to number for feature '%s': %s", self.featureName,
        tostring(self.variant.payload.value))
      return defaultValue
    end
  end

  return defaultValue
end

function VariantProxy:StringVariation(defaultValue)
  defaultValue = defaultValue or ""
  if type(defaultValue) ~= "string" then
    self.client.logger:Warn("`defaultValue` must be a string")
    return defaultValue
  end

  if self.variant and self.variant.payload and self.variant.payload.type == "string" then
    if self.variant.payload.value ~= nil then
      local strValue = tostring(self.variant.payload.value)
      return strValue
    else
      self.client.logger:Warn("Nil string value for feature '%s'", self.featureName)
      return defaultValue
    end
  end

  return defaultValue
end

function VariantProxy:JsonVariation(defaultValue)
  defaultValue = defaultValue or {}
  if type(defaultValue) ~= "table" then
    self.client.logger:Warn("`defaultValue` must be a table")
    return defaultValue
  end

  if not self.variant.payload then
    self.client.logger:Debug("No valid payload found for feature '%s'", self.featureName)
    return defaultValue
  end

  if self.variant.payload.type ~= "json" then
    self.client.logger:Debug("Expected JSON payload for feature '%s' but got '%s'", self.featureName,
      self.variant.payload.type or "nil")
    return defaultValue
  end

  if not self.variant.payload.value then
    self.client.logger:Warn("Empty JSON payload for feature '%s'", self.featureName)
    return defaultValue
  end

  local success, result = pcall(function()
    return json.decode(self.variant.payload.value)
  end)

  if not success then
    self.client.logger:Warn("Failed to decode JSON for feature '%s': %s", self.featureName, tostring(result))

    self.client:emit(events.ERROR, {
      type = "JsonDecodeError",
      message = tostring(result),
      featureName = self.featureName,
      payload = self.variant.payload.value
    })

    return defaultValue
  end

  if not result then
    self.client.logger:Warn("JSON decode returned nil for feature '%s'", self.featureName)
    return defaultValue
  end

  return result
end

function VariantProxy:IsEnabled()
  return self.variant.feature_enabled
end

return VariantProxy
