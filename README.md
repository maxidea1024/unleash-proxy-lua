# Togglet Lua SDK

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/your-org/togglet-lua-sdk)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Lua](https://img.shields.io/badge/lua-5.1%2B-blue.svg)](https://www.lua.org/)

This is a Lua SDK for Togglet feature flags. It provides a simple and powerful way to manage feature flags in your Lua applications, including games, web applications.

## How to use the SDK

### Step 1: Installation

Include the Togglet module in your Lua project:

```lua
local Togglet = require("framework.3rdparty.togglet.index")
```

### Step 2: Initialize the SDK

Configure the client according to your needs. The following example provides only the required options:

```lua
local Togglet = require("framework.3rdparty.togglet.index")
local ToggletClient = Togglet.ToggletClient

-- Define HTTP request function (implement according to your environment)
local function httpRequest(options, callback)
  -- Implement actual HTTP request
  -- options: { url, method, headers, body }
  -- callback: function(error, response)
end

-- Initialize client
local client = ToggletClient.New({
  url = "https://your-togglet-server.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  request = httpRequest
})

-- Start the client
client:Start():Next(function()
  print("Togglet client is ready!")
end)
```

### Step 3: Let the client synchronize

You should wait for the client's `ready` or `init` events before you start working with it. Before it's ready, the client might not report the correct state for your features.

```lua
client:On(Togglet.Events.READY, function()
  if client:IsEnabled('my-feature') then
    print('my-feature is enabled')
  else
    print('my-feature is disabled')
  end
end)
```

The difference between the events is explained in the [Available events](#available-events) section.

### Step 4: Check feature toggle states

Once the client is ready, you can start checking features in your application. Use the `IsEnabled` method to check the state of any feature you want:

```lua
client:IsEnabled('my-feature')
```

You can use the `GetToggle` method to get a toggle proxy for an **enabled feature that has variants**. If the feature is disabled, you will get back a disabled toggle proxy.

```lua
local toggle = client:GetToggle('my-feature')

if toggle:IsEnabled() then
  local color = toggle:StringVariation('blue') -- default value: 'blue'
  setButtonColor(color)
end
```

You can also access the payload associated with the variant:

```lua
local toggle = client:GetToggle('my-feature')
local payload = toggle:JsonVariation({})

if payload.type == 'special' then
  -- do something with the payload
  print("Payload value:", payload.value)
end
```

#### Updating the Togglet context

The Togglet context is used to evaluate features against attributes of the current user. To update and configure the Togglet context in this SDK, use the `SetContextFields`, `SetContextField` and `RemoveContextField` methods.

```lua
-- Used to set multiple context fields
client:SetContextFields({
  userId = '1233',
  sessionId = 'session-456',
  customProperty = 'value'
})

-- Used to update a single field on the context
client:SetContextField('userId', '4141')

-- Used to remove a field from the context
client:RemoveContextField('customProperty')
```

### Alternative: Using ToggletClientBuilder

For more systematic and flexible configuration, you can use ToggletClientBuilder:

```lua
local Togglet = require("framework.3rdparty.togglet.index")
local ToggletClientBuilder = Togglet.ToggletClientBuilder

-- Basic online mode configuration
local client = ToggletClientBuilder.New("your-app-name")
    :Url("https://your-togglet-server.com/api")
    :ClientKey("your-client-key")
    :Request(httpRequest)
    :Environment("production")
    :RefreshInterval(15)
    :LogLevel("info")
    :Build()

-- Offline mode configuration
local offlineClient = ToggletClientBuilder.New("your-app-name")
    :Offline(true)
    :Bootstrap({
      { name = "feature-a", enabled = true },
      { name = "feature-b", enabled = false }
    })
    :DevMode(true)
    :LogLevel("debug")
    :Build()
```

## Available options

The Togglet SDK takes the following options:

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `url` | yes | n/a | The Togglet server URL to connect to. E.g.: `https://example.com/api` |
| `clientKey` | yes | n/a | The client key to be used for authentication |
| `appName` | yes | n/a | The name of the application using this SDK. Will be used as part of the metrics sent to server |
| `request` | yes | n/a | HTTP request function for making API calls |
| `refreshInterval` | no | 30 | How often, in seconds, the SDK should check for updated toggle configuration. If set to 0 will disable checking for updates |
| `disableRefresh` | no | false | If set to true, the client will not check for updated toggle configuration |
| `metricsInterval` | no | 60 | How often, in seconds, the SDK should send usage metrics back to server |
| `disableMetrics` | no | false | Set this option to `true` if you want to disable usage metrics |
| `storageProvider` | no | `InMemoryStorageProvider` | Allows you to inject a custom storage provider |
| `bootstrap` | no | `nil` | Allows you to bootstrap the cached feature toggle configuration |
| `bootstrapOverride` | no | `true` | Should the bootstrap automatically override cached data in the local storage |
| `offline` | no | `false` | Set to true to run in offline mode (requires bootstrap data) |
| `useExplicitSyncMode` | no | `false` | Set to true to enable explicit synchronization mode |
| `environment` | no | `nil` | Environment name (e.g., "production", "development") |
| `enableDevMode` | no | `false` | Enable development mode for additional logging |
| `loggerFactory` | no | `nil` | Custom logger factory for logging |
| `customHeaders` | no | `{}` | Additional headers to use when making HTTP requests |
| `experimental` | no | `{}` | Experimental features configuration |

## Listen for updates

The client is also an event emitter. This means that your code can subscribe to updates from the client. This is a neat way to update your app when toggle state updates.

```lua
client:On(Togglet.Events.UPDATE, function()
  local myToggle = client:IsEnabled('my-feature')
  -- do something useful
end)
```

### Available events:

- **error** - emitted when an error occurs on init, or when fetch function fails, or when fetch receives a non-ok response object. The error object is sent as payload.
- **init** - emitted after the SDK has read local cached data in the storageProvider.
- **ready** - emitted after the SDK has successfully started and performed the initial fetch towards the Togglet server.
- **update** - emitted every time the Togglet server returns a new feature toggle configuration. The SDK will emit this event as part of the initial fetch from the SDK.

> **Note:** Please remember that you should always register your event listeners before you call `client:Start()`. If you register them after you have started the SDK you risk losing important events.

## Stop the SDK

You can stop the Togglet client by calling the `Stop` method. Once the client has been stopped, it will no longer check for updates or send metrics to the server.

A stopped client _can_ be restarted.

```lua
client:Stop()
```

## Bootstrap

Now it is possible to bootstrap the SDK with your own feature toggle configuration when you don't want to make an API call.

This is also useful if you require the toggles to be in a certain state immediately after initializing the SDK.

### How to use it?

Add a `bootstrap` attribute when creating a new `ToggletClient`. There's also a `bootstrapOverride` attribute which by default is `true`.

```lua
local client = ToggletClient.New({
  url = "https://your-server.com/api",
  clientKey = "your-client-key",
  appName = "my-app",
  request = httpRequest,
  bootstrapOverride = false,
  bootstrap = {
    { name = "feature-a", enabled = true },
    { name = "feature-b", enabled = false, variant = {
      name = "blue",
      enabled = true,
      payload = { type = "string", value = "blue-theme" }
    }}
  }
})
```

**NOTES: ⚠️**

- If `bootstrapOverride` is `true` (by default), any local cached data will be overridden with the bootstrap specified.
- If `bootstrapOverride` is `false` any local cached data will not be overridden unless the local cache is empty.

## Manage your own refresh mechanism

You can opt out of the Togglet feature flag auto-refresh mechanism and metrics update by setting the `refreshInterval` and/or `metricsInterval` options to `0`. In this case, it becomes your responsibility to call `UpdateToggles` and/or `SendMetrics` methods.

```lua
local client = ToggletClient.New({
  url = "https://your-server.com/api",
  clientKey = "your-client-key",
  appName = "my-app",
  request = httpRequest,
  refreshInterval = 0, -- Disable auto-refresh
  metricsInterval = 0  -- Disable auto-metrics
})

-- Manually update toggles when needed
client:UpdateToggles():Next(function()
  print("Toggles updated manually")
end)
```

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### License

[MIT license](LICENSE)
