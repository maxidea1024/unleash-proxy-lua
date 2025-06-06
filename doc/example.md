local isFeatureEnabled = client:IsEnabled("feature-1")

local variant = client:GetVariant("feature-1")

local toggle = clent:Toggle("feature-1")
if toggle:IsEnabled() then
  print("feature-1 is enabled")
else
  print("feature-1 is disabled")
end

local boolValue = client:BoolVariation("feature-1", false)
local stringValue = client:StringVariation("feature-1", "")
local numberValue = client:NumberVariation("feature-1", 123)
local jsonValue = client:JsonVariation("feature-1", {})
local variation = client:Variation("feature-1")

client:WatchToggle("feature-1", function(toggle)
end)

client:WatchToggleWithInitialState("feature-1", function(toggle)
end)

local watchToggleGroup = client:CreateWatchToggleGroup()
  :WatchToggle("feature-1", function(toggle)
  end)
  :WatchToggeWithInitialState("feature-1", function(toggle)
  end)

watchToggleGroup:UnwatchAll()

client:UpdateToggles()

client:SyncToggles()

client:Start()

client:Stop()

client:IsReady()
