local ToggletConfigBuilder = require("framework.3rdparty.togglet.togglet-config-builder")
local ToggletClient = require("framework.3rdparty.togglet.togglet-client")

-- Test helper functions
local function assertNotNil(value, message)
  assert(value ~= nil, message or "Value should not be nil")
end

local function assertEquals(expected, actual, message)
  assert(expected == actual, (message or "Values should be equal") ..
    string.format(" (expected: %s, got: %s)", tostring(expected), tostring(actual)))
end

local function assertError(expectedErrorPattern, fn, ...)
  local success, error = pcall(fn, ...)
  assert(not success, "Expected function to throw an error, but it succeeded")
  assert(string.match(error, expectedErrorPattern),
    string.format("Error message '%s' does not match expected pattern '%s'", error, expectedErrorPattern))
end

-- Sample bootstrap data for tests
local sampleBootstrap = {
  {
    name = "feature-a",
    enabled = true,
    variant = {
      name = "variant-1",
      enabled = true,
      payload = {
        type = "string",
        value = "test-value"
      }
    }
  },
  {
    name = "feature-b",
    enabled = false
  }
}

-- Test suite
local tests = {}

-- Test basic offline configuration
function tests.testBasicOfflineConfig()
  print("Running test: Basic offline configuration")

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :Build()

  assertNotNil(config, "Config should be created")
  assertEquals("test-app", config.appName, "App name should match")
  assertEquals(true, config.offline, "Offline mode should be enabled")
  assertNotNil(config.bootstrap, "Bootstrap data should be set")
  assertEquals(2, #config.bootstrap, "Bootstrap should contain 2 features")
end

-- Test offline mode requires bootstrap data
function tests.testOfflineModeRequiresBootstrap()
  print("Running test: Offline mode requires bootstrap data")

  assertError("Bootstrap data is required in offline mode", function()
    ToggletConfigBuilder.New("test-app")
        :Offline(true)
        :Build()
  end)
end

-- Test offline mode with development mode
function tests.testOfflineModeWithDevMode()
  print("Running test: Offline mode with development mode")

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :DevMode(true)
      :Build()

  assertEquals(true, config.offline, "Offline mode should be enabled")
  assertEquals(true, config.enableDevMode, "Dev mode should be enabled")
end

-- Test offline mode with custom logger
function tests.testOfflineModeWithCustomLogger()
  print("Running test: Offline mode with custom logger")

  -- Mock logger factory
  local mockLoggerFactory = {
    CreateLogger = function(self, name)
      return {
        Debug = function() end,
        Info = function() end,
        Warn = function() end,
        Error = function() end
      }
    end
  }

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :LoggerFactory(mockLoggerFactory)
      :Build()

  assertNotNil(config.loggerFactory, "Logger factory should be set")
end

-- Test offline mode with log level
function tests.testOfflineModeWithLogLevel()
  print("Running test: Offline mode with log level")

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :LogLevel("debug")
      :Build()

  assertNotNil(config.loggerFactory, "Logger factory should be created")
end

-- Test offline mode with custom storage provider
function tests.testOfflineModeWithCustomStorage()
  print("Running test: Offline mode with custom storage provider")

  -- Mock storage provider
  local mockStorageProvider = {
    Get = function() return nil end,
    Set = function() return true end,
    Delete = function() return true end
  }

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :StorageProvider(mockStorageProvider)
      :Build()

  assertEquals(mockStorageProvider, config.storageProvider, "Storage provider should be set")
end

-- Test offline mode with bootstrap override
function tests.testOfflineModeWithBootstrapOverride()
  print("Running test: Offline mode with bootstrap override")

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :BootstrapOverride(true)
      :Build()

  assertEquals(true, config.bootstrapOverride, "Bootstrap override should be enabled")
end

-- Test offline mode with metrics disabled
function tests.testOfflineModeWithMetricsDisabled()
  print("Running test: Offline mode with metrics disabled")

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :DisableMetrics(true)
      :Build()

  assertEquals(true, config.disableMetrics, "Metrics should be disabled")
end

-- Test offline mode with impression data
function tests.testOfflineModeWithImpressionData()
  print("Running test: Offline mode with impression data")

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :ImpressionDataAll(true)
      :Build()

  assertEquals(true, config.impressionDataAll, "Impression data should be enabled")
end

-- Test offline mode with context
function tests.testOfflineModeWithContext()
  print("Running test: Offline mode with context")

  local testContext = {
    userId = "user-123",
    sessionId = "session-456",
    properties = {
      region = "us-east",
      platform = "desktop"
    }
  }

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :Context(testContext)
      :Build()

  assertNotNil(config.context, "Context should be set")
  assertEquals("user-123", config.context.userId, "User ID should match")
end

-- Test offline mode with experimental features
function tests.testOfflineModeWithExperimental()
  print("Running test: Offline mode with experimental features")

  local experimental = {
    featureX = true,
    featureY = false
  }

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :Experimental(experimental)
      :Build()

  assertNotNil(config.experimental, "Experimental features should be set")
  assertEquals(true, config.experimental.featureX, "Feature X should be enabled")
end

-- Test offline mode with toggles storage TTL
function tests.testOfflineModeWithTogglesStorageTTL()
  print("Running test: Offline mode with toggles storage TTL")

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :TogglesStorageTTL(3600)
      :Build()

  assertNotNil(config.experimental, "Experimental features should be created")
  assertEquals(3600, config.experimental.togglesStorageTTL, "TTL should be set to 3600")
end

-- Test creating client with offline config
function tests.testCreateClientWithOfflineConfig()
  print("Running test: Create client with offline config")

  local config = ToggletConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :Build()

  local client = ToggletClient.New(config)
  assertNotNil(client, "ToggletClient should be created")

  -- Test client is ready immediately in offline mode
  assertEquals(true, client:IsReady(), "ToggletClient should be ready immediately in offline mode")

  -- Test feature flags from bootstrap
  assertEquals(true, client:IsEnabled("feature-a"), "Feature A should be enabled")
  assertEquals(false, client:IsEnabled("feature-b"), "Feature B should be disabled")
  assertEquals(false, client:IsEnabled("non-existent-feature"), "Non-existent feature should be disabled")

  -- Test variant
  local variant = client:GetVariant("feature-a")
  assertNotNil(variant, "Variant should exist")
  assertEquals("variant-1", variant:VariantName(), "Variant name should match")
  assertEquals("test-value", variant:StringVariation("default"), "Variant value should match")
end

-- Run all tests
local function runAllTests()
  print("=== Running ToggletConfigBuilder Offline Mode Tests ===")
  local passedCount = 0
  local failedCount = 0

  for name, testFn in pairs(tests) do
    local success, error = pcall(testFn)
    if success then
      print("✓ " .. name .. " passed")
      passedCount = passedCount + 1
    else
      print("✗ " .. name .. " failed: " .. error)
      failedCount = failedCount + 1
    end
  end

  print("=== Test Results ===")
  print(string.format("Passed: %d, Failed: %d, Total: %d",
    passedCount, failedCount, passedCount + failedCount))

  return failedCount == 0
end

-- Execute tests
return runAllTests()
