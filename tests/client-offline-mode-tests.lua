local UnleashConfigBuilder = require("framework.3rdparty.unleash.unleash-config-builder")
local UnleashClient = require("framework.3rdparty.unleash.unleash-client")
local Util = require("framework.3rdparty.unleash.util")

-- Test helper functions
local function assertNotNil(value, message)
  assert(value ~= nil, message or "Value should not be nil")
end

local function assertEquals(expected, actual, message)
  assert(expected == actual, (message or "Values should be equal") ..
    string.format(" (expected: %s, got: %s)", tostring(expected), tostring(actual)))
end

local function assertNotEquals(expected, actual, message)
  assert(expected ~= actual, (message or "Values should not be equal") ..
    string.format(" (both: %s)", tostring(actual)))
end

local function assertTrue(value, message)
  assert(value == true, message or "Value should be true")
end

local function assertFalse(value, message)
  assert(value == false, message or "Value should be false")
end

local function assertTableEquals(expected, actual, message)
  assert(type(expected) == "table", "Expected value should be a table")
  assert(type(actual) == "table", "Actual value should be a table")

  local missing = {}
  local unexpected = {}
  local different = {}

  for k, v in pairs(expected) do
    if actual[k] == nil then
      table.insert(missing, k)
    elseif type(v) == "table" and type(actual[k]) == "table" then
      -- Skip deep comparison for tables
    elseif v ~= actual[k] then
      different[k] = { expected = v, actual = actual[k] }
    end
  end

  for k, v in pairs(actual) do
    if expected[k] == nil then
      table.insert(unexpected, k)
    end
  end

  if #missing > 0 or #unexpected > 0 or next(different) ~= nil then
    local errorMsg = message or "Tables are not equal"
    if #missing > 0 then
      errorMsg = errorMsg .. "\nMissing keys: " .. table.concat(missing, ", ")
    end
    if #unexpected > 0 then
      errorMsg = errorMsg .. "\nUnexpected keys: " .. table.concat(unexpected, ", ")
    end
    if next(different) ~= nil then
      errorMsg = errorMsg .. "\nDifferent values:"
      for k, v in pairs(different) do
        errorMsg = errorMsg .. string.format("\n  %s: expected %s, got %s",
          k, tostring(v.expected), tostring(v.actual))
      end
    end
    error(errorMsg)
  end
end

local function assertError(expectedErrorPattern, fn, ...)
  local success, error = pcall(fn, ...)
  assert(not success, "Expected function to throw an error, but it succeeded")
  assert(string.match(error, expectedErrorPattern),
    string.format("Error message '%s' does not match expected pattern '%s'", error, expectedErrorPattern))
end

-- Mock event emitter for testing
local function createMockEventEmitter()
  local events = {}

  return {
    on = function(self, event, callback)
      events[event] = events[event] or {}
      table.insert(events[event], callback)
      return function() -- Return unsubscribe function
        for i, cb in ipairs(events[event]) do
          if cb == callback then
            table.remove(events[event], i)
            break
          end
        end
      end
    end,

    emit = function(self, event, ...)
      if events[event] then
        for _, callback in ipairs(events[event]) do
          callback(...)
        end
      end
    end,

    getListenerCount = function(self, event)
      return events[event] and #events[event] or 0
    end
  }
end

-- Sample bootstrap data for tests
local sampleBootstrap = {
  {
    name = "string-feature",
    enabled = true,
    variant = {
      name = "string-variant",
      enabled = true,
      payload = {
        type = "string",
        value = "string-value"
      }
    }
  },
  {
    name = "number-feature",
    enabled = true,
    variant = {
      name = "number-variant",
      enabled = true,
      payload = {
        type = "number",
        value = 42
      }
    }
  },
  {
    name = "boolean-feature",
    enabled = true,
    variant = {
      name = "boolean-variant",
      enabled = true,
      payload = {
        type = "boolean",
        value = true
      }
    }
  },
  {
    name = "json-feature",
    enabled = true,
    variant = {
      name = "json-variant",
      enabled = true,
      payload = {
        type = "json",
        value = {
          key1 = "value1",
          key2 = 2,
          nested = {
            nestedKey = "nestedValue"
          }
        }
      }
    }
  },
  {
    name = "disabled-feature",
    enabled = false
  },
  {
    name = "feature-with-disabled-variant",
    enabled = true,
    variant = {
      name = "disabled-variant",
      enabled = false,
      payload = {
        type = "string",
        value = "should-not-be-used"
      }
    }
  }
}

-- Test suite
local tests = {}

-- Test client creation in offline mode
function tests.testClientCreationOffline()
  print("Running test: UnleashClient creation in offline mode")

  local config = UnleashConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(sampleBootstrap)
      :Build()

  local client = UnleashClient.New(config)
  assertNotNil(client, "UnleashClient should be created")
  assertTrue(client:IsReady(), "UnleashClient should be ready immediately in offline mode")
end

-- Test feature flag evaluation in offline mode
function tests.testFeatureFlagEvaluation()
  print("Running test: Feature flag evaluation in offline mode")

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :Build())

  -- Test enabled features
  assertTrue(client:IsEnabled("string-feature"), "String feature should be enabled")
  assertTrue(client:IsEnabled("number-feature"), "Number feature should be enabled")
  assertTrue(client:IsEnabled("boolean-feature"), "Boolean feature should be enabled")
  assertTrue(client:IsEnabled("json-feature"), "JSON feature should be enabled")

  -- Test disabled features
  assertFalse(client:IsEnabled("disabled-feature"), "Disabled feature should be disabled")

  -- Test non-existent features
  assertFalse(client:IsEnabled("non-existent-feature"), "Non-existent feature should be disabled")
end

-- Test variant retrieval in offline mode
function tests.testVariantRetrieval()
  print("Running test: Variant retrieval in offline mode")

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :Build())

  -- Test string variant
  local stringVariant = client:GetVariant("string-feature")
  assertNotNil(stringVariant, "String variant should exist")
  assertEquals("string-variant", stringVariant:VariantName(), "String variant name should match")
  assertEquals("string-value", stringVariant:StringVariation("default"), "String variant value should match")

  -- Test number variant
  local numberVariant = client:GetVariant("number-feature")
  assertNotNil(numberVariant, "Number variant should exist")
  assertEquals("number-variant", numberVariant:VariantName(), "Number variant name should match")
  assertEquals(42, numberVariant:NumberVariation(0), "Number variant value should match")

  -- Test boolean variant
  local booleanVariant = client:GetVariant("boolean-feature")
  assertNotNil(booleanVariant, "Boolean variant should exist")
  assertEquals("boolean-variant", booleanVariant:VariantName(), "Boolean variant name should match")
  assertEquals(true, booleanVariant:BoolVariation(false), "Boolean variant value should match")

  -- Test JSON variant
  local jsonVariant = client:GetVariant("json-feature")
  assertNotNil(jsonVariant, "JSON variant should exist")
  assertEquals("json-variant", jsonVariant:VariantName(), "JSON variant name should match")
  local jsonValue = jsonVariant:JsonVariation({})
  assertNotNil(jsonValue, "JSON value should exist")
  assertEquals("value1", jsonValue.key1, "JSON value key1 should match")
  assertEquals(2, jsonValue.key2, "JSON value key2 should match")
  assertNotNil(jsonValue.nested, "JSON nested value should exist")
  assertEquals("nestedValue", jsonValue.nested.nestedKey, "JSON nested value should match")

  -- Test disabled variant
  local disabledVariant = client:GetVariant("disabled-feature")
  assertNotNil(disabledVariant, "Disabled variant should exist")
  assertFalse(disabledVariant:IsEnabled(), "Disabled variant should be disabled")

  -- Test feature with disabled variant
  local featureWithDisabledVariant = client:GetVariant("feature-with-disabled-variant")
  assertNotNil(featureWithDisabledVariant, "Feature with disabled variant should exist")
  assertTrue(featureWithDisabledVariant:IsEnabled(), "Feature with disabled variant should be enabled")
  assertFalse(featureWithDisabledVariant:VariantIsEnabled(), "Variant should be disabled")

  -- Test non-existent variant
  local nonExistentVariant = client:GetVariant("non-existent-feature")
  assertNotNil(nonExistentVariant, "Non-existent variant should return a default variant")
  assertFalse(nonExistentVariant:IsEnabled(), "Non-existent variant should be disabled")
end

-- Test default values for variants
function tests.testVariantDefaultValues()
  print("Running test: Variant default values in offline mode")

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :Build())

  -- Test default values for non-existent feature
  local nonExistentVariant = client:GetVariant("non-existent-feature")
  assertEquals("default-string", nonExistentVariant:StringVariation("default-string"),
    "Default string should be returned")
  assertEquals(123, nonExistentVariant:NumberVariation(123), "Default number should be returned")
  assertEquals(true, nonExistentVariant:BoolVariation(true), "Default boolean should be returned")
  local defaultJson = { default = "json" }
  assertTableEquals(defaultJson, nonExistentVariant:JsonVariation(defaultJson), "Default JSON should be returned")

  -- Test type conversion for variants
  local stringVariant = client:GetVariant("string-feature")
  assertEquals(0, stringVariant:NumberVariation(0), "String should not convert to number")
  assertEquals(false, stringVariant:BoolVariation(false), "String should not convert to boolean")
  assertTableEquals({}, stringVariant:JsonVariation({}), "String should not convert to JSON")

  -- Test disabled feature with default values
  local disabledVariant = client:GetVariant("disabled-feature")
  assertEquals("default-for-disabled", disabledVariant:StringVariation("default-for-disabled"),
    "Default should be used for disabled feature")
end

-- Test context in offline mode
function tests.testContextInOfflineMode()
  print("Running test: Context in offline mode")

  local initialContext = {
    userId = "user-123",
    sessionId = "session-456",
    properties = {
      region = "us-east",
      platform = "desktop"
    }
  }

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :Context(initialContext)
    :Build())

  -- Context updates should work but not affect feature evaluation in offline mode
  local updateCalled = false
  client:UpdateContext({
    userId = "user-456",
    properties = {
      region = "eu-west",
      platform = "mobile"
    }
  }, function()
    updateCalled = true
  end)

  assertTrue(updateCalled, "Context update callback should be called")
  assertTrue(client:IsEnabled("string-feature"), "Feature should still be enabled after context update")
end

-- Test impression events in offline mode
function tests.testImpressionEventsOffline()
  print("Running test: Impression events in offline mode")

  local impressionEvents = {}
  local mockEventEmitter = createMockEventEmitter()

  -- Create a client with impression data enabled
  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :ImpressionDataAll(true)
    :Build())

  -- Replace the event emitter with our mock
  client._events = mockEventEmitter

  -- Listen for impression events
  mockEventEmitter:on("impression", function(event)
    table.insert(impressionEvents, event)
  end)

  -- Generate some impression events
  client:IsEnabled("string-feature")
  client:IsEnabled("disabled-feature")
  client:GetVariant("json-feature")

  assertEquals(3, #impressionEvents, "Should have 3 impression events")

  -- Check the first event (IsEnabled for string-feature)
  assertEquals("isEnabled", impressionEvents[1].eventType, "First event should be isEnabled")
  assertEquals("string-feature", impressionEvents[1].featureName, "First event feature name should match")
  assertTrue(impressionEvents[1].enabled, "First event should be enabled")

  -- Check the second event (IsEnabled for disabled-feature)
  assertEquals("isEnabled", impressionEvents[2].eventType, "Second event should be isEnabled")
  assertEquals("disabled-feature", impressionEvents[2].featureName, "Second event feature name should match")
  assertFalse(impressionEvents[2].enabled, "Second event should be disabled")

  -- Check the third event (GetVariant for json-feature)
  assertEquals("getVariant", impressionEvents[3].eventType, "Third event should be getVariant")
  assertEquals("json-feature", impressionEvents[3].featureName, "Third event feature name should match")
  assertEquals("json-variant", impressionEvents[3].variantName, "Third event variant name should match")
end

-- Test watch toggle in offline mode
function tests.testWatchToggleOffline()
  print("Running test: Watch toggle in offline mode")

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :Build())

  -- Test WatchToggle
  local watchCallCount = 0
  local lastVariant = nil

  local unsubscribe = client:WatchToggle("string-feature", function(variant)
    watchCallCount = watchCallCount + 1
    lastVariant = variant
  end)

  -- In offline mode, the watch callback should be called immediately with the current state
  assertEquals(1, watchCallCount, "Watch callback should be called once")
  assertNotNil(lastVariant, "Variant should be provided to callback")
  assertEquals("string-feature", lastVariant:FeatureName(), "Feature name should match")
  assertEquals("string-variant", lastVariant:VariantName(), "Variant name should match")

  -- Unsubscribe should work
  unsubscribe()

  -- Test WatchToggleWithInitialState
  local initialStateCallCount = 0
  local initialStateVariant = nil

  client:WatchToggleWithInitialState("number-feature", function(variant)
    initialStateCallCount = initialStateCallCount + 1
    initialStateVariant = variant
  end)

  assertEquals(1, initialStateCallCount, "Initial state callback should be called once")
  assertNotNil(initialStateVariant, "Variant should be provided to initial state callback")
  assertEquals("number-feature", initialStateVariant:FeatureName(), "Feature name should match")
  assertEquals("number-variant", initialStateVariant:VariantName(), "Variant name should match")
end

-- Test bootstrap override in offline mode
function tests.testBootstrapOverrideOffline()
  print("Running test: Bootstrap override in offline mode")

  -- Create a client with bootstrap override enabled
  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :BootstrapOverride(true)
    :Build())

  -- Even with bootstrap override, in offline mode the bootstrap data should be used
  assertTrue(client:IsEnabled("string-feature"), "String feature should be enabled")
  assertFalse(client:IsEnabled("disabled-feature"), "Disabled feature should be disabled")

  -- Test with a different bootstrap but same override setting
  local differentBootstrap = {
    {
      name = "string-feature",
      enabled = false -- Different from original bootstrap
    },
    {
      name = "new-feature",
      enabled = true
    }
  }

  local client2 = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(differentBootstrap)
    :BootstrapOverride(true)
    :Build())

  assertFalse(client2:IsEnabled("string-feature"), "String feature should now be disabled")
  assertTrue(client2:IsEnabled("new-feature"), "New feature should be enabled")
  assertFalse(client2:IsEnabled("disabled-feature"), "Original disabled feature should not exist")
end

-- Test sync toggles in offline mode
function tests.testSyncTogglesOffline()
  print("Running test: Sync toggles in offline mode")

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :Build())

  local syncCalled = false
  client:SyncToggles(true, function()
    syncCalled = true
  end)

  assertTrue(syncCalled, "Sync callback should be called even in offline mode")
  assertTrue(client:IsEnabled("string-feature"), "Features should still be available after sync")
end

-- Test client with empty bootstrap in offline mode
function tests.testEmptyBootstrapOffline()
  print("Running test: Empty bootstrap in offline mode")

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap({}) -- Empty bootstrap
    :Build())

  assertTrue(client:IsReady(), "UnleashClient should be ready with empty bootstrap")
  assertFalse(client:IsEnabled("any-feature"), "No features should be enabled with empty bootstrap")

  local variant = client:GetVariant("any-feature")
  assertNotNil(variant, "Should get a default variant")
  assertFalse(variant:IsEnabled(), "Default variant should be disabled")
  assertEquals("default", variant:StringVariation("default"), "Default value should be returned")
end

-- Test client with complex bootstrap data
function tests.testComplexBootstrapOffline()
  print("Running test: Complex bootstrap in offline mode")

  -- Create complex bootstrap with nested variants and different payload types
  local complexBootstrap = {
    {
      name = "complex-feature",
      enabled = true,
      variant = {
        name = "complex-variant",
        enabled = true,
        payload = {
          type = "json",
          value = {
            strings = { "value1", "value2", "value3" },
            numbers = { 1, 2, 3, 4, 5 },
            booleans = { true, false, true },
            nested = {
              level1 = {
                level2 = {
                  level3 = "deep-value"
                }
              }
            }
          }
        }
      }
    }
  }

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(complexBootstrap)
    :Build())

  assertTrue(client:IsEnabled("complex-feature"), "Complex feature should be enabled")

  local variant = client:GetVariant("complex-feature")
  assertNotNil(variant, "Complex variant should exist")
  assertEquals("complex-variant", variant:VariantName(), "Complex variant name should match")

  local jsonValue = variant:JsonVariation({})
  assertNotNil(jsonValue, "JSON value should exist")
  assertNotNil(jsonValue.strings, "Strings array should exist")
  assertEquals(3, #jsonValue.strings, "Strings array should have 3 elements")
  assertEquals("value2", jsonValue.strings[2], "Second string should match")

  assertNotNil(jsonValue.nested, "Nested object should exist")
  assertNotNil(jsonValue.nested.level1, "Level 1 should exist")
  assertNotNil(jsonValue.nested.level1.level2, "Level 2 should exist")
  assertEquals("deep-value", jsonValue.nested.level1.level2.level3, "Deep value should match")
end

-- Test error handling in offline mode
function tests.testErrorHandlingOffline()
  print("Running test: Error handling in offline mode")

  -- Test with invalid bootstrap data
  local invalidBootstrap = "not a table"

  assertError("bootstrap must be a table", function()
    UnleashClient.New(UnleashConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(invalidBootstrap)
      :Build())
  end)

  -- Test with invalid feature in bootstrap
  local invalidFeatureBootstrap = {
    "not a feature object"
  }

  assertError("feature must be a table", function()
    UnleashClient.New(UnleashConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(invalidFeatureBootstrap)
      :Build())
  end)

  -- Test with missing feature name
  local missingNameBootstrap = {
    {
      enabled = true
    }
  }

  assertError("feature must have a name", function()
    UnleashClient.New(UnleashConfigBuilder.New("test-app")
      :Offline(true)
      :Bootstrap(missingNameBootstrap)
      :Build())
  end)
end

-- Test multiple clients with different bootstrap data
function tests.testMultipleClientsOffline()
  print("Running test: Multiple clients in offline mode")

  local client1 = UnleashClient.New(UnleashConfigBuilder.New("app1")
    :Offline(true)
    :Bootstrap({
      {
        name = "feature-1",
        enabled = true
      }
    })
    :Build())

  local client2 = UnleashClient.New(UnleashConfigBuilder.New("app2")
    :Offline(true)
    :Bootstrap({
      {
        name = "feature-2",
        enabled = true
      }
    })
    :Build())

  assertTrue(client1:IsEnabled("feature-1"), "Feature 1 should be enabled in client 1")
  assertFalse(client1:IsEnabled("feature-2"), "Feature 2 should not exist in client 1")

  assertFalse(client2:IsEnabled("feature-1"), "Feature 1 should not exist in client 2")
  assertTrue(client2:IsEnabled("feature-2"), "Feature 2 should be enabled in client 2")
end

-- Test client with delayed bootstrap data
function tests.testDelayedBootstrapOffline()
  print("Running test: Delayed bootstrap in offline mode")

  -- Create client without bootstrap initially
  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Build())

  assertTrue(client:IsReady(), "UnleashClient should be ready even without bootstrap")
  assertFalse(client:IsEnabled("any-feature"), "No features should be enabled without bootstrap")

  -- Set bootstrap data after client creation
  client:SetBootstrap({
    {
      name = "delayed-feature",
      enabled = true
    }
  })

  assertTrue(client:IsEnabled("delayed-feature"), "Delayed feature should be enabled after setting bootstrap")
end

-- Test client with custom logger
function tests.testCustomLoggerOffline()
  print("Running test: Custom logger in offline mode")

  local logMessages = {}
  local customLogger = {
    debug = function(message) table.insert(logMessages, { level = "debug", message = message }) end,
    info = function(message) table.insert(logMessages, { level = "info", message = message }) end,
    warn = function(message) table.insert(logMessages, { level = "warn", message = message }) end,
    error = function(message) table.insert(logMessages, { level = "error", message = message }) end
  }

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :Logger(customLogger)
    :Build())

  assertTrue(#logMessages > 0, "Logger should have received messages")

  -- Check for client initialization log
  local foundInitLog = false
  for _, log in ipairs(logMessages) do
    if log.level == "info" and string.match(log.message, "UnleashClient initialized in offline mode") then
      foundInitLog = true
      break
    end
  end

  assertTrue(foundInitLog, "Should log client initialization in offline mode")
end

-- Test client with custom storage
function tests.testCustomStorageOffline()
  print("Running test: Custom storage in offline mode")

  local storage = {}
  local customStorage = {
    get = function(key) return storage[key] end,
    set = function(key, value) storage[key] = value end,
    remove = function(key) storage[key] = nil end
  }

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :Storage(customStorage)
    :Build())

  -- In offline mode, storage should still work but not be necessary
  assertTrue(client:IsReady(), "UnleashClient should be ready with custom storage")
  assertTrue(client:IsEnabled("string-feature"), "Features should be available with custom storage")
end

-- Test client with custom event handlers
function tests.testCustomEventHandlersOffline()
  print("Running test: Custom event handlers in offline mode")

  local events = {}

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(sampleBootstrap)
    :Build())

  -- Add custom event handlers
  client:On("ready", function() table.insert(events, "ready") end)
  client:On("error", function(err) table.insert(events, "error: " .. err) end)
  client:On("update", function() table.insert(events, "update") end)

  -- In offline mode, ready event should be fired immediately
  assertEquals(1, #events, "Should have one event")
  assertEquals("ready", events[1], "Ready event should be fired")

  -- Error events should still work
  client:EmitError("test-error")
  assertEquals(2, #events, "Should have two events")
  assertEquals("error: test-error", events[2], "Error event should be fired")
end

-- Test performance in offline mode with large bootstrap
function tests.testPerformanceWithLargeBootstrap()
  print("Running test: Performance with large bootstrap in offline mode")

  -- Create a large bootstrap with many features
  local largeBootstrap = {}
  for i = 1, 1000 do
    table.insert(largeBootstrap, {
      name = "feature-" .. i,
      enabled = i % 2 == 0,
      variant = {
        name = "variant-" .. i,
        enabled = i % 3 == 0,
        payload = {
          type = "string",
          value = "value-" .. i
        }
      }
    })
  end

  local startTime = os.clock()

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(largeBootstrap)
    :Build())

  local initTime = os.clock() - startTime
  print("Initialization time with 1000 features: " .. initTime .. " seconds")

  -- Test lookup performance
  startTime = os.clock()
  for i = 1, 1000 do
    client:IsEnabled("feature-" .. i)
  end

  local lookupTime = os.clock() - startTime
  print("Lookup time for 1000 features: " .. lookupTime .. " seconds")

  -- Verify some random features
  assertTrue(client:IsEnabled("feature-2"), "Feature 2 should be enabled")
  assertFalse(client:IsEnabled("feature-1"), "Feature 1 should be disabled")

  local variant = client:GetVariant("feature-3")
  assertEquals("variant-3", variant:VariantName(), "Variant name should match")
  assertEquals("value-3", variant:StringVariation("default"), "Variant value should match")
end

-- Test client with feature dependencies
function tests.testFeatureDependenciesOffline()
  print("Running test: Feature dependencies in offline mode")

  -- Create bootstrap with dependent features
  local dependencyBootstrap = {
    {
      name = "parent-feature",
      enabled = true
    },
    {
      name = "child-feature",
      enabled = true,
      dependencies = { "parent-feature" }
    },
    {
      name = "grandchild-feature",
      enabled = true,
      dependencies = { "child-feature" }
    },
    {
      name = "orphan-feature",
      enabled = true,
      dependencies = { "non-existent-feature" }
    }
  }

  local client = UnleashClient.New(UnleashConfigBuilder.New("test-app")
    :Offline(true)
    :Bootstrap(dependencyBootstrap)
    :Build())

  -- Test feature dependencies
  assertTrue(client:IsEnabled("parent-feature"), "Parent feature should be enabled")
  assertTrue(client:IsEnabled("child-feature"), "Child feature should be enabled")
  assertTrue(client:IsEnabled("grandchild-feature"), "Grandchild feature should be enabled")

  -- Test feature with missing dependency
  assertFalse(client:IsEnabled("orphan-feature"), "Orphan feature should be disabled due to missing dependency")

  -- Modify bootstrap to disable parent feature
  client:SetBootstrap({
    {
      name = "parent-feature",
      enabled = false
    },
    {
      name = "child-feature",
      enabled = true,
      dependencies = { "parent-feature" }
    },
    {
      name = "grandchild-feature",
      enabled = true,
      dependencies = { "child-feature" }
    }
  })

  -- Test cascading dependencies
  assertFalse(client:IsEnabled("parent-feature"), "Parent feature should now be disabled")
  assertFalse(client:IsEnabled("child-feature"), "Child feature should be disabled due to parent")
  assertFalse(client:IsEnabled("grandchild-feature"), "Grandchild feature should be disabled due to parent chain")
end

-- Run all tests
local function runTests()
  print("Running offline mode tests...")
  local passCount = 0
  local failCount = 0

  for name, testFn in pairs(tests) do
    local success, err = pcall(testFn)
    if success then
      print("✓ " .. name .. " passed")
      passCount = passCount + 1
    else
      print("✗ " .. name .. " failed: " .. tostring(err))
      failCount = failCount + 1
    end
  end

  print("\nTest results: " .. passCount .. " passed, " .. failCount .. " failed")
  return failCount == 0
end

return {
  runTests = runTests
}
