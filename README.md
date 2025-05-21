# Unleash Client for Lua

Lua 애플리케이션을 위한 피처 플래그 클라이언트로, Unleash 서버에 연결하여 동작합니다. 이 클라이언트를 사용하면 최소한의 노력으로 Lua 애플리케이션에서 기능 토글을 관리할 수 있습니다.


## 피처 플래그란?

피처 플래그(Feature Flag)는 코드 변경 없이 기능을 동적으로 활성화하거나 비활성화할 수 있는 소프트웨어 개발 기법입니다. 이를 통해 개발자는 배포와 기능 출시를 분리하여 더 안전하고 유연하게 소프트웨어를 관리할 수 있습니다.

### 피처 플래그의 장점

- **점진적 출시**: 새 기능을 일부 사용자에게만 먼저 제공하여 위험을 최소화
- **A/B 테스트**: 다양한 기능 변형을 테스트하여 최적의 사용자 경험 발견
- **카나리 배포**: 새 기능을 소수의 사용자에게 먼저 출시하여 문제 조기 발견
- **기능 토글**: 문제 발생 시 코드 롤백 없이 즉시 기능 비활성화 가능
- **조건부 기능**: 특정 사용자, 지역, 디바이스 등에 따라 다른 기능 제공
- **구독 기반 기능**: 프리미엄 사용자에게만 특정 기능 제공
- **계절 이벤트**: 특정 기간에만 활성화되는 기능 관리

### 피처 플래그의 단점

- **코드 복잡성 증가**: 조건부 로직이 많아져 코드 가독성 저하 가능
- **기술적 부채**: 오래된 플래그가 제거되지 않으면 코드베이스 복잡성 증가
- **테스트 복잡성**: 다양한 플래그 조합에 대한 테스트 필요
- **성능 영향**: 과도한 플래그 사용은 런타임 성능에 영향 줄 수 있음
- **관리 오버헤드**: 많은 플래그를 관리하는 데 추가 리소스 필요

> **중요**: 이 SDK는 클라이언트 사이드 전용으로 설계되었습니다. 서버사이드 SDK와 달리 모든 플래그 정의를 가져오지 않고, 클라이언트에 필요한 플래그 정보만 가져옵니다. 이는 네트워크 트래픽과 메모리 사용량을 최적화할 뿐만 아니라, 보안 측면에서도 중요합니다. 민감한 기능 설정이나 구성 정보가 클라이언트에 노출되는 것을 방지하여 잠재적인 보안 위험을 줄입니다.


## 특징

- 🚀 **동적 기능 토글링** - 런타임에 기능을 활성화/비활성화
- 🔄 **실시간 업데이트** - 피처 플래그 변경 사항 자동 폴링
- 🧩 **변형(Variant) 지원** - 피처 플래그 변형 지원 (A/B 테스트)
- 📊 **컨텍스트 기반 평가** - 사용자 컨텍스트 기반 플래그 평가
- 💾 **오프라인 지원** - 부트스트랩 데이터로 오프라인에서도 작동
- 🔌 **명시적 동기화 모드** - 플래그 업데이트 적용 시점 제어
- 🔒 **보안** - 클라이언트 측 인증 지원
- 🔔 **이벤트 기반** - 피처 플래그 변경 구독
- 📝 **노출 데이터** - 피처 플래그 사용 추적
- 🔄 **자동 재시도** - 실패한 요청에 대한 지수 백오프
- 🔌 **외부 의존성 없음** - 모든 필요한 라이브러리가 포함되어 있어 추가 설치 불필요

## HTTP 통신

이 SDK는 Unreal Engine 4 환경위에 자체 구현된 `HttpRequest` 함수를 통해 HTTP 통신을 처리합니다. 이 함수는 다음과 같은 특징을 가지고 있습니다:
(`HttpRequest` 함수는 Unreal Engine 4의 `HttpModule` 의 기능을 그대로 사용합니다.)

- **스레드 세이프**: 멀티스레드 환경에서 안전하게 사용 가능
- **메인 스레드 처리**: 콜백은 메인 스레드에서 처리되어 UI 업데이트 등의 작업이 안전함
- **비동기 처리**: 네트워크 요청이 게임 루프를 차단하지 않음
- **자동 재시도**: 네트워크 오류 시 지수 백오프 알고리즘으로 재시도

SDK를 초기화할 때 `request` 함수를 제공하여 HTTP 통신을 처리합니다:

```lua
local client = Client.New({
  url = "https://unleash.example.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  request = function(url, method, headers, body, callback)
    -- UE4의 HttpRequest 함수를 사용하여 HTTP 요청 처리
    HttpRequest(url, method, headers, body, callback)
  end
})
```

> **참고**: `HttpRequest` 함수는 메인 스레드에서 콜백을 호출하므로, 콜백 내에서 UI 업데이트나 게임 상태 변경과 같은 작업을 안전하게 수행할 수 있습니다.
> **참고**: 경우에 따라서는 Unreal Engine 4가 아닌 환경에서도 사용이 가능합니다. 이때에는 `request` 에 해당하는 부분만 `http.request` 또는 `copas.http` 로 대체해주면 됩니다.

## 폴링 주기 최적화

이 SDK는 기본적으로 30초 간격으로 Unleash 서버에서 피처 플래그 업데이트를 폴링(주기적으로 가져옴) 합니다. 폴링 주기는 `refreshInterval` 설정을 통해 조정할 수 있습니다.

### 폴링 주기 설정 시 고려사항

- **짧은 폴링 주기 (10초 미만)**
  - **장점**: 피처 플래그 변경 사항이 빠르게 적용됨
  - **단점**: 
    - 서버 부하 증가
    - 네트워크 트래픽 증가
    - 배터리 소모 증가 (모바일 환경)
    - 서버 측 속도 제한(rate limiting)에 도달할 가능성

- **긴 폴링 주기 (60초 이상)**
  - **장점**: 
    - 서버 부하 감소
    - 네트워크 트래픽 감소
    - 배터리 소모 감소
  - **단점**: 
    - 피처 플래그 변경 사항이 적용되기까지 시간 지연
    - 중요한 기능 변경이 지연될 수 있음

### 권장 설정

- **일반 애플리케이션**: 30초 (기본값)
- **중요한 실시간 기능이 필요한 경우**: 15-20초
- **배터리 최적화가 중요한 모바일 앱**: 60초 이상
- **개발/테스트 환경**: 10-15초
- **프로덕션 환경**: 30-60초

```lua
-- 폴링 주기 설정 예시
local client = Client.New({
  -- 기본 구성...
  refreshInterval = 30,  -- 30초 간격으로 폴링 (기본값)
})
```

> **참고**: 폴링 주기를 0으로 설정하거나 `disableRefresh = true`로 설정하면 자동 폴링이 비활성화되며, `UpdateToggles()` 메서드를 통해 수동으로만 업데이트할 수 있습니다.

## 설치

Lua 프로젝트에 feature-flags 모듈을 포함하세요:

```lua
local FeatureFlags = require("framework.3rdparty.feature-flags.index")
```

## 빠른 시작

```lua
local FeatureFlags = require("framework.3rdparty.feature-flags.index")
local Client = FeatureFlags.Client

-- 클라이언트 초기화
local client = Client.New({
  url = "https://unleash.example.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  environment = "production",
  request = function(url, method, headers, body, callback)
    -- HTTP 요청 함수 구현
    -- 반드시 다음 형식의 응답 객체로 콜백을 호출해야 함:
    -- { status = number, headers = table, body = string }
  end
})

-- 클라이언트가 준비될 때까지 대기
client:WaitUntilReady(function()
  -- 기능이 활성화되었는지 확인
  if client:IsEnabled("my-feature") then
    print("기능이 활성화되었습니다!")
  else
    print("기능이 비활성화되었습니다!")
  end
  
  -- 변형 정보 가져오기
  local variantProxy = client:GetVariantProxy("my-feature-with-variants")
  print("변형 이름:", variantProxy:GetVariantName())
  print("기능 활성화:", variantProxy:IsEnabled())
end)
```

## 초기화

### 클라이언트 구성

```lua
local client = Client.New({
  -- 필수 매개변수
  url = "https://unleash.example.com/api",  -- Unleash API URL
  clientKey = "your-client-key",            -- 클라이언트 API 키
  appName = "your-app-name",                -- 애플리케이션 이름
  request = yourHttpRequestFunction,        -- HTTP 요청 함수
  
  -- 선택적 매개변수
  environment = "production",               -- 환경 이름 (기본값: "default")
  refreshInterval = 30,                     -- 폴링 간격(초) (기본값: 30)
  disableAutoStart = false,                 -- true로 설정하여 수동으로 시작
  offline = false,                          -- 오프라인 모드 활성화
  bootstrap = initialFeatureFlags,          -- 초기 피처 플래그
  bootstrapOverride = true,                 -- 저장된 플래그를 부트스트랩으로 덮어쓰기
  useExplicitSyncMode = false,              -- 명시적 동기화 모드 활성화
  disableRefresh = false,                   -- 자동 폴링 비활성화
  usePOSTrequests = false,                  -- API 요청에 GET 대신 POST 사용
  storageProvider = customStorageProvider,  -- 사용자 정의 스토리지 제공자
  impressionDataAll = false,                -- 모든 노출 추적
  customHeaders = {                         -- 사용자 정의 HTTP 헤더
    ["Custom-Header"] = "value"
  },
  context = {                               -- 초기 컨텍스트
    userId = "user-123",
    sessionId = "session-456",
    remoteAddress = "127.0.0.1",
    properties = {
      customField = "value"
    }
  },
  loggerFactory = customLoggerFactory,      -- 사용자 정의 로거 팩토리
  experimental = {                          -- 실험적 기능
    togglesStorageTTL = 3600                -- 캐시 TTL(초)
  }
})
```

### 시작 및 중지

```lua
-- 수동 시작 (disableAutoStart = true인 경우)
client:Start(function()
  print("클라이언트가 시작되었습니다!")
})

-- 클라이언트가 준비될 때까지 대기
client:WaitUntilReady(function()
  print("클라이언트가 준비되었습니다!")
})

-- 클라이언트 중지
client:Stop()
```

## 부트스트래핑 (Bootstrapping)

부트스트래핑은 클라이언트가 서버에 연결하기 전에 초기 피처 플래그 상태를 제공하는 방법입니다. 이는 다음과 같은 상황에서 유용합니다:

- 애플리케이션 시작 시 빠른 로딩
- 네트워크 연결이 불안정한 환경
- 서버 다운타임 동안의 폴백 메커니즘
- 오프라인 모드 지원

### 부트스트래핑 구성

```lua
local initialFeatureFlags = {
  {
    name = "feature-a",
    enabled = true,
    variant = {
      name = "variant-1",
      enabled = true,
      payload = {
        type = "string",
        value = "Hello World"
      }
    }
  },
  {
    name = "feature-b",
    enabled = false
  }
}

local client = Client.New({
  url = "https://unleash.example.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  request = yourHttpRequestFunction,
  
  -- 부트스트랩 구성
  bootstrap = initialFeatureFlags,
  bootstrapOverride = true  -- true: 항상 부트스트랩 값으로 덮어씀
                           -- false: 저장된 값이 있으면 부트스트랩 무시
})
```

### 부트스트랩 사용 사례

#### 1. 서버 연결 전 초기 상태 제공

```lua
local client = Client.New({
  -- 기본 구성...
  bootstrap = initialFeatureFlags,
  disableAutoStart = true  -- 자동 시작 비활성화
})

-- 부트스트랩 값으로 즉시 사용 가능
if client:IsEnabled("feature-a") then
  print("부트스트랩 값으로 기능 A가 활성화됨")
end

-- 나중에 서버에 연결
client:Start(function()
  print("서버에 연결됨, 최신 플래그로 업데이트됨")
})
```

#### 2. 서버 다운타임 대비

```lua
local client = Client.New({
  -- 기본 구성...
  bootstrap = initialFeatureFlags,
  bootstrapOverride = false  -- 저장된 값이 있으면 사용
})

-- 오류 처리
client:On(FeatureFlags.Events.ERROR, function(error)
  print("서버 연결 오류, 부트스트랩/캐시된 값 사용 중:", error.message)
})
```

#### 3. 개발 환경에서 테스트

```lua
-- 개발 환경에서 특정 기능 강제 활성화
local devBootstrap = {
  {
    name = "new-experimental-feature",
    enabled = true
  }
}

local client = Client.New({
  -- 기본 구성...
  bootstrap = devBootstrap,
  bootstrapOverride = true  -- 항상 부트스트랩 값 사용
})
```

## 오프라인 모드

오프라인 모드는 서버에 연결하지 않고 클라이언트를 사용할 수 있게 해줍니다. 이 모드에서는 부트스트랩 데이터만 사용하며 서버에서 업데이트를 가져오지 않습니다.

### 오프라인 모드 구성

```lua
local client = Client.New({
  appName = "your-app-name",
  offline = true,  -- 오프라인 모드 활성화
  bootstrap = {    -- 필수: 오프라인 모드에서 사용할 피처 플래그
    {
      name = "feature-a",
      enabled = true,
      variant = {
        name = "variant-1",
        enabled = true,
        payload = { type = "string", value = "test" }
      }
    },
    {
      name = "feature-b",
      enabled = false
    }
  }
})
```

### 오프라인 모드 사용 사례

#### 1. 네트워크 없는 환경

```lua
-- 네트워크 연결이 없는 환경에서 사용
local client = Client.New({
  appName = "your-app-name",
  offline = true,
  bootstrap = offlineFeatureFlags
})

-- 오프라인 모드에서는 항상 즉시 준비됨
if client:IsReady() then
  print("클라이언트가 오프라인 모드로 준비됨")
end

-- 기능 확인
if client:IsEnabled("feature-a") then
  print("오프라인 모드에서 기능 A 활성화됨")
end
```

#### 2. 테스트 환경

```lua
-- 테스트 환경에서 특정 기능 상태로 고정
local testFeatureFlags = {
  {
    name = "payment-gateway",
    enabled = true,
    variant = {
      name = "test-gateway",
      enabled = true,
      payload = { type = "json", value = { endpoint = "https://test-api.example.com" } }
    }
  }
}

local client = Client.New({
  appName = "test-app",
  offline = true,
  bootstrap = testFeatureFlags
})

-- 테스트 코드에서 사용
local paymentVariant = client:GetVariantProxy("payment-gateway")
local endpoint = paymentVariant:JsonVariation({}).endpoint
print("테스트 엔드포인트:", endpoint)
```

#### 3. 임베디드 환경

```lua
-- 임베디드 시스템에서 하드코딩된 기능 플래그 사용
local embeddedFlags = {
  {
    name = "hardware-feature-x",
    enabled = deviceSupportsFeatureX()  -- 하드웨어 기능 확인 함수
  },
  {
    name = "memory-optimization",
    enabled = getAvailableMemory() < 512  -- 메모리 기반 최적화
  }
}

local client = Client.New({
  appName = "embedded-app",
  offline = true,
  bootstrap = embeddedFlags
})
```

## 명시적 동기화 모드

명시적 동기화 모드(Explicit Sync Mode)는 서버에서 받은 피처 플래그 업데이트를 즉시 적용하지 않고, 개발자가 명시적으로 동기화를 요청할 때만 적용하는 기능입니다. 이 모드는 다음과 같은 상황에서 유용합니다:

- 중요한 작업 중 예상치 못한 기능 변경 방지
- 특정 시점(예: 화면 전환, 세션 시작)에만 업데이트 적용
- 여러 관련 기능을 동시에 업데이트해야 하는 경우

### 실시간 업데이트의 잠재적 문제점

명시적 동기화 모드를 사용하지 않고 피처 플래그를 실시간으로 적용할 경우 다음과 같은 문제가 발생할 수 있습니다:

1. **게임 세션 중 일관성 손상**
   ```lua
   -- 플레이어가 보스 전투 중일 때 갑자기 난이도 변경
   -- 실시간 업데이트 시나리오
   function bossFight()
     startBossFight()
     
     -- 전투 중 서버에서 "boss-difficulty" 플래그가 변경되면
     -- 즉시 적용되어 갑작스러운 난이도 변화 발생
     -- 플레이어는 혼란스럽고 불공정하다고 느낄 수 있음
   end
   ```

2. **UI 요소의 갑작스러운 변경**
   ```lua
   -- 사용자가 메뉴 탐색 중 UI 레이아웃 변경
   -- 실시간 업데이트 시나리오
   function navigateMenu()
     showMainMenu()
     
     -- 사용자가 메뉴 탐색 중 "new-ui-layout" 플래그가 변경되면
     -- 즉시 UI가 재구성되어 사용자 경험 저하
     -- 사용자가 클릭하려던 버튼 위치가 바뀌어 의도치 않은 동작 발생
   end
   ```

3. **트랜잭션 일관성 문제**
   ```lua
   -- 아이템 구매 중 가격 정책 변경
   -- 실시간 업데이트 시나리오
   function purchaseItem(itemId)
     local price = getItemPrice(itemId)
     showConfirmDialog("구매 확인", itemId, price)
     
     -- 사용자가 확인 대화상자를 보는 동안 "pricing-policy" 플래그가 변경되면
     -- 확인 버튼 클릭 시 다른 가격으로 처리될 수 있음
     -- 사용자는 표시된 가격과 다른 금액이 청구되는 혼란 경험
   end
   ```

4. **게임 밸런스 붕괴**
   ```lua
   -- PvP 매치 중 밸런스 변경
   -- 실시간 업데이트 시나리오
   function pvpMatch()
     startMatch()
     
     -- 매치 중 "character-balance" 플래그가 변경되면
     -- 캐릭터 능력치가 즉시 변경되어 경기 밸런스 붕괴
     -- 플레이어는 갑자기 약해지거나 강해져 불공정함 경험
   end
   ```

5. **기능 간 의존성 문제**
   ```lua
   -- 상호 의존적인 기능들의 비동기 업데이트
   -- 실시간 업데이트 시나리오
   function initializeFeatures()
     -- "feature-a"와 "feature-b"가 서로 의존적인 경우
     -- "feature-a"만 먼저 업데이트되고 "feature-b"는 아직 업데이트되지 않은 상태라면
     -- 두 기능 간 불일치로 예상치 못한 동작이나 오류 발생 가능
   end
   ```

### 온라인 게임에서의 활용 사례

#### 1. 게임 세션 중 일관성 유지

```lua
-- 게임 세션 시작 시 플래그 동기화
function startGameSession()
  -- 최신 플래그로 동기화
  client:SyncToggles(true, function()
    print("게임 세션 시작 전 최신 기능 플래그 적용")
    
    -- 게임 세션 시작
    beginGameSession()
    
    -- 게임 세션 중에는 플래그 변경 없이 일관된 경험 제공
  end)
end

-- 게임 세션 종료 후 다시 동기화
function endGameSession()
  -- 게임 결과 저장 등 마무리 작업
  finalizeGameSession()
  
  -- 세션 종료 후 최신 플래그 동기화
  client:SyncToggles(true, function()
    print("게임 세션 종료 후 최신 기능 플래그 적용")
    returnToLobby()
  end)
end
```

#### 2. 레벨/맵 전환 시 동기화

```lua
-- 레벨 또는 맵 전환 시 동기화
function changeLevel(newLevelId)
  -- 로딩 화면 표시
  showLoadingScreen()
  
  -- 레벨 전환 전 최신 플래그 동기화
  client:SyncToggles(true, function()
    print("레벨 전환 시 최신 기능 플래그 적용")
    
    -- 새 레벨에 적용될 기능 확인
    local hasNewFeatures = client:IsEnabled("level-" .. newLevelId .. "-features")
    
    -- 레벨 로드 및 초기화
    loadLevel(newLevelId, hasNewFeatures)
    hideLoadingScreen()
  end)
end
```

#### 3. 매치메이킹 및 인스턴스 생성

```lua
-- 매치메이킹 시작 전 동기화
function startMatchmaking()
  -- 매치메이킹 전 최신 플래그 동기화
  client:SyncToggles(true, function()
    -- 매치메이킹 관련 기능 확인
    local matchmakingVariant = client:GetVariantProxy("matchmaking-algorithm")
    local algorithm = matchmakingVariant:StringVariation("default")
    
    -- 선택된 알고리즘으로 매치메이킹 시작
    beginMatchmaking(algorithm)
  end)
end

-- 게임 인스턴스 생성 시 동기화
function createGameInstance(players)
  client:SyncToggles(true, function()
    -- 게임 모드 확인
    local gameModeVariant = client:GetVariantProxy("game-mode-settings")
    local settings = gameModeVariant:JsonVariation({})
    
    -- 설정된 게임 모드로 인스턴스 생성
    initializeGameInstance(players, settings)
  end)
end
```

#### 4. 일일 리셋 및 이벤트 전환

```lua
-- 일일 리셋 시 동기화
function performDailyReset()
  -- 일일 리셋 작업 수행
  resetDailyQuests()
  resetDailyShop()
  
  -- 리셋 후 최신 플래그 동기화
  client:SyncToggles(true, function()
    -- 오늘의 이벤트 확인
    if client:IsEnabled("daily-special-event") then
      local eventVariant = client:GetVariantProxy("daily-special-event")
      local eventType = eventVariant:StringVariation("none")
      activateSpecialEvent(eventType)
    end
    
    -- UI 업데이트
    refreshGameUI()
  end)
end
```

#### 5. PvP와 PvE 모드 전환

```lua
-- 게임 모드 전환 시 동기화
function switchGameMode(newMode)
  -- 모드 전환 전 최신 플래그 동기화
  client:SyncToggles(true, function()
    if newMode == "PvP" then
      -- PvP 관련 기능 확인
      local pvpFeatures = {
        matchmaking = client:IsEnabled("pvp-matchmaking"),
        ranking = client:IsEnabled("pvp-ranking"),
        rewards = client:GetVariantProxy("pvp-rewards"):JsonVariation({})
      }
      initializePvPMode(pvpFeatures)
    else
      -- PvE 관련 기능 확인
      local pveFeatures = {
        difficulty = client:GetVariantProxy("pve-difficulty"):StringVariation("normal"),
        enemies = client:GetVariantProxy("pve-enemy-types"):JsonVariation({})
      }
      initializePvEMode(pveFeatures)
    end
  end)
end
```

### 명시적 동기화 모드 구성

```lua
local client = Client.New({
  url = "https://unleash.example.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  request = yourHttpRequestFunction,
  
  -- 명시적 동기화 모드 활성화
  useExplicitSyncMode = true
})
```

### 명시적 동기화 모드 사용 사례

#### 1. 기본 동기화 패턴

```lua
-- 클라이언트 초기화
local client = Client.New({
  -- 기본 구성...
  useExplicitSyncMode = true
})

-- 클라이언트가 준비될 때까지 대기
client:WaitUntilReady(function()
  -- 초기 상태 사용
  if client:IsEnabled("feature-a") then
    print("초기 상태에서 기능 A 활성화됨")
  end
  
  -- 서버에서 최신 토글 가져오기
  client:UpdateToggles(function(error)
    if not error then
      -- 가져온 토글을 동기화하여 적용
      client:SyncToggles(false, function()
        -- 이제 최신 상태 사용 가능
        if client:IsEnabled("feature-a") then
          print("업데이트 후 기능 A 활성화됨")
        end
      end)
    end
  end)
})
```

#### 2. 화면 전환 시 동기화

```lua
-- 화면 전환 함수
function switchToScreen(screenName)
  -- 화면 전환 전에 최신 토글 동기화
  client:SyncToggles(true, function()
    print("화면 전환 전 최신 토글로 동기화됨")
    
    -- 이제 최신 상태로 화면 렌더링
    renderScreen(screenName)
  end)
end
```

#### 3. 주기적 동기화

```lua
-- 5분마다 동기화하는 타이머 설정
local syncInterval = 5 * 60  -- 5분(초 단위)

function setupPeriodicSync()
  -- 주기적으로 토글 업데이트 및 동기화
  Timer.Perform(function()
    client:UpdateToggles(function(error)
      if not error then
        client:SyncToggles(false, function()
          print("주기적 동기화 완료")
        end)
      end
    end)
  end):Delay(syncInterval):StartDelay(syncInterval)
end
```

#### 4. 사용자 세션 시작 시 동기화

```lua
function userLogin(userId)
  -- 사용자 ID 설정
  client:SetContextField("userId", userId, function()
    -- 사용자별 토글 가져오기 및 동기화
    client:SyncToggles(true, function()
      print("사용자 로그인 시 토글 동기화됨")
      
      -- 이제 사용자별 기능 확인 가능
      if client:IsEnabled("premium-feature") then
        showPremiumFeatures()
      end
    end)
  end)
end
```

#### 5. 중요 작업 중 동기화 방지

```lua
function startCriticalOperation()
  print("중요 작업 시작, 토글 업데이트 무시")
  
  -- 작업 완료
  performCriticalTask(function()
    -- 작업 완료 후 최신 상태로 동기화
    client:SyncToggles(true, function()
      print("중요 작업 완료, 최신 토글로 동기화됨")
    end)
  end)
end
```

## 피처 플래그 평가

### 기본 기능 토글

```lua
-- 기능이 활성화되었는지 확인
if client:IsEnabled("my-feature") then
  -- 기능이 활성화됨
else
  -- 기능이 비활성화됨
end

-- 모든 활성화된 토글 가져오기
local enabledToggles = client:GetAllEnabledToggles()
for _, toggle in ipairs(enabledToggles) do
  print(toggle.name, toggle.enabled)
end
```

### 변형(Variants)

변형(Variants)는 `GetVariant()` 또는 `GetVariantProxy()` 함수를 통해서 사용할수 있습니다. `GetVariant()` 함수를 통해서 사용할 경우에는 다소 사용이 불편할수 있으므로, `GetVariantProxy()` 를 사용하는 것을 추천합니다. `GetVariant()` 함수는 `variant` 자료형을 반환하므로, 다소 사용하기 불편할수 있습니다.

`GetVariantProxy` 메서드는 `VariantProxy` 객체를 반환합니다. 이 프록시 객체는 변형 데이터에 안전하게 접근할 수 있는 다양한 메서드를 제공합니다:

- `GetFeatureName()`: 기능 이름 반환
- `GetVariantName()`: 변형 이름 반환
- `GetRawVariant()`: 원본 변형 객체 반환
- `IsEnabled()`: 기능 활성화 여부 반환
- `BoolVariation(defaultValue)`: 불리언 값 반환
- `NumberVariation(defaultValue)`: 숫자 값 반환
- `StringVariation(defaultValue)`: 문자열 값 반환
- `JsonVariation(defaultValue)`: JSON 객체 값 반환

```lua
-- 변형 정보 가져오기
local variant = client:GetVariantProxy("my-feature")
print("변형 이름:", variantProxy:GetVariantName())
print("기능 이름:", variantProxy:GetFeatureName())
print("기능 활성화:", variantProxy:IsEnabled())

-- 변형 데이터 타입별 접근
local boolValue = variant:BoolVariation(false)
local numberValue = variant:NumberVariation(0)
local stringValue = variant:StringVariation("default")
local jsonValue = variant:JsonVariation({})

-- 또는 클라이언트에서 직접 타입별 변형 접근
local boolValue = client:BoolVariation("my-bool-feature", false)
local numberValue = client:NumberVariation("my-number-feature", 0)
local stringValue = client:StringVariation("my-string-feature", "default")
local jsonValue = client:JsonVariation("my-json-feature", {})
```

---

# 컨텍스트(Context)

피처 플래그 클라이언트에서 컨텍스트는 사용자, 환경, 세션 등에 관한 정보를 담고 있으며, 이를 기반으로 피처 플래그의 활성화 여부를 결정합니다. 이 문서는 컨텍스트의 정의와 효과적인 사용법을 설명합니다.

## 컨텍스트 구조

### 컨텍스트 필드 유형

컨텍스트 필드는 두 가지 유형으로 나뉩니다:

1. **정적 필드**: 클라이언트 초기화 시 설정되며 이후 변경할 수 없습니다.
   - `appName`: 애플리케이션 이름 (필수)
   - `environment`: 환경 (기본값: "default")
   - `sessionId`: 세션 ID

2. **가변 필드**: 런타임에 업데이트할 수 있는 필드입니다.
   - `userId`: 사용자 ID
   - `remoteAddress`: 원격 IP 주소
   - `currentTime`: 현재 시간
   - `properties`: 사용자 정의 속성 (객체)

## 컨텍스트 초기화

### 초기화 시 컨텍스트 설정

클라이언트 초기화 시 컨텍스트를 설정할 수 있습니다:

```lua
local client = Client.New({
  url = "https://unleash.example.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",  -- 정적 필드
  environment = "production",  -- 정적 필드
  
  -- 초기 컨텍스트 설정
  context = {
    userId = "user-123",       -- 가변 필드
    sessionId = "session-456", -- 정적 필드
    remoteAddress = "127.0.0.1", -- 가변 필드
    properties = {             -- 사용자 정의 속성
      region = "asia",
      deviceType = "mobile",
      premium = true
    }
  }
})
```

## 컨텍스트 업데이트

### 전체 컨텍스트 업데이트

`UpdateContext` 메서드를 사용하여 여러 컨텍스트 필드를 한 번에 업데이트할 수 있습니다:

```lua
client:UpdateContext({
  userId = "new-user-id",
  remoteAddress = "192.168.1.1",
  properties = {
    region = "europe",
    deviceType = "desktop",
    premium = false,
    language = "en"
  }
}, function()
  print("컨텍스트가 업데이트되었습니다")
  -- 컨텍스트 업데이트 후 자동으로 피처 플래그가 다시 평가됩니다
})
```

> **참고**: `UpdateContext`는 정적 필드(`appName`, `environment`, `sessionId`)를 변경하지 않습니다. 이러한 필드를 업데이트하려고 하면 경고 로그가 기록됩니다.

### 단일 컨텍스트 필드 업데이트

`SetContextField` 메서드를 사용하여 단일 컨텍스트 필드를 업데이트할 수 있습니다:

```lua
-- 기본 컨텍스트 필드 업데이트
client:SetContextField("userId", "another-user-id", function()
  print("사용자 ID가 업데이트되었습니다")
end)

-- 사용자 정의 속성 업데이트
client:SetContextField("region", "america", function()
  print("지역이 업데이트되었습니다")
  -- 이 필드는 context.properties.region에 저장됩니다
end)
```

### 컨텍스트 필드 제거

`RemoveContextField` 메서드를 사용하여 컨텍스트 필드를 제거할 수 있습니다:

```lua
client:RemoveContextField("userId", function()
  print("사용자 ID가 제거되었습니다")
end)

client:RemoveContextField("region", function()
  print("지역이 제거되었습니다")
  -- context.properties.region이 제거됩니다
end)
```

## 컨텍스트 조회

### 현재 컨텍스트 가져오기

`GetContext` 메서드를 사용하여 현재 컨텍스트의 복사본을 가져올 수 있습니다:

```lua
local context = client:GetContext()
print("사용자 ID:", context.userId)
print("환경:", context.environment)

-- 사용자 정의 속성 접근
if context.properties then
  print("지역:", context.properties.region)
  print("디바이스 유형:", context.properties.deviceType)
end
```

> **참고**: `GetContext`는 컨텍스트의 깊은 복사본을 반환하므로, 반환된 객체를 수정해도 실제 컨텍스트는 변경되지 않습니다.

## 컨텍스트 기반 평가

### 컨텍스트가 피처 플래그 평가에 미치는 영향

컨텍스트는 피처 플래그의 활성화 여부를 결정하는 데 중요한 역할을 합니다. Unleash 서버는 다음과 같은 컨텍스트 기반 전략을 지원합니다:

1. **사용자 ID 기반**: 특정 사용자에게만 기능 활성화
2. **IP 주소 기반**: 특정 IP 주소 또는 범위에 대해 기능 활성화
3. **환경 기반**: 개발, 테스트, 프로덕션 등 특정 환경에서만 기능 활성화
4. **사용자 정의 속성 기반**: 지역, 디바이스 유형, 구독 상태 등에 따라 기능 활성화

예를 들어, 프리미엄 사용자에게만 새 기능을 제공하려면:

```lua
-- 사용자 로그인 시 프리미엄 상태 설정
function onUserLogin(userId, isPremium)
  client:UpdateContext({
    userId = userId,
    properties = {
      premium = isPremium
    }
  }, function()
    -- 컨텍스트 업데이트 후 기능 확인
    if client:IsEnabled("premium-feature") then
      showPremiumFeature()
    end
  end)
end
```

Unleash 서버에서는 "premium-feature" 토글에 대해 "premium = true" 조건을 가진 전략을 구성할 수 있습니다.

## 컨텍스트 해시

### 컨텍스트 해시 계산

클라이언트는 내부적으로 컨텍스트 해시를 계산하여 컨텍스트가 변경되었는지 확인합니다. 이 해시는 다음과 같이 계산됩니다:

1. 컨텍스트 필드를 정렬된 순서로 JSON 문자열로 변환
2. SHA-256 해시 함수를 사용하여 해시 값 계산

컨텍스트 해시가 변경되면 클라이언트는 서버에서 피처 플래그를 다시 가져옵니다.

> **참고**: 컨텍스트 해시 계산은 내부 구현 세부 사항이며, 직접 접근하거나 수정할 수 없습니다.

## 컨텍스트 사용 모범 사례

### 1. 필요한 정보만 포함

컨텍스트에는 피처 플래그 평가에 필요한 정보만 포함하세요. 불필요한 데이터는 성능에 영향을 미칠 수 있습니다.

```lua
-- 좋은 예: 필요한 정보만 포함
client:UpdateContext({
  userId = "user-123",
  properties = {
    region = "asia",
    premium = true
  }
})

-- 나쁜 예: 불필요한 정보 포함
client:UpdateContext({
  userId = "user-123",
  properties = {
    region = "asia",
    premium = true,
    fullName = "John Doe",  -- 피처 플래그 평가에 불필요
    email = "john@example.com",  -- 피처 플래그 평가에 불필요
    preferences = {  -- 중첩된 복잡한 객체
      theme = "dark",
      fontSize = 14,
      notifications = { ... }
    }
  }
})
```

### 2. 컨텍스트 업데이트 최적화

컨텍스트가 변경될 때마다 서버에서 피처 플래그를 다시 가져오므로, 불필요한 업데이트를 최소화하세요.

```lua
-- 나쁜 예: 매 프레임마다 컨텍스트 업데이트
function update(dt)
  client:SetContextField("currentTime", ISO8601Now())  -- 매 프레임마다 업데이트
end

-- 좋은 예: 필요할 때만 컨텍스트 업데이트
local lastTimeUpdate = 0
function update(dt)
  local currentTime = os.time()
  if currentTime - lastTimeUpdate > 60 then  -- 1분마다 업데이트
    client:SetContextField("currentTime", currentTime)
    lastTimeUpdate = currentTime
  end
end
```

### 3. 사용자 전환 시 컨텍스트 업데이트

사용자가 로그인하거나 로그아웃할 때 컨텍스트를 업데이트하세요.

```lua
function onUserLogin(userId, userInfo)
  client:UpdateContext({
    userId = userId,
    properties = {
      region = userInfo.region,
      premium = userInfo.isPremium,
      accountAge = userInfo.accountAge
    }
  })
end

function onUserLogout()
  client:UpdateContext({
    userId = nil,  -- userId 제거
    properties = {
      region = getDefaultRegion(),  -- 기본값으로 재설정
      premium = false,
      accountAge = nil
    }
  })
end
```

### 4. 명시적 동기화 모드와 함께 사용

명시적 동기화 모드를 사용할 때는 컨텍스트 업데이트 후 `SyncToggles`를 호출하여 변경 사항을 적용하세요.

```lua
-- 컨텍스트 업데이트 후 토글 동기화
client:UpdateContext({
  userId = "new-user-id",
  properties = { premium = true }
}, function()
  -- 컨텍스트 업데이트 후 토글 동기화
  client:SyncToggles(true, function()
    -- 이제 최신 상태로 기능 확인 가능
    if client:IsEnabled("premium-feature") then
      showPremiumFeature()
    end
  end)
end)
```

## 보안 고려 사항

### 민감한 정보 처리

컨텍스트에 민감한 정보를 포함하지 마세요. 컨텍스트 데이터는 서버로 전송되며 로그에 기록될 수 있습니다.

```lua
-- 나쁜 예: 민감한 정보 포함
client:UpdateContext({
  userId = "user-123",
  properties = {
    password = "secret123",  -- 민감한 정보
    creditCard = "1234-5678-9012-3456",  -- 민감한 정보
    authToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."  -- 민감한 정보
  }
})

-- 좋은 예: 안전한 정보만 포함
client:UpdateContext({
  userId = "user-123",
  properties = {
    hasPaymentMethod = true,  -- 불리언 플래그만 사용
    accountTier = "premium"   -- 민감하지 않은 정보
  }
})
```

### 사용자 식별 정보 최소화

개인 식별 정보(PII)를 최소화하고, 가능한 경우 익명화된 ID를 사용하세요.

```lua
-- 나쁜 예: 과도한 개인 정보
client:UpdateContext({
  userId = "john.doe@example.com",  -- 이메일을 ID로 사용
  properties = {
    fullName = "John Doe",
    age = 35,
    location = "Seoul, South Korea"
  }
})

-- 좋은 예: 최소한의 익명화된 정보
client:UpdateContext({
  userId = "u12345",  -- 익명화된 ID
  properties = {
    ageGroup = "30-40",
    region = "asia"
  }
})
```

## 문제 해결

### 컨텍스트 업데이트 후 피처 플래그가 변경되지 않는 경우

1. **정적 필드 업데이트 시도**: 정적 필드(`appName`, `environment`, `sessionId`)는 초기화 후 변경할 수 없습니다.

   ```lua
   -- 이 업데이트는 무시됩니다
   client:UpdateContext({
     environment = "production"  -- 정적 필드
   })
   ```

2. **컨텍스트 변경 없음**: 이전과 동일한 값으로 컨텍스트를 업데이트하면 서버 요청이 발생하지 않습니다.

   ```lua
   -- 이미 userId가 "user-123"인 경우 변경 없음
   client:SetContextField("userId", "user-123")
   ```

3. **오프라인 모드**: 오프라인 모드에서는 컨텍스트 업데이트가 무시됩니다.

   ```lua
   -- 오프라인 모드에서는 효과 없음
   client:UpdateContext({
     userId = "new-user-id"
   })
   ```

4. **명시적 동기화 모드**: 명시적 동기화 모드에서는 `SyncToggles`를 호출해야 변경 사항이 적용됩니다.

   ```lua
   -- 컨텍스트 업데이트 후 SyncToggles 호출 필요
   client:UpdateContext({
     userId = "new-user-id"
   }, function()
     client:SyncToggles(true)  -- 이 호출이 없으면 변경 사항이 적용되지 않음
   end)
   ```

### 로깅 활성화

문제 해결을 위해 로깅을 활성화하여 컨텍스트 변경 및 서버 요청을 추적할 수 있습니다:

```lua
local client = Client.New({
  -- 기본 구성...
  logLevel = "debug"  -- 상세 로깅 활성화
})
```

## 예제 시나리오

### 사용자 세그먼트에 따른 기능 제공

```lua
-- 사용자 로그인 시
function onUserLogin(userId, userInfo)
  -- 사용자 컨텍스트 설정
  client:UpdateContext({
    userId = userId,
    properties = {
      region = userInfo.region,
      accountType = userInfo.accountType,  -- "free", "premium", "enterprise"
      accountAge = calculateAccountAge(userInfo.createdAt),
      deviceType = getDeviceType()
    }
  }, function()
    -- 컨텍스트 업데이트 후 사용자별 기능 확인
    
    -- 프리미엄 기능
    if client:IsEnabled("premium-features") then
      enablePremiumFeatures()
    end
    
    -- 지역별 기능
    if client:IsEnabled("regional-content") then
      loadRegionalContent()
    end
    
    -- 신규 사용자 튜토리얼
    if client:IsEnabled("new-user-tutorial") then
      showTutorial()
    end
    
    -- A/B 테스트
    local uiVariant = client:GetVariantProxy("ui-redesign")
    if uiVariant:IsEnabled() then
      applyUiTheme(uiVariant:StringVariation("classic"))
    end
  end)
end
```

### 디바이스 특성에 따른 기능 최적화

```lua
-- 앱 시작 시 디바이스 정보 설정
function initializeDeviceContext()
  local deviceInfo = getDeviceInfo()
  
  client:UpdateContext({
    properties = {
      deviceType = deviceInfo.type,  -- "mobile", "tablet", "desktop"
      osVersion = deviceInfo.osVersion,
      memorySize = deviceInfo.memoryMB,
      screenSize = deviceInfo.screenSize,
      networkType = getCurrentNetworkType()  -- "wifi", "cellular", "offline"
    }
  }, function()
    -- 디바이스 특성에 따른 기능 최적화
    
    -- 저사양 디바이스 최적화
    if client:IsEnabled("low-end-device-optimization") then
      enableLowEndOptimizations()
    end
    
    -- 고해상도 텍스처
    if client:IsEnabled("high-res-textures") then
      loadHighResTextures()
    end
    
    -- 네트워크 최적화
    local networkConfig = client:GetVariantProxy("network-config")
    if networkConfig:IsEnabled() then
      applyNetworkSettings(networkConfig:JsonVariation({}))
    end
  end)
end

-- 네트워크 상태 변경 시 업데이트
function onNetworkChanged(newNetworkType)
  client:SetContextField("networkType", newNetworkType, function()
    -- 네트워크 상태에 따른 기능 조정
    if client:IsEnabled("offline-mode") then
      enableOfflineMode()
    end
  end)
end
```


# 온라인 게임에서의 Feature Flags 활용 사례

피처 플래그(Feature Flags)는 온라인 게임 개발 및 운영에 있어 강력한 도구입니다. 이 문서에서는 온라인 게임에서 피처 플래그를 활용하는 다양한 사례와 구현 방법을 설명합니다.

## 1. 점진적 기능 출시 (Gradual Rollout)

### 사례: 새로운 게임 모드 출시

새로운 게임 모드를 전체 사용자에게 한 번에 출시하는 대신, 일부 사용자에게 먼저 제공하여 안정성을 검증할 수 있습니다.

```lua
-- 새로운 배틀로얄 모드 점진적 출시
function checkBattleRoyaleAccess()
  if client:IsEnabled("new-battle-royale-mode") then
    showBattleRoyaleMode()
  else
    showComingSoonMessage("배틀로얄 모드가 곧 출시됩니다!")
  end
end

-- 사용자 로그인 시 컨텍스트 설정
function onUserLogin(userId, userInfo)
  client:UpdateContext({
    userId = userId,
    properties = {
      region = userInfo.region,
      accountAge = calculateAccountAge(userInfo.createdAt),
      playTime = userInfo.totalPlayHours
    }
  }, function()
    checkBattleRoyaleAccess()
  end)
end
```

서버에서는 다음과 같은 전략을 설정할 수 있습니다:
- 처음에는 내부 테스터(특정 userId 목록)에게만 활성화
- 그 다음 특정 지역(예: 한국)의 사용자 10%에게 활성화
- 점차 비율을 높여 모든 사용자에게 제공

### 사례: 신규 아이템 시스템

```lua
function initializeInventory()
  if client:IsEnabled("new-inventory-system") then
    initializeNewInventorySystem()
  else
    initializeLegacyInventorySystem()
  end
  
  -- 변형을 통한 아이템 드롭률 조정
  local dropRateConfig = client:GetVariantProxy("item-drop-rates")
  if dropRateConfig:IsEnabled() then
    setDropRates(dropRateConfig:JsonVariation({
      common: 70,
      uncommon: 20,
      rare: 8,
      epic: 1.8,
      legendary: 0.2
    }))
  end
end
```

## 2. A/B 테스트

### 사례: 튜토리얼 최적화

여러 버전의 튜토리얼을 테스트하여 어떤 버전이 사용자 참여도와 유지율을 높이는지 측정할 수 있습니다.

```lua
function showTutorial()
  local tutorialVariant = client:GetVariantProxy("tutorial-version")
  
  if not tutorialVariant:IsEnabled() then
    -- 기본 튜토리얼 표시
    showDefaultTutorial()
    return
  end
  
  local version = tutorialVariant:StringVariation("default")
  
  if version == "interactive" then
    showInteractiveTutorial()
  elseif version == "video" then
    showVideoTutorial()
  elseif version == "quick" then
    showQuickTutorial()
  else
    showDefaultTutorial()
  end
  
  -- 분석 이벤트 전송
  trackAnalyticsEvent("tutorial_shown", {
    variant = version
  })
end
```

### 사례: 상점 UI 레이아웃

```lua
function initializeShop()
  local shopVariant = client:GetVariantProxy("shop-layout")
  
  if shopVariant:IsEnabled() then
    local layout = shopVariant:StringVariation("grid")
    local featuredItems = shopVariant:JsonVariation({})
    
    initializeShopWithLayout(layout, featuredItems)
    
    -- 구매 전환율 추적
    trackShopConversion(layout)
  else
    initializeDefaultShop()
  end
end
```

## 3. 계절 이벤트 및 한시적 콘텐츠

### 사례: 크리스마스 이벤트

특정 기간에만 활성화되는 계절 이벤트를 관리할 수 있습니다.

```lua
function checkSeasonalEvents()
  -- 크리스마스 이벤트
  if client:IsEnabled("christmas-event") then
    enableChristmasDecorations()
    addChristmasItems()
    startSnowEffect()
    
    -- 이벤트 세부 설정
    local eventConfig = client:GetVariantProxy("christmas-event-config")
    if eventConfig:IsEnabled() then
      local config = eventConfig:JsonVariation({})
      setEventDuration(config.startDate, config.endDate)
      setSpecialDrops(config.specialDrops)
    end
  end
  
  -- 할로윈 이벤트
  if client:IsEnabled("halloween-event") then
    enableHalloweenTheme()
  end
}

-- 게임 시작 시 및 주기적으로 확인
function onGameStart()
  checkSeasonalEvents()
  
  -- 4시간마다 이벤트 상태 확인
  scheduleRepeating(checkSeasonalEvents, 4 * 60 * 60)
}
```

### 사례: 주말 보너스

```lua
function checkWeekendBonus()
  if client:IsEnabled("weekend-bonus") then
    local bonusConfig = client:GetVariantProxy("weekend-bonus-config")
    if bonusConfig:IsEnabled() then
      local config = bonusConfig:JsonVariation({
        xpMultiplier: 2.0,
        goldMultiplier: 1.5
      })
      
      applyXPBoost(config.xpMultiplier)
      applyGoldBoost(config.goldMultiplier)
      showBoostNotification()
    }
  }
}
```

## 4. 지역별 콘텐츠 및 규제 대응

### 사례: 국가별 콘텐츠 조정

각 국가의 규제 및 문화적 차이에 맞게 게임 콘텐츠를 조정할 수 있습니다.

```lua
function initializeRegionalContent()
  client:UpdateContext({
    properties = {
      country = getUserCountry(),
      language = getUserLanguage()
    }
  }, function()
    -- 확률형 아이템(가챠) 표시
    if client:IsEnabled("show-gacha-probabilities") then
      enableGachaProbabilityDisplay()
    }
    
    -- 혈흔 효과
    if client:IsEnabled("blood-effects") then
      enableBloodEffects()
    } else {
      enableAlternativeEffects()
    }
    
    -- 지역별 인게임 상점 가격
    local pricingConfig = client:GetVariantProxy("regional-pricing")
    if pricingConfig:IsEnabled() then
      applyRegionalPricing(pricingConfig:JsonVariation({}))
    }
  })
}
```

### 사례: 연령 제한 기능

```lua
function applyAgeRestrictions()
  client:UpdateContext({
    properties = {
      age = getUserAge(),
      country = getUserCountry()
    }
  }, function()
    -- 미성년자 보호 기능
    if client:IsEnabled("minor-protection") then
      enablePlayTimeLimit()
      disableMicrotransactions()
      enableContentFilter()
    }
    
    -- 채팅 필터
    if client:IsEnabled("chat-filter") then
      local filterConfig = client:GetVariantProxy("chat-filter-config")
      applyChatFilter(filterConfig:JsonVariation({}))
    }
  })
}
```

## 5. 서버 부하 관리

### 사례: 트래픽 제어

서버 부하가 높을 때 비핵심 기능을 비활성화하여 성능을 유지할 수 있습니다.

```lua
function initializeGameServices()
  -- 서버 상태에 따라 기능 활성화/비활성화
  if client:IsEnabled("leaderboards") then
    initializeLeaderboards()
  }
  
  if client:IsEnabled("friend-activity") then
    initializeFriendActivity()
  }
  
  if client:IsEnabled("detailed-match-history") then
    initializeMatchHistory()
  } else {
    initializeBasicMatchHistory()
  }
  
  -- 매치메이킹 풀 크기 조정
  local matchmakingConfig = client:GetVariantProxy("matchmaking-config")
  if matchmakingConfig:IsEnabled() then
    configureMatchmaking(matchmakingConfig:JsonVariation({}))
  }
}
```

### 사례: 긴급 상황 대응

```lua
-- 서버 상태 변경 시 호출
function onServerStatusUpdate(serverStatus)
  client:UpdateContext({
    properties = {
      serverLoad = serverStatus.currentLoad,
      serverRegion = serverStatus.region
    }
  }, function()
    -- 서버 부하에 따른 기능 조정
    if not client:IsEnabled("high-quality-textures") then
      useReducedTextures()
    }
    
    if not client:IsEnabled("particle-effects") then
      reduceParticleEffects()
    }
    
    if not client:IsEnabled("background-matchmaking") then
      pauseBackgroundMatchmaking()
    }
  })
}
```

## 6. 게임 밸런싱

### 사례: 무기 및 캐릭터 밸런싱

게임 내 무기, 캐릭터, 능력치 등을 실시간으로 조정할 수 있습니다.

```lua
function initializeGameBalance()
  -- 무기 밸런스
  local weaponBalance = client:GetVariantProxy("weapon-balance")
  if weaponBalance:IsEnabled() then
    applyWeaponStats(weaponBalance:JsonVariation({
      assault_rifle: { damage: 25, fireRate: 0.1, recoil: 0.3 },
      shotgun: { damage: 80, fireRate: 0.8, recoil: 0.7 },
      sniper: { damage: 120, fireRate: 1.2, recoil: 0.5 }
    }))
  }
  
  -- 캐릭터 능력치
  local characterBalance = client:GetVariantProxy("character-balance")
  if characterBalance:IsEnabled() then
    applyCharacterStats(characterBalance:JsonVariation({}))
  }
  
  -- 경험치 획득률
  local progressionConfig = client:GetVariantProxy("progression-speed")
  if progressionConfig:IsEnabled() then
    setXpMultiplier(progressionConfig:NumberVariation(1.0))
  }
}
```

### 사례: 매치메이킹 알고리즘 조정

```lua
function configureMatchmaking()
  local matchmakingVariant = client:GetVariantProxy("matchmaking-algorithm")
  
  if matchmakingVariant:IsEnabled() then
    local algorithm = matchmakingVariant:StringVariation("skill-based")
    local config = matchmakingVariant:JsonVariation({
      skillWeight: 0.7,
      pingWeight: 0.2,
      waitTimeWeight: 0.1,
      maxWaitTime: 60
    })
    
    setMatchmakingAlgorithm(algorithm, config)
  }
}
```

## 7. 디바이스 및 성능 최적화

### 사례: 디바이스 성능에 따른 그래픽 설정

사용자 디바이스 성능에 따라 그래픽 설정을 자동으로 조정할 수 있습니다.

```lua
function optimizeGraphicsSettings()
  -- 디바이스 정보 컨텍스트 설정
  local deviceInfo = getDeviceInfo()
  
  client:UpdateContext({
    properties = {
      deviceModel = deviceInfo.model,
      gpuTier = classifyGpuTier(deviceInfo.gpu),
      memoryGB = deviceInfo.totalMemoryGB,
      cpuCores = deviceInfo.cpuCores,
      osVersion = deviceInfo.osVersion
    }
  }, function()
    -- 고사양 그래픽 기능
    if client:IsEnabled("high-end-graphics") then
      enableHighEndGraphics()
    } else {
      enableBasicGraphics()
    }
    
    -- 그래픽 세부 설정
    local graphicsConfig = client:GetVariantProxy("graphics-config")
    if graphicsConfig:IsEnabled() then
      local config = graphicsConfig:JsonVariation({})
      setRenderDistance(config.renderDistance)
      setShadowQuality(config.shadowQuality)
      setTextureQuality(config.textureQuality)
      setAntiAliasing(config.antiAliasing)
    }
    
    -- 프레임 레이트 제한
    if client:IsEnabled("fps-limit") then
      setFrameRateLimit(client:NumberVariation("fps-limit-value", 60))
    }
  })
}
```

### 사례: 네트워크 최적화

```lua
function optimizeNetworkSettings()
  -- 네트워크 상태 확인
  local networkInfo = getNetworkInfo()
  
  client:UpdateContext({
    properties = {
      connectionType = networkInfo.connectionType, -- wifi, cellular, ethernet
      bandwidth = networkInfo.estimatedBandwidth,
      latency = networkInfo.averageLatency
    }
  }, function()
    -- 데이터 사용량 최적화
    if client:IsEnabled("data-saving-mode") then
      enableLowDataMode()
    }
    
    -- 네트워크 설정
    local networkConfig = client:GetVariantProxy("network-config")
    if networkConfig:IsEnabled() then
      local config = networkConfig:JsonVariation({})
      setUpdateFrequency(config.updateFrequency)
      setPacketSize(config.packetSize)
      setCompressionLevel(config.compressionLevel)
    }
  })
}
```

## 8. 명시적 동기화 모드 활용

### 사례: 게임 세션 중 일관성 유지

게임 세션 중에는 피처 플래그 변경을 방지하여 일관된 경험을 제공할 수 있습니다.

```lua
-- 명시적 동기화 모드로 클라이언트 초기화
local client = Client.New({
  -- 기본 구성...
  useExplicitSyncMode = true
})

-- 게임 세션 시작 시 플래그 동기화
function startGameSession()
  -- 최신 플래그로 동기화
  client:SyncToggles(true, function()
    print("게임 세션 시작 전 최신 기능 플래그 적용")
    
    -- 게임 세션 시작
    beginGameSession()
    
    -- 게임 세션 중에는 플래그 변경 없이 일관된 경험 제공
  end)
}

-- 게임 세션 종료 후 다시 동기화
function endGameSession()
  -- 게임 결과 저장 등 마무리 작업
  finalizeGameSession()
  
  -- 세션 종료 후 최신 플래그 동기화
  client:SyncToggles(true, function()
    print("게임 세션 종료 후 최신 기능 플래그 적용")
    returnToLobby()
  end)
}
```

### 사례: 레벨/맵 전환 시 동기화

```lua
-- 레벨 또는 맵 전환 시 동기화
function changeLevel(newLevelId)
  -- 로딩 화면 표시
  showLoadingScreen()
  
  -- 레벨 전환 전 최신 플래그 동기화
  client:SyncToggles(true, function()
    print("레벨 전환 시 최신 기능 플래그 적용")
    
    -- 새 레벨에 적용될 기능 확인
    local hasNewFeatures = client:IsEnabled("level-" .. newLevelId .. "-features")
    
    -- 레벨 로드 및 초기화
    loadLevel(newLevelId, hasNewFeatures)
    hideLoadingScreen()
  end)
}
```

## 9. 부트스트래핑 활용

### 사례: 오프라인 모드 지원

네트워크 연결 없이도 기본 기능을 사용할 수 있도록 부트스트래핑을 활용할 수 있습니다.

```lua
-- 오프라인 모드용 기본 피처 플래그
local offlineFeatureFlags = {
  {
    name = "offline-mode",
    enabled = true
  },
  {
    name = "single-player-campaign",
    enabled = true
  },
  {
    name = "multiplayer",
    enabled = false
  },
  {
    name = "graphics-quality",
    enabled = true,
    variant = {
      name = "medium",
      enabled = true,
      payload = {
        type = "json",
        value = {
          textureQuality = "medium",
          shadowQuality = "low",
          antiAliasing = false
        }
      }
    }
  }
}

-- 네트워크 연결 상태에 따라 클라이언트 초기화
function initializeFeatureFlags()
  local isOnline = checkNetworkConnection()
  
  local client = Client.New({
    url = "https://unleash.example.com/api",
    clientKey = "your-client-key",
    appName = "your-game-name",
    request = yourHttpRequestFunction,
    
    -- 오프라인 모드 설정
    offline = not isOnline,
    bootstrap = offlineFeatureFlags,
    
    -- 네트워크 연결이 있을 때만 자동 시작
    disableAutoStart = not isOnline
  })
  
  -- 네트워크 연결이 있으면 시작
  if isOnline then
    client:Start(function()
      print("온라인 모드로 피처 플래그 초기화 완료")
    end)
  } else {
    print("오프라인 모드로 피처 플래그 초기화 완료")
  }
  
  return client
}
```

### 사례: 빠른 게임 시작

```lua
-- 기본 설정으로 게임을 빠르게 시작하고, 백그라운드에서 최신 설정 로드
function quickStartGame()
  local defaultFeatureFlags = {
    {
      name = "quick-start",
      enabled = true
    },
    {
      name = "basic-graphics",
      enabled = true
    }
  }
  
  local client = Client.New({
    -- 기본 구성...
    bootstrap = defaultFeatureFlags,
    bootstrapOverride = false  -- 서버에서 가져온 값으로 나중에 덮어씀
  })
  
  -- 부트스트랩 값으로 즉시 게임 시작
  startGameWithBasicSettings()
  
  -- 백그라운드에서 최신 설정 로드
  client:WaitUntilReady(function()
    -- 필요한 경우 설정 업데이트
    updateGameSettings()
  end)
}
```

## 10. 실시간 이벤트 및 프로모션

### 사례: 플래시 세일

제한된 시간 동안 특별 할인을 제공할 수 있습니다.

```lua
function checkPromotions()
  if client:IsEnabled("flash-sale") then
    local saleConfig = client:GetVariantProxy("flash-sale-config")
    if saleConfig:IsEnabled() then
      local config = saleConfig:JsonVariation({
        discountPercent: 30,
        duration: 4, -- hours
        featuredItems: ["item1", "item2", "item3"]
      })
      
      applyFlashSale(config)
    }
  }
}
```


# Feature Flags 사용 시 주의사항

피처 플래그는 강력한 도구이지만, 효과적으로 사용하기 위해서는 몇 가지 주의사항을 고려해야 합니다. 이 문서에서는 온라인 게임에서 피처 플래그를 사용할 때 발생할 수 있는 잠재적 문제점과 이를 방지하기 위한 모범 사례를 설명합니다.

## 1. 코드 복잡성 관리

### 문제점

피처 플래그를 과도하게 사용하면 코드베이스가 복잡해지고 가독성이 저하될 수 있습니다.

```lua
-- 나쁜 예: 중첩된 조건문으로 인한 복잡성
function initializeGameFeatures()
  if client:IsEnabled("new-combat-system") then
    if client:IsEnabled("advanced-targeting") then
      if client:IsEnabled("auto-aim") then
        initializeAdvancedCombatWithAutoAim()
      else
        initializeAdvancedCombatWithoutAutoAim()
      end
    else
      initializeBasicCombatWithNewSystem()
    end
  else
    if client:IsEnabled("legacy-combat-improvements") then
      initializeImprovedLegacyCombat()
    else
      initializeClassicCombat()
    end
  end
end
```

### 모범 사례

1. **모듈화된 접근 방식 사용**

```lua
-- 좋은 예: 모듈화된 접근 방식
function initializeGameFeatures()
  initializeCombatSystem()
  initializeInventorySystem()
  initializeQuestSystem()
end

function initializeCombatSystem()
  local useNewCombat = client:IsEnabled("new-combat-system")
  local useAdvancedTargeting = useNewCombat and client:IsEnabled("advanced-targeting")
  local useAutoAim = useAdvancedTargeting and client:IsEnabled("auto-aim")
  
  if useNewCombat then
    if useAdvancedTargeting then
      initializeAdvancedTargeting(useAutoAim)
    end
    initializeNewCombatSystem()
  else
    local useImprovements = client:IsEnabled("legacy-combat-improvements")
    initializeLegacyCombat(useImprovements)
  end
end
```

2. **전략 패턴 활용**

```lua
-- 좋은 예: 전략 패턴 활용
local combatSystems = {
  ["new-with-auto-aim"] = initializeAdvancedCombatWithAutoAim,
  ["new-advanced"] = initializeAdvancedCombatWithoutAutoAim,
  ["new-basic"] = initializeBasicCombatWithNewSystem,
  ["legacy-improved"] = initializeImprovedLegacyCombat,
  ["legacy"] = initializeClassicCombat
}

function initializeCombatSystem()
  local systemKey = "legacy"
  
  if client:IsEnabled("new-combat-system") then
    if client:IsEnabled("advanced-targeting") then
      systemKey = client:IsEnabled("auto-aim") and "new-with-auto-aim" or "new-advanced"
    else
      systemKey = "new-basic"
    end
  elseif client:IsEnabled("legacy-combat-improvements") then
    systemKey = "legacy-improved"
  end
  
  combatSystems[systemKey]()
end
```

## 2. 기술적 부채 관리

### 문제점

오래된 피처 플래그가 제거되지 않으면 코드베이스가 복잡해지고 유지보수가 어려워집니다.

```lua
-- 나쁜 예: 오래된 플래그가 남아있는 경우
function renderUI()
  if client:IsEnabled("ui-v1-fixes") then  -- 2년 전에 추가된 플래그
    if client:IsEnabled("ui-v2") then  -- 1년 전에 추가된 플래그
      if client:IsEnabled("ui-v2-fixes") then  -- 6개월 전에 추가된 플래그
        if client:IsEnabled("ui-v3") then  -- 최근에 추가된 플래그
          renderUIV3()
        else
          renderUIV2WithFixes()
        end
      else
        renderUIV2()
      end
    else
      renderUIV1WithFixes()
    end
  else
    renderLegacyUI()  -- 더 이상 사용되지 않는 코드
  end
end
```

### 모범 사례

1. **플래그 수명 주기 관리**

```lua
-- 좋은 예: 명확한 플래그 버전 관리
function renderUI()
  local uiVersion = determineUIVersion()
  renderUIByVersion(uiVersion)
end

function determineUIVersion()
  if client:IsEnabled("ui-v3") then
    return "v3"
  elseif client:IsEnabled("ui-v2") then
    local withFixes = client:IsEnabled("ui-v2-fixes")
    return withFixes and "v2-fixed" or "v2"
  else
    return "v1"  -- v1-fixes 플래그는 제거됨
  end
end
```

2. **정기적인 플래그 정리**

- 출시 완료된 기능의 플래그 제거 일정 수립
- 각 플래그에 만료일 또는 검토일 설정
- 분기별로 오래된 플래그 검토 및 제거

## 3. 테스트 복잡성 관리

### 문제점

다양한 플래그 조합에 대한 테스트가 어려워질 수 있습니다.

```lua
-- 나쁜 예: 테스트하기 어려운 많은 조합
-- 플래그: combat-v2, inventory-v2, quest-v2, ui-v2, networking-v2
-- 가능한 조합: 2^5 = 32가지
```

### 모범 사례

1. **관련 플래그 그룹화**

```lua
-- 좋은 예: 관련 기능을 하나의 플래그로 그룹화
-- 플래그: game-systems-v2 (combat, inventory, quest 포함)
--         ui-v2
--         networking-v2
-- 가능한 조합: 2^3 = 8가지
```

2. **테스트 자동화**

```lua
-- 주요 플래그 조합에 대한 자동 테스트
function testAllCriticalPaths()
  local criticalCombinations = {
    { ["game-systems-v2"] = true, ["ui-v2"] = true, ["networking-v2"] = true },
    { ["game-systems-v2"] = true, ["ui-v2"] = true, ["networking-v2"] = false },
    { ["game-systems-v2"] = true, ["ui-v2"] = false, ["networking-v2"] = false },
    { ["game-systems-v2"] = false, ["ui-v2"] = false, ["networking-v2"] = false }
  }
  
  for _, combination in ipairs(criticalCombinations) do
    testWithFlagCombination(combination)
  end
end
```

## 4. 성능 영향 관리

### 문제점

과도한 플래그 평가는 런타임 성능에 영향을 줄 수 있습니다.

```lua
-- 나쁜 예: 매 프레임마다 플래그 확인
function update(dt)
  if client:IsEnabled("high-quality-rendering") then
    renderHighQuality()
  else
    renderStandardQuality()
  end
  
  if client:IsEnabled("advanced-physics") then
    updateAdvancedPhysics(dt)
  else
    updateBasicPhysics(dt)
  end
  
  -- 매 프레임마다 반복되는 많은 플래그 확인...
end
```

### 모범 사례

1. **결과 캐싱**

```lua
-- 좋은 예: 플래그 결과 캐싱
local useHighQualityRendering = false
local useAdvancedPhysics = false

function initializeSettings()
  useHighQualityRendering = client:IsEnabled("high-quality-rendering")
  useAdvancedPhysics = client:IsEnabled("advanced-physics")
  
  -- 플래그 변경 이벤트 구독
  client:On(FeatureFlags.Events.UPDATE, function()
    useHighQualityRendering = client:IsEnabled("high-quality-rendering")
    useAdvancedPhysics = client:IsEnabled("advanced-physics")
  end)
end

function update(dt)
  if useHighQualityRendering then
    renderHighQuality()
  else
    renderStandardQuality()
  end
  
  if useAdvancedPhysics then
    updateAdvancedPhysics(dt)
  else
    updateBasicPhysics(dt)
  end
end
```

2. **성능 중요 경로에서 플래그 사용 최소화**

```lua
-- 좋은 예: 초기화 시점에만 플래그 확인
function initializeGame()
  -- 게임 시작 시 한 번만 설정
  if client:IsEnabled("high-quality-rendering") then
    initializeHighQualityRenderer()
  else
    initializeStandardRenderer()
  end
  
  if client:IsEnabled("advanced-physics") then
    initializeAdvancedPhysicsEngine()
  else
    initializeBasicPhysicsEngine()
  end
end
```

## 5. 사용자 경험 일관성 유지

### 문제점

피처 플래그가 갑자기 변경되면 사용자 경험이 일관되지 않을 수 있습니다.

```lua
-- 나쁜 예: 게임 중 갑작스러운 변경
function onFeatureFlagsUpdated()
  -- 플래그가 변경되면 즉시 UI 재구성
  if client:IsEnabled("new-ui-layout") then
    switchToNewUILayout()  -- 사용자가 메뉴 탐색 중일 때 혼란 야기
  }
  
  -- 게임 규칙 변경
  if client:IsEnabled("updated-game-rules") then
    applyNewGameRules()  -- 게임 중 규칙 변경으로 혼란 야기
  }
}
```

### 모범 사례

1. **명시적 동기화 모드 사용**

```lua
-- 좋은 예: 명시적 동기화 모드로 변경 시점 제어
local client = Client.New({
  -- 기본 구성...
  useExplicitSyncMode = true
})

-- 적절한 시점에만 동기화
function onLevelCompleted()
  -- 레벨 완료 후 동기화
  client:SyncToggles(true, function()
    -- 이제 다음 레벨에 새 기능 적용
    prepareNextLevel()
  end)
}
```

2. **자연스러운 전환점 활용**

```lua
-- 좋은 예: 자연스러운 전환점 활용
function onMainMenuEntered()
  -- 메인 메뉴에서 플래그 동기화
  client:SyncToggles(true, function()
    -- UI 업데이트
    if client:IsEnabled("new-ui-layout") then
      initializeNewUILayout()
    } else {
      initializeClassicUILayout()
    }
  })
}

function onMatchEnded()
  -- 매치 종료 후 플래그 동기화
  client:SyncToggles(true, function()
    -- 다음 매치에 새 규칙 적용
    if client:IsEnabled("updated-game-rules") then
      prepareNewGameRules()
    } else {
      prepareClassicGameRules()
    }
  })
}
```

## 6. 네트워크 요청 최적화

### 문제점

과도한 컨텍스트 업데이트는 불필요한 네트워크 요청을 발생시킬 수 있습니다.

```lua
-- 나쁜 예: 과도한 컨텍스트 업데이트
function update(dt)
  -- 매 프레임마다 위치 업데이트
  local playerPosition = getPlayerPosition()
  client:SetContextField("playerX", playerPosition.x)
  client:SetContextField("playerY", playerPosition.y)
  client:SetContextField("playerZ", playerPosition.z)
  
  -- 매 프레임마다 시간 업데이트
  client:SetContextField("currentTime", os.time())
}
```

### 모범 사례

1. **업데이트 빈도 제한**

```lua
-- 좋은 예: 업데이트 빈도 제한
local lastPositionUpdate = 0
local lastTimeUpdate = 0

function update(dt)
  local currentTime = os.time()
  
  -- 5초마다 위치 업데이트
  if currentTime - lastPositionUpdate > 5 then
    local playerPosition = getPlayerPosition()
    client:UpdateContext({
      properties = {
        playerPosition = {
          x = playerPosition.x,
          y = playerPosition.y,
          z = playerPosition.z
        }
      }
    })
    lastPositionUpdate = currentTime
  end
  
  -- 1분마다 시간 업데이트
  if currentTime - lastTimeUpdate > 60 then
    client:SetContextField("currentTime", currentTime)
    lastTimeUpdate = currentTime
  end
}
```

2. **중요한 변경 사항만 업데이트**

```lua
-- 좋은 예: 중요한 변경 사항만 업데이트
local lastPlayerZone = ""

function checkPlayerZone()
  local currentZone = getPlayerZone()
  
  -- 플레이어가 다른 구역으로 이동한 경우에만 업데이트
  if currentZone ~= lastPlayerZone then
    client:SetContextField("playerZone", currentZone, function()
      -- 구역별 기능 확인
      if client:IsEnabled("zone-specific-features") then
        applyZoneFeatures(currentZone)
      end
    end)
    lastPlayerZone = currentZone
  end
}
```

## 7. 오류 처리 및 폴백 전략

### 문제점

피처 플래그 서비스 연결 실패 시 게임 기능이 중단될 수 있습니다.

```lua
-- 나쁜 예: 오류 처리 부재
function initializeGame()
  -- 피처 플래그 초기화 실패 시 게임이 중단될 수 있음
  client:Start(function()
    startGame()
  })
}
```

### 모범 사례

1. **오류 이벤트 처리**

```lua
-- 좋은 예: 오류 이벤트 처리
function initializeFeatureFlags()
  client:On(FeatureFlags.Events.ERROR, function(error)
    print("피처 플래그 오류:", error.message)
    
    -- 오류 로깅
    logError("FeatureFlags", error.message)
    
    -- 기본값으로 폴백
    useDefaultFeatures()
  })
  
  client:Start(function()
    print("피처 플래그 초기화 성공")
    startGame()
  })
}
```

2. **부트스트랩 데이터로 폴백**

```lua
-- 좋은 예: 부트스트랩 데이터로 폴백
local defaultFeatureFlags = {
  {
    name = "essential-features",
    enabled = true
  },
  {
    name = "advanced-graphics",
    enabled = false
  }
}

local client = Client.New({
  -- 기본 구성...
  bootstrap = defaultFeatureFlags,
  bootstrapOverride = false
})

function initializeGame()
  -- 타임아웃 설정
  local initTimeout = setTimeout(function()
    print("피처 플래그 초기화 타임아웃, 기본값 사용")
    startGameWithDefaultFeatures()
  }, 5000)  -- 5초 타임아웃
  
  client:Start(function()
    clearTimeout(initTimeout)
    print("피처 플래그 초기화 성공")
    startGame()
  })
}
```

## 8. 보안 고려 사항

### 문제점

민감한 정보가 컨텍스트에 포함되거나, 중요한 게임 로직이 클라이언트 측 플래그에 의존할 수 있습니다.

```lua
-- 나쁜 예: 민감한 정보 포함
client:UpdateContext({
  userId = "user123",
  properties = {
    authToken = "eyJhbGciOiJIUzI1...",  -- 민감한 정보
    email = "user@example.com",         -- 개인 식별 정보
    purchaseHistory = { ... }           -- 민감한 정보
  }
})

-- 나쁜 예: 중요한 게임 로직을 클라이언트 측 플래그에 의존
function calculateRewards(score) {
  if client:IsEnabled("double-rewards") then
    return score * 2  -- 클라이언트에서 조작 가능
  } else {
    return score
  }
}
```

### 모범 사례

1. **민감한 정보 제외**

```lua
-- 좋은 예: 안전한 정보만 포함
client:UpdateContext({
  userId = "user123",
  properties = {
    userTier = "premium",      -- 민감하지 않은 정보
    hasCompletedTutorial = true,
    deviceCategory = "high-end"
  }
})
```

2. **중요한 로직은 서버 측에서 처리**

```lua
-- 좋은 예: 중요한 로직은 서버 측에서 처리
function submitScore(score) {
  -- 점수를 서버로 전송하고 서버에서 보상 계산
  sendToServer("submit_score", {
    score = score,
    level = currentLevel,
    timestamp = os.time()
  })
}

-- 서버에서 피처 플래그 확인 후 보상 계산
-- server-side code (pseudo):
-- function calculateRewards(userId, score) {
--   if isFeatureEnabled("double-rewards", userId) {
--     return score * 2
--   } else {
--     return score
--   }
-- }
```

## 9. 사용자 피드백 및 모니터링

### 문제점

피처 플래그 변경의 영향을 추적하지 않으면 문제를 조기에 발견하기 어렵습니다.

```lua
-- 나쁜 예: 모니터링 부재
function enableNewFeature() {
  if client:IsEnabled("new-feature") then
    showNewFeature()  -- 문제가 발생해도 알 수 없음
  }
}
```

### 모범 사례

1. **노출 이벤트 추적**

```lua
-- 좋은 예: 노출 이벤트 추적
function checkNewFeature() {
  if client:IsEnabled("new-feature") then
    -- 노출 이벤트 기록
    client:RecordImpression("new-feature")
    
    -- 분석 이벤트 전송
    trackAnalyticsEvent("feature_shown", {
      featureId = "new-feature",
      userId = getCurrentUserId()
    })
    
    showNewFeature()
  }
}
```

2. **사용자 피드백 수집**

```lua
-- 좋은 예: 사용자 피드백 수집
function showNewFeature() {
  -- 피드백 폼 표시
  showFeedbackForm("new-feature", function(feedback) {
    -- 피드백 전송
    sendFeedbackToServer("new-feature", feedback)
  })
}
```



# 피처 플래그 노출 데이터(Impression Data)

## 노출 데이터란?

노출 데이터(Impression Data)는 사용자가 특정 피처 플래그에 노출되었을 때 기록되는 정보입니다. 이는 피처 플래그가 평가되고 사용될 때마다 생성되는 이벤트로, 다음과 같은 정보를 포함합니다:

- 피처 플래그 이름
- 활성화 여부(enabled/disabled)
- 변형(variant) 정보 (해당하는 경우)
- 사용자 컨텍스트
- 타임스탬프
- 이벤트 유형 (isEnabled, getVariant 등)

## 노출 데이터를 사용해야 하는 이유

### 1. 사용량 추적 및 분석

노출 데이터를 통해 어떤 피처 플래그가 얼마나 자주 평가되는지, 어떤 사용자들이 특정 기능에 노출되었는지 파악할 수 있습니다. 이는 다음과 같은 질문에 답하는 데 도움이 됩니다:

- "새로운 기능이 실제로 사용되고 있는가?"
- "어떤 사용자 세그먼트가 이 기능을 가장 많이 사용하는가?"
- "특정 기능이 사용되지 않는 이유는 무엇인가?"

### 2. A/B 테스트 분석

A/B 테스트를 실행할 때, 노출 데이터는 각 변형(variant)에 노출된 사용자 수와 그 결과를 정확하게 측정하는 데 필수적입니다. 이를 통해:

- 각 변형의 전환율 계산
- 통계적 유의성 평가
- 사용자 행동 패턴 분석

### 3. 디버깅 및 문제 해결

노출 데이터는 예상치 못한 동작이 발생했을 때 디버깅에 도움이 됩니다:

- 특정 사용자가 기능에 노출되었는지 확인
- 피처 플래그 평가 시점과 컨텍스트 파악
- 기능 활성화/비활성화 패턴 분석

### 4. 성능 최적화

자주 평가되는 피처 플래그를 식별하여 성능 최적화에 활용할 수 있습니다:

- 불필요하게 자주 평가되는 플래그 식별
- 캐싱 전략 개선
- 평가 빈도 최적화

## 노출 데이터 구현 방법

Feature Flags 클라이언트에서 노출 데이터를 활성화하고 사용하는 방법은 다음과 같습니다:

### 1. 클라이언트 초기화 시 설정

```lua
local client = Client.New({
  url = "https://unleash.example.com/api",
  clientKey = "your-client-key",
  appName = "your-game-name",
  
  -- 모든 피처 플래그에 대해 노출 데이터 활성화
  impressionDataAll = true,
  
  -- 또는 기본적으로 비활성화하고 개별 토글에서만 활성화
  impressionDataAll = false
})
```

### 2. 개별 토글에 대한 노출 데이터 설정

서버 측에서 특정 토글에 대해서만 노출 데이터를 활성화할 수 있습니다. 이 경우 토글 구성에 `impressionData: true`를 포함시킵니다.

### 3. 노출 이벤트 구독

```lua
-- 노출 이벤트 구독
client:On(FeatureFlags.Events.IMPRESSION, function(event)
  -- 노출 이벤트 처리
  print("피처 플래그 노출:", event.featureName, "활성화:", event.enabled)
  
  -- 분석 시스템으로 이벤트 전송
  trackAnalyticsEvent("feature_flag_impression", {
    featureName = event.featureName,
    enabled = event.enabled,
    eventType = event.eventType,
    userId = event.context.userId,
    timestamp = os.time()
  })
  
  -- 변형 정보가 있는 경우
  if event.variantName then
    print("변형:", event.variantName)
  end
})
```

## 노출 데이터 예제

### 기본 기능 토글 노출

```lua
-- IsEnabled 호출 시 노출 데이터 생성
function checkNewFeature()
  if client:IsEnabled("new-combat-system") then
    -- 이 호출은 다음과 같은 노출 이벤트를 생성합니다:
    -- {
    --   eventType: "isEnabled",
    --   eventId: "550e8400-e29b-41d4-a716-446655440000",
    --   context: { userId: "user123", ... },
    --   enabled: true,
    --   featureName: "new-combat-system",
    --   impressionData: { ... }
    -- }
    
    initializeNewCombatSystem()
  else
    initializeLegacyCombatSystem()
  end
}
```

### 변형(Variant) 노출

```lua
-- GetVariant 호출 시 노출 데이터 생성
function initializeTutorial()
  local tutorialVariant = client:GetVariant("tutorial-version")
  
  if tutorialVariant:IsEnabled() then
    local version = tutorialVariant:StringVariation("default")
    
    -- 이 호출은 다음과 같은 노출 이벤트를 생성합니다:
    -- {
    --   eventType: "getVariant",
    --   eventId: "550e8400-e29b-41d4-a716-446655440001",
    --   context: { userId: "user123", ... },
    --   enabled: true,
    --   featureName: "tutorial-version",
    --   variantName: "interactive",
    --   impressionData: { ... }
    -- }
    
    if version == "interactive" then
      showInteractiveTutorial()
    elseif version == "video" then
      showVideoTutorial()
    else
      showDefaultTutorial()
    end
  else
    showDefaultTutorial()
  end
}
```

## 노출 데이터 활용 사례

### 1. 사용자 세그먼트별 기능 사용 분석

```lua
-- 노출 데이터를 활용한 사용자 세그먼트 분석
client:On(FeatureFlags.Events.IMPRESSION, function(event)
  if event.featureName == "premium-features" then
    -- 프리미엄 기능 노출 데이터 수집
    local userSegment = getUserSegment(event.context.userId)
    
    incrementCounter("premium_feature_impressions", {
      segment = userSegment,
      enabled = event.enabled
    })
    
    -- 프리미엄 기능 활성화 비율 추적
    if event.enabled then
      incrementCounter("premium_feature_enabled", {
        segment = userSegment
      })
    end
  end
})
```

### 2. A/B 테스트 결과 분석

```lua
-- A/B 테스트 결과 분석을 위한 노출 데이터 활용
client:On(FeatureFlags.Events.IMPRESSION, function(event)
  if event.featureName == "shop-layout" and event.eventType == "getVariant" then
    -- 상점 레이아웃 A/B 테스트 노출 추적
    recordExposure("shop_layout_test", {
      userId = event.context.userId,
      variant = event.variantName
    })
    
    -- 나중에 구매 전환율과 연결하여 분석
    -- 예: 각 변형별 구매 전환율 = 구매 수 / 노출 수
  end
})

-- 구매 이벤트 발생 시
function onPurchaseCompleted(userId, amount)
  -- 구매 이벤트 기록
  recordConversion("shop_layout_test", {
    userId = userId,
    amount = amount
  })
}
```

### 3. 기능 사용 패턴 분석

```lua
-- 시간대별 기능 사용 패턴 분석
local hourlyImpressions = {}
for i = 0, 23 do
  hourlyImpressions[i] = 0
end

client:On(FeatureFlags.Events.IMPRESSION, function(event)
  if event.featureName == "daily-quests" then
    -- 현재 시간 (0-23)
    local hour = os.date("*t").hour
    
    -- 시간대별 노출 횟수 증가
    hourlyImpressions[hour] = hourlyImpressions[hour] + 1
    
    -- 주기적으로 분석 서버에 데이터 전송
    if hourlyImpressions[hour] % 100 == 0 then
      sendAnalyticsData("hourly_feature_usage", {
        feature = "daily-quests",
        hourlyData = hourlyImpressions
      })
    end
  end
})
```

### 4. 디버깅 및 문제 해결

```lua
-- 디버깅을 위한 노출 데이터 로깅
local debugMode = true

client:On(FeatureFlags.Events.IMPRESSION, function(event)
  if debugMode then
    -- 개발 모드에서만 상세 로깅
    print(string.format(
      "[FeatureFlags] %s: '%s' = %s, Context: %s",
      event.eventType,
      event.featureName,
      tostring(event.enabled),
      Util.Inspect(event.context)
    ))
    
    -- 특정 사용자의 노출 데이터만 자세히 로깅
    if event.context.userId == "test-user-123" then
      logToFile("feature_flags_debug.log", Util.Inspect(event))
    end
  end
})
```

## 노출 데이터 최적화

노출 데이터는 유용하지만, 과도한 데이터 생성은 성능에 영향을 줄 수 있습니다. 다음과 같은 최적화 전략을 고려하세요:

### 1. 선택적 활성화

모든 피처 플래그가 아닌 중요한 플래그에 대해서만 노출 데이터를 활성화합니다:

```lua
-- 클라이언트 설정
local client = Client.New({
  -- 기본 구성...
  impressionDataAll = false  -- 기본적으로 비활성화
})

-- 서버 측에서 중요한 플래그에만 impressionData: true 설정
```

### 2. 샘플링

모든 노출을 기록하는 대신 일부만 샘플링하여 처리합니다:

```lua
-- 노출 데이터 샘플링 (10%)
client:On(FeatureFlags.Events.IMPRESSION, function(event)
  -- 10%의 확률로만 처리
  if math.random() < 0.1 then
    trackAnalyticsEvent("feature_impression", {
      -- 이벤트 데이터...
      sampled = true
    })
  end
})
```

### 3. 배치 처리

노출 이벤트를 실시간으로 처리하는 대신 배치로 모아서 처리합니다:

```lua
-- 배치 처리를 위한 노출 데이터 수집
local impressionBatch = {}
local MAX_BATCH_SIZE = 100
local BATCH_INTERVAL = 60  -- 60초

client:On(FeatureFlags.Events.IMPRESSION, function(event)
  -- 배치에 이벤트 추가
  table.insert(impressionBatch, {
    featureName = event.featureName,
    enabled = event.enabled,
    eventType = event.eventType,
    variantName = event.variantName,
    timestamp = os.time(),
    userId = event.context.userId
  })
  
  -- 배치 크기가 최대에 도달하면 전송
  if #impressionBatch >= MAX_BATCH_SIZE then
    sendImpressionBatch()
  end
})

-- 주기적으로 배치 전송
function setupBatchTimer()
  Timer.Perform(function()
    if #impressionBatch > 0 then
      sendImpressionBatch()
    end
  end):Delay(BATCH_INTERVAL):StartDelay(BATCH_INTERVAL)
end

function sendImpressionBatch()
  -- 배치 복사 및 초기화
  local batch = Util.DeepClone(impressionBatch)
  impressionBatch = {}
  
  -- 분석 서버로 배치 전송
  sendAnalyticsData("feature_impressions_batch", {
    impressions = batch,
    count = #batch
  })
end
```

## 결론

노출 데이터는 피처 플래그의 사용 패턴을 이해하고, A/B 테스트를 분석하며, 문제를 디버깅하는 데 필수적인 도구입니다. 적절히 구성하고 최적화하면 게임 개발 및 운영에 귀중한 인사이트를 제공할 수 있습니다. 그러나 성능 영향을 고려하여 필요한 경우에만 선택적으로 활성화하고, 데이터 처리를 최적화하는 것이 중요합니다.
