# Feature Flags Client

이 라이브러리는 애플리케이션에서 기능 플래그를 관리하기 위한 클라이언트를 제공합니다. 동적 업데이트, 컨텍스트 기반 평가, 캐싱 메커니즘을 지원합니다.

## 설치

Lua 환경에서 다음 의존성이 필요합니다:
- `dkjson`
- `timer`
- `metrics-reporter`
- `storage-provider-inmemory`
- `event-emitter`
- `event-system`
- `util`
- `logger`
- `events`

## 초기화

클라이언트를 생성하려면 다음 필수 필드를 포함한 설정 테이블을 제공해야 합니다:

```lua
local Client = require("framework.3rdparty.feature-flags.client")

local client = Client.new({
  url = "https://feature-flags-server.com/api", -- 서버 URL
  clientKey = "your-client-key", -- 인증 키
  appName = "your-app-name", -- 애플리케이션 이름
  request = yourHttpRequestFunction, -- HTTP 요청 함수
  context = { -- 초기 컨텍스트 설정
    userId = "user123",
    sessionId = "session456",
    remoteAddress = "192.168.1.1",
    currentTime = os.time(),
    properties = {
      customField = "customValue"
    }
  },
  autoStart = true -- 자동 시작 여부
})
```

### 초기화 주의사항
1. `url`, `clientKey`, `appName`, `request`는 필수 필드입니다. 누락 시 오류가 발생합니다.
2. `context`는 초기 사용자 정보를 설정하는 데 사용됩니다. 이후 `updateContext`를 통해 동적으로 변경할 수 있습니다.
3. `autoStart`를 `true`로 설정하면 클라이언트가 자동으로 시작됩니다.

---

## 주요 메서드

### `client:isEnabled(toggleName)`
특정 기능 플래그가 활성화되었는지 확인합니다.

```lua
local isFeatureEnabled = client:isEnabled("feature_name")
print("Feature enabled:", isFeatureEnabled)
```

### `client:getVariant(toggleName)`
특정 기능 플래그의 변형(variant)을 가져옵니다.

```lua
local variant = client:getVariant("feature_name")
print("Variant name:", variant.name)
```

### `client:updateContext(context, callback)`
클라이언트 컨텍스트를 동적으로 업데이트합니다.

```lua
client:updateContext({
  userId = "newUserId",
  properties = {
    anotherField = "anotherValue"
  }
}, function()
  print("Context updated!")
end)
```

### `client:getContext()`
현재 컨텍스트를 가져옵니다.

```lua
local context = client:getContext()
print("Current context:", context)
```

### `client:setContextField(field, value)`
특정 컨텍스트 필드를 설정합니다.

```lua
client:setContextField("userId", "updatedUserId")
```

### `client:removeContextField(field)`
특정 컨텍스트 필드를 제거합니다.

```lua
client:removeContextField("userId")
```

---

## 클라이언트 시작 및 중지

### `client:start(callback)`
클라이언트를 시작하고 플래그 업데이트를 폴링합니다.

```lua
client:start(function()
  print("Client started!")
end)
```

### `client:stop()`
클라이언트를 중지하고 폴링을 멈춥니다.

```lua
client:stop()
```

---

## 이벤트 처리

### `client:on(event, callback)`
특정 이벤트에 대한 리스너를 등록합니다.

```lua
client:on("ready", function()
  print("Client is ready!")
end)
```

### `client:watch(featureName, callback)`
특정 기능 플래그의 변경 사항을 감시합니다.

```lua
client:watch("feature_name", function(toggle)
  print("Feature updated:", toggle)
end)
```

### `client:unwatch(featureName, callback)`
특정 기능 플래그의 감시를 중지합니다.

```lua
client:unwatch("feature_name")
```

---

## 이벤트 목록

클라이언트는 다음 이벤트를 발생시킵니다:
- `ready`: 클라이언트가 준비되었을 때 발생.
- `update`: 플래그가 업데이트되었을 때 발생.
- `error`: 오류가 발생했을 때 발생.
- `recovered`: 클라이언트가 오류에서 복구되었을 때 발생.

---

## 고급 설정

클라이언트는 다음과 같은 추가 설정 옵션을 지원합니다:
- `refreshInterval`: 플래그 업데이트를 폴링하는 간격(초). 기본값은 `30`.
- `disableRefresh`: `true`로 설정하면 폴링을 비활성화.
- `usePOSTrequests`: 플래그를 가져올 때 GET 대신 POST 요청 사용.
- `storageProvider`: 플래그 캐싱을 위한 사용자 정의 스토리지 제공자.
- `experimental`: `togglesStorageTTL`과 같은 실험적 기능.

---

## 주의사항

1. **정적 컨텍스트 필드**: `appName`, `environment`, `sessionId`는 동적으로 업데이트할 수 없습니다.
2. **컨텍스트 업데이트**: `updateContext` 또는 `setContextField`를 사용하여 동적 필드를 업데이트하세요.
3. **오류 처리**: 네트워크 요청에 대한 적절한 오류 처리를 구현하세요.
4. **이벤트 리스너**: 이벤트 리스너를 등록할 때 메모리 누수를 방지하기 위해 필요하지 않은 리스너는 제거하세요.

---

## 예제

### 기본 사용 예제

```lua
local client = Client.new({
  url = "https://feature-flags-server.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  request = yourHttpRequestFunction,
  autoStart = true
})

client:on("ready", function()
  print("Client is ready!")
  local isEnabled = client:isEnabled("example_feature")
  print("Feature enabled:", isEnabled)
end)
```

### 컨텍스트 업데이트 예제

```lua
client:updateContext({
  userId = "newUserId",
  properties = {
    customField = "newValue"
  }
}, function()
  print("Context updated!")
end)
```

### 플래그 감시 예제

```lua
client:watch("example_feature", function(toggle)
  print("Feature updated:", toggle)
end)
```
