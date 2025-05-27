# Togglet Lua SDK

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/your-org/togglet-lua-sdk)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Lua](https://img.shields.io/badge/lua-5.1%2B-blue.svg)](https://www.lua.org/)

Lua 애플리케이션을 위한 강력하고 유연한 피처 플래그 클라이언트입니다. 게임, 웹 애플리케이션, 서버 애플리케이션 등 다양한 Lua 환경에서 피처 플래그를 쉽게 관리할 수 있습니다.

## ✨ 주요 특징

- 🚀 **점진적 출시**: 새 기능을 일부 사용자에게만 먼저 제공하여 위험을 최소화
- 🧪 **A/B 테스트**: 다양한 기능 변형을 테스트하여 최적의 사용자 경험 발견
- 🐤 **카나리 배포**: 새 기능을 소수의 사용자에게 먼저 출시하여 문제 조기 발견
- 🎛️ **실시간 제어**: 코드 배포 없이 즉시 기능 활성화/비활성화
- 🎯 **타겟팅**: 사용자, 지역, 디바이스 등 다양한 조건에 따른 기능 제공
- 💎 **구독 기반**: 프리미엄 사용자에게만 특정 기능 제공
- 🎉 **이벤트 관리**: 특정 기간에만 활성화되는 기능 관리
- 📱 **오프라인 지원**: 네트워크 연결 없이도 동작하는 오프라인 모드
- 🔄 **실시간 동기화**: 서버와 실시간으로 플래그 상태 동기화
- 📊 **메트릭 수집**: 피처 사용량 및 성능 메트릭 자동 수집

## 🚀 빠른 시작

### 설치

Lua 프로젝트에 Togglet 모듈을 포함하세요:

```lua
local Togglet = require("framework.3rdparty.togglet.index")
```

### 기본 설정

```lua
local Togglet = require("framework.3rdparty.togglet.index")
local ToggletClient = Togglet.ToggletClient

-- HTTP 요청 함수 정의 (환경에 맞게 구현)
local function httpRequest(options, callback)
  -- 실제 HTTP 요청 구현
  -- options: { url, method, headers, body }
  -- callback: function(error, response)
end

-- 클라이언트 초기화
local client = ToggletClient.New({
  url = "https://your-togglet-server.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  request = httpRequest,

  -- 선택적 설정
  environment = "production",
  refreshInterval = 30, -- 30초마다 업데이트
  storageProvider = Togglet.InMemoryStorageProvider.New()
})

-- 클라이언트 시작
client:Start():Next(function()
  print("Togglet 클라이언트가 준비되었습니다!")
end)
```

### ToggletConfigBuilder를 활용한 설정

더 체계적이고 유연한 설정을 위해 ToggletConfigBuilder를 사용할 수 있습니다:

```lua
local Togglet = require("framework.3rdparty.togglet.index")
local ToggletConfigBuilder = Togglet.ToggletConfigBuilder

-- 기본 온라인 모드 설정
local client = ToggletConfigBuilder.New("your-app-name")
    :Url("https://your-togglet-server.com/api")
    :ClientKey("your-client-key")
    :Request(httpRequest)
    :Environment("production")
    :RefreshInterval(30)
    :LogLevel("info")
    :NewClient()

-- 오프라인 모드 설정
local offlineClient = ToggletConfigBuilder.New("your-app-name")
    :Offline(true)
    :Bootstrap({
      { name = "feature-a", enabled = true },
      { name = "feature-b", enabled = false }
    })
    :DevMode(true)
    :LogLevel("debug")
    :NewClient()

-- 고급 설정 예제
local advancedClient = ToggletConfigBuilder.New("your-app-name")
    :Url("https://your-togglet-server.com/api")
    :ClientKey("your-client-key")
    :Request(httpRequest)
    :Environment("production")
    :ExplicitSyncMode(true)
    :RefreshInterval(60)
    :MetricsInterval(120)
    :DisableMetrics(false)
    :ImpressionDataAll(true)
    :StorageProvider(Togglet.FileStorageProvider.New("/tmp/togglet", "myapp"))
    :Context({
      userId = "initial-user",
      properties = { region = "us-east" }
    })
    :CustomHeaders({
      ["X-Custom-Header"] = "custom-value"
    })
    :Experimental({
      togglesStorageTTL = 3600
    })
    :NewClient()
```

### 기본 사용법

```lua
-- 피처 플래그 확인
if client:IsEnabled("new-feature") then
  -- 새 기능이 활성화된 경우
  enableNewFeature()
else
  -- 기존 기능 사용
  useOldFeature()
end

-- 토글 프록시 사용 (GetToggle로 ToggleProxy 반환)
local toggle = client:GetToggle("button-color")
if toggle:IsEnabled() then
  local color = toggle:StringVariation("blue") -- 기본값: "blue"
  setButtonColor(color)
end

-- 컨텍스트 필드 설정
client:SetContextFields({
  userId = "user123",
  sessionId = "session456",
  customProperty = "value"
})

-- 이벤트 구독
client:On(Togglet.Events.UPDATE, function(toggles)
  print("피처 플래그가 업데이트되었습니다!")
end)

client:On(Togglet.Events.ERROR, function(error)
  print("오류 발생:", error.message)
end)
```

## 📖 주요 API

### ToggletClient

#### 생성자
- `ToggletClient.New(config)` - 새 클라이언트 인스턴스 생성

#### 메서드
- `Start()` - 클라이언트 시작 및 초기화
- `IsEnabled(featureName, forceSelectRealtimeToggle?)` - 피처 플래그 활성화 상태 확인
- `GetVariant(featureName, forceSelectRealtimeToggle?)` - 원시 변형 데이터 반환 (내부용)
- `GetToggle(featureName, forceSelectRealtimeToggle?)` - 피처 토글 프록시 가져오기 (ToggleProxy 반환, 권장)
- `SetContextFields(fields)` - 사용자 컨텍스트 필드들 설정
- `SetContextField(field, value)` - 단일 컨텍스트 필드 설정
- `RemoveContextField(field)` - 컨텍스트 필드 제거
- `GetContext()` - 현재 컨텍스트 가져오기
- `UpdateToggles()` - 서버에서 최신 플래그 정보 가져오기
- `SyncToggles(fetchNow?)` - 명시적 동기화 모드에서 플래그 동기화
- `Stop()` - 클라이언트 중지

#### 편의 메서드
- `BoolVariation(featureName, defaultValue, forceSelectRealtimeToggle?)` - 불린 값 직접 가져오기
- `NumberVariation(featureName, defaultValue, forceSelectRealtimeToggle?)` - 숫자 값 직접 가져오기
- `StringVariation(featureName, defaultValue, forceSelectRealtimeToggle?)` - 문자열 값 직접 가져오기
- `JsonVariation(featureName, defaultValue, forceSelectRealtimeToggle?)` - JSON 값 직접 가져오기
- `Variation(featureName, defaultVariantName, forceSelectRealtimeToggle?)` - 변형 이름 직접 가져오기

#### 이벤트
- `Events.READY` - 클라이언트 준비 완료
- `Events.UPDATE` - 플래그 업데이트
- `Events.ERROR` - 오류 발생
- `Events.IMPRESSION` - 피처 사용 이벤트

### ToggleProxy

`GetToggle()` 메서드가 반환하는 토글 프록시 객체 (권장 사용법):

- `IsEnabled()` - 토글이 활성화되었는지 확인
- `FeatureName()` - 피처 이름 반환
- `VariantName(defaultVariantName?)` - 변형 이름 반환
- `RawVariant()` - 원시 변형 데이터 반환
- `BoolVariation(defaultValue)` - 불린 값 가져오기
- `StringVariation(defaultValue)` - 문자열 값 가져오기
- `NumberVariation(defaultValue)` - 숫자 값 가져오기
- `JsonVariation(defaultValue)` - JSON 객체 값 가져오기
- `GetPayloadType()` - 페이로드 타입 반환

### ToggletConfigBuilder

설정을 체계적으로 구성하기 위한 빌더 패턴 클래스:

#### 생성자
- `ToggletConfigBuilder.New(appName)` - 새 설정 빌더 생성

#### 필수 설정 메서드 (온라인 모드)
- `Url(url)` - Togglet 서버 URL 설정
- `ClientKey(clientKey)` - 클라이언트 인증 키 설정
- `Request(requestFn)` - HTTP 요청 함수 설정

#### 모드 설정 메서드
- `Offline(offline?)` - 오프라인 모드 활성화 (기본값: true)
- `DevMode(devMode?)` - 개발 모드 활성화 (기본값: true)
- `ExplicitSyncMode(explicitSync?)` - 명시적 동기화 모드 활성화 (기본값: true)

#### 환경 및 컨텍스트 설정
- `Environment(environment)` - 환경 설정 (예: "production", "development")
- `Context(context)` - 초기 컨텍스트 설정

#### 데이터 설정
- `Bootstrap(bootstrap)` - 부트스트랩 데이터 설정 (오프라인 모드 필수)
- `BootstrapOverride(override?)` - 부트스트랩 데이터 우선 사용 (기본값: true)

#### 네트워크 설정
- `RefreshInterval(interval)` - 자동 새로고침 간격 (초)
- `DisableRefresh(disable?)` - 자동 새로고침 비활성화 (기본값: true)
- `CustomHeaders(headers)` - 커스텀 HTTP 헤더 설정
- `HeaderName(headerName)` - 인증 헤더 이름 설정
- `UsePOSTRequests(usePOST?)` - POST 요청 사용 (기본값: true)

#### 메트릭 설정
- `MetricsInterval(interval)` - 메트릭 전송 간격 (초)
- `MetricsIntervalInitial(interval)` - 초기 메트릭 전송 간격 (초)
- `DisableMetrics(disable?)` - 메트릭 수집 비활성화 (기본값: true)
- `ImpressionDataAll(enable?)` - 모든 노출 데이터 수집 (기본값: true)

#### 로깅 설정
- `LogLevel(logLevel)` - 로그 레벨 설정 ("debug", "info", "warn", "error")
- `LoggerFactory(loggerFactory)` - 커스텀 로거 팩토리 설정

#### 스토리지 설정
- `StorageProvider(storageProvider)` - 커스텀 스토리지 제공자 설정

#### 고급 설정
- `Backoff(min, max, factor, jitter)` - 재시도 백오프 설정
- `Experimental(experimental)` - 실험적 기능 설정
- `TogglesStorageTTL(ttl)` - 토글 스토리지 TTL 설정 (초)

#### 빌드 메서드
- `Build()` - 설정 객체 생성
- `NewClient()` - 설정으로 ToggletClient 직접 생성

### 매개변수 설명

- `forceSelectRealtimeToggle`: 명시적 동기화 모드에서도 실시간 토글 맵을 강제로 사용할지 여부
  - `true`: 실시간 토글 맵 사용 (최신 서버 데이터)
  - `false` 또는 `nil`: 현재 모드에 따라 결정 (명시적 동기화 모드에서는 동기화된 토글 맵 사용)

## 🔧 고급 설정

### 오프라인 모드

네트워크 연결이 불안정하거나 오프라인 환경에서 사용할 수 있습니다:

```lua
-- 직접 설정 방식
local client = ToggletClient.New({
  offline = true,
  bootstrap = {
    { name = "feature-a", enabled = true },
    { name = "feature-b", enabled = false, variants = {
      { name = "variant1", enabled = true, payload = { color = "red" } }
    }}
  }
})

-- ToggletConfigBuilder 사용 (권장)
local offlineClient = ToggletConfigBuilder.New("my-app")
    :Offline(true)
    :Bootstrap({
      { name = "feature-a", enabled = true },
      { name = "feature-b", enabled = false, variants = {
        { name = "variant1", enabled = true, payload = { color = "red" } }
      }}
    })
    :DevMode(true)
    :LogLevel("debug")
    :NewClient()
```

### 명시적 동기화 모드

게임이나 중요한 작업 중 갑작스러운 플래그 변경을 방지하려면:

```lua
-- ToggletConfigBuilder 사용 (권장)
local client = ToggletConfigBuilder.New("my-game")
    :Url("https://api.example.com/togglet")
    :ClientKey("client-key")
    :Request(httpRequest)
    :ExplicitSyncMode(true)
    :RefreshInterval(60)
    :NewClient()

-- 적절한 시점에만 동기화 (예: 레벨 완료 후)
function onLevelCompleted()
  client:SyncToggles(true):Next(function()
    -- 다음 레벨에 새 기능 적용
    prepareNextLevel()
  end)
end
```

### 커스텀 스토리지 제공자

데이터 지속성을 위한 다양한 스토리지 옵션:

```lua
-- 파일 기반 스토리지
local client = ToggletClient.New({
  storageProvider = Togglet.FileStorageProvider.New("/path/to/storage", "myapp"),
  -- 기타 설정...
})

-- 메모리 기반 스토리지 (기본값)
local client = ToggletClient.New({
  storageProvider = Togglet.InMemoryStorageProvider.New(),
  -- 기타 설정...
})
```

### 로깅 설정

디버깅과 모니터링을 위한 로깅 설정:

```lua
local client = ToggletClient.New({
  loggerFactory = Togglet.Logging.DefaultLoggerFactory.New(Togglet.Logging.LogLevel.Debug),
  enableDevMode = true, -- 개발 모드 활성화
  -- 기타 설정...
})
```

### 메트릭 수집

피처 사용량 추적을 위한 메트릭 설정:

```lua
local client = ToggletClient.New({
  metricsInterval = 60, -- 60초마다 메트릭 전송
  disableMetrics = false, -- 메트릭 수집 활성화
  -- 기타 설정...
})

-- 메트릭 이벤트 구독
client:On(Togglet.Events.SENT, function(data)
  print("메트릭이 전송되었습니다:", data.url)
end)
```

## 💡 실제 사용 예제

### 게임에서의 활용

```lua
-- ToggletConfigBuilder를 사용한 게임 설정
local gameClient = ToggletConfigBuilder.New("awesome-game")
    :Url("https://game-api.example.com/togglet")
    :ClientKey("game-client-key")
    :Request(httpRequest)
    :Environment("production")
    :ExplicitSyncMode(true) -- 게임 중 갑작스러운 변경 방지
    :RefreshInterval(60) -- 1분마다 업데이트
    :MetricsInterval(300) -- 5분마다 메트릭 전송
    :LogLevel("warn") -- 경고 이상만 로깅
    :Context({
      platform = "mobile",
      version = "1.2.3"
    })
    :NewClient()

-- 레벨 시작 시 새 기능 확인
function startLevel(levelId)
  -- 새로운 적 AI 시스템
  if gameClient:IsEnabled("new-enemy-ai") then
    initializeAdvancedAI()
  else
    initializeClassicAI()
  end

  -- 특별 이벤트 아이템
  local eventToggle = gameClient:GetToggle("special-event")
  if eventToggle:IsEnabled() then
    local eventConfig = eventToggle:JsonVariation({})
    spawnSpecialItems(eventConfig.itemTypes, eventConfig.spawnRate)
  end
end

-- 레벨 완료 후 플래그 동기화
function onLevelCompleted()
  gameClient:SyncToggles(true):Next(function()
    -- 다음 레벨 준비
    prepareNextLevel()
  end)
end
```

### 웹 애플리케이션에서의 활용

```lua
-- ToggletConfigBuilder를 사용한 웹 앱 설정
local webClient = ToggletConfigBuilder.New("web-app")
    :Url("https://api.example.com/togglet")
    :ClientKey("web-client-key")
    :Request(httpRequest)
    :Environment("production")
    :RefreshInterval(30) -- 30초마다 자동 업데이트
    :MetricsInterval(60) -- 1분마다 메트릭 전송
    :ImpressionDataAll(true) -- 모든 노출 데이터 수집
    :LogLevel("info")
    :StorageProvider(Togglet.FileStorageProvider.New("/tmp/web-app", "togglet"))
    :NewClient()

-- 사용자별 기능 제공
function renderUserDashboard(userId)
  webClient:SetContextFields({ userId = userId })

  -- 새로운 대시보드 UI
  if webClient:IsEnabled("new-dashboard-ui") then
    renderNewDashboard()
  else
    renderClassicDashboard()
  end

  -- 프리미엄 기능
  if webClient:IsEnabled("premium-features") then
    showPremiumFeatures()
  end
end
```

## 🎯 모범 사례

### 1. 적절한 동기화 시점 선택

```lua
-- ✅ 좋은 예: 자연스러운 전환점에서 동기화
function onMainMenuEntered()
  client:SyncToggles(true):Next(function()
    updateMainMenuFeatures()
  end)
end

function onMatchEnded()
  client:SyncToggles(true):Next(function()
    prepareNextMatch()
  end)
end

-- ❌ 나쁜 예: 게임 중 갑작스러운 동기화
function onGameLoop()
  client:SyncToggles(true) -- 게임 플레이 중 혼란 야기
end
```

### 2. 안전한 기본값 사용

```lua
-- ✅ 좋은 예: 안전한 기본값 제공
local maxPlayersToggle = client:GetToggle("max-players")
local maxPlayers = maxPlayersToggle:NumberVariation(4)
local gameMode = client:GetToggle("game-mode"):StringVariation("classic")

-- 또는 편의 메서드 사용
local maxPlayers = client:NumberVariation("max-players", 4)
local gameMode = client:StringVariation("game-mode", "classic")

-- ❌ 나쁜 예: 기본값 없이 사용
local maxPlayers = client:GetToggle("max-players"):NumberVariation() -- 오류 발생
```

### 3. 오류 처리

```lua
-- ✅ 좋은 예: 적절한 오류 처리
client:On(Togglet.Events.ERROR, function(error)
  logger:Error("Togglet 오류:", error.message)
  -- 오프라인 모드로 전환하거나 기본 동작 수행
  fallbackToDefaultBehavior()
end)

client:Start():Catch(function(error)
  logger:Error("Togglet 시작 실패:", error)
  -- 기본 설정으로 계속 진행
  initializeWithDefaults()
end)
```

## 🧪 테스트

프로젝트에 포함된 테스트를 실행하여 기능을 검증할 수 있습니다:

```bash
# 오프라인 모드 테스트
lua tests/client-offline-mode-tests.lua

# 설정 빌더 테스트
lua tests/client-config-builder-offline-tests.lua
```

### 테스트 작성 예제

```lua
-- 피처 플래그 테스트 예제
local function testFeatureFlag()
  local client = ToggletClient.New({
    offline = true,
    bootstrap = {
      { name = "test-feature", enabled = true },
      { name = "test-variant", enabled = true, variant = {
        name = "test-variant",
        feature_enabled = true,
        payload = { type = "string", value = "test-value" }
      }}
    }
  })

  -- 기본 플래그 테스트
  assert(client:IsEnabled("test-feature") == true)
  assert(client:IsEnabled("non-existent-feature") == false)

  -- ToggleProxy 테스트
  local toggle = client:GetToggle("test-variant")
  assert(toggle:IsEnabled() == true)
  assert(toggle:StringVariation("default") == "test-value")
  assert(toggle:FeatureName() == "test-variant")

  print("✅ 피처 플래그 테스트 통과")
end
```

## 📚 추가 리소스

- 📖 [상세 API 문서](docs/api.md)
- ⚙️ [설정 가이드](docs/configuration.md)
- 🏆 [모범 사례 가이드](docs/best-practices.md)
- 💻 [예제 코드 모음](examples/)
- 🎮 [게임 개발 가이드](docs/game-development.md)
- 🌐 [웹 개발 가이드](docs/web-development.md)

## 🏗️ 아키텍처

### 핵심 구성 요소

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ToggletClient │────│  EventEmitter   │────│     Events      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  ToggleProxy    │    │   Validation    │    │     Logging     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ StorageProvider │    │ MetricsReporter │    │   ErrorHelper   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 주요 모듈

- **ToggletClient**: 메인 클라이언트 클래스, 모든 기능의 진입점
- **ToggleProxy**: 개별 피처 플래그의 프록시 객체
- **EventEmitter**: 이벤트 기반 아키텍처 지원
- **StorageProvider**: 데이터 지속성 (InMemory, File)
- **MetricsReporter**: 사용량 메트릭 수집 및 전송
- **Validation**: 입력 매개변수 검증
- **Promise**: 비동기 작업 처리
- **Timer**: 주기적 작업 스케줄링

### 데이터 흐름

1. **초기화**: 클라이언트 생성 → 스토리지에서 캐시된 데이터 로드
2. **시작**: 서버에서 최신 플래그 데이터 가져오기
3. **사용**: 플래그 상태 확인 → 메트릭 이벤트 생성
4. **동기화**: 주기적 또는 명시적으로 서버와 동기화
5. **이벤트**: 상태 변경 시 구독자에게 알림

## 🔧 설정 옵션

### 필수 설정

```lua
{
  url = "string",           -- Togglet 서버 URL
  clientKey = "string",     -- 클라이언트 인증 키
  appName = "string",       -- 애플리케이션 이름
  request = function        -- HTTP 요청 함수
}
```

### 선택적 설정

```lua
{
  -- 네트워크 설정
  refreshInterval = 30,           -- 자동 새로고침 간격 (초)
  disableRefresh = false,         -- 자동 새로고침 비활성화
  requestTimeout = 10,            -- 요청 타임아웃 (초)

  -- 동작 모드
  offline = false,                -- 오프라인 모드
  useExplicitSyncMode = false,    -- 명시적 동기화 모드
  disableAutoStart = false,       -- 자동 시작 비활성화

  -- 데이터 설정
  bootstrap = {},                 -- 초기 플래그 데이터
  bootstrapOverride = true,       -- 부트스트랩 데이터 우선 사용

  -- 스토리지 설정
  storageProvider = nil,          -- 커스텀 스토리지 제공자

  -- 메트릭 설정
  metricsInterval = 60,           -- 메트릭 전송 간격 (초)
  disableMetrics = false,         -- 메트릭 수집 비활성화

  -- 로깅 설정
  loggerFactory = nil,            -- 커스텀 로거 팩토리
  enableDevMode = false,          -- 개발 모드

  -- 컨텍스트 설정
  environment = "production",     -- 환경 설정
  sessionId = nil,                -- 세션 ID

  -- 실험적 기능
  experimental = {}               -- 실험적 기능 설정
}
```

## 🤝 기여하기

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

## 🆘 지원

- 📧 이메일: support@togglet.com
- 💬 Discord: [Togglet Community](https://discord.gg/togglet)
- 📖 문서: [docs.togglet.com](https://docs.togglet.com)
- 🐛 이슈 리포트: [GitHub Issues](https://github.com/your-org/togglet-lua-sdk/issues)

---

**Togglet Lua SDK**로 더 안전하고 유연한 기능 배포를 경험해보세요! 🚀
