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

이 SDK는 Unreal Engine 4의 자체 구현된 `HttpRequest` 함수를 통해 HTTP 통신을 처리합니다. 이 함수는 다음과 같은 특징을 가지고 있습니다:

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
  local variantProxy = client:GetVariant("my-feature-with-variants")
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
local paymentVariant = client:GetVariant("payment-gateway")
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
    local matchmakingVariant = client:GetVariant("matchmaking-algorithm")
    local algorithm = matchmakingVariant:StringVariation("default")
    
    -- 선택된 알고리즘으로 매치메이킹 시작
    beginMatchmaking(algorithm)
  end)
end

-- 게임 인스턴스 생성 시 동기화
function createGameInstance(players)
  client:SyncToggles(true, function()
    -- 게임 모드 확인
    local gameModeVariant = client:GetVariant("game-mode-settings")
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
      local eventVariant = client:GetVariant("daily-special-event")
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
        rewards = client:GetVariant("pvp-rewards"):JsonVariation({})
      }
      initializePvPMode(pvpFeatures)
    else
      -- PvE 관련 기능 확인
      local pveFeatures = {
        difficulty = client:GetVariant("pve-difficulty"):StringVariation("normal"),
        enemies = client:GetVariant("pve-enemy-types"):JsonVariation({})
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

```lua
-- 변형 정보 가져오기
local variantProxy = client:GetVariant("my-feature")
print("변형 이름:", variantProxy:GetVariantName())
print("기능 이름:", variantProxy:GetFeatureName())
print("기능 활성화:", variantProxy:IsEnabled())

-- 변형 데이터 타입별 접근
local boolValue = variantProxy:BoolVariation(false)
local numberValue = variantProxy:NumberVariation(0)
local stringValue = variantProxy:StringVariation("default")
local jsonValue = variantProxy:JsonVariation({})

-- 또는 클라이언트에서 직접 타입별 변형 접근
local boolValue = client:BoolVariation("my-bool-feature", false)
local numberValue = client:NumberVariation("my-number-feature", 0)
local stringValue = client:StringVariation("my-string-feature", "default")
local jsonValue = client:JsonVariation("my-json-feature", {})
```

`GetVariant` 메서드는 `VariantProxy` 객체를 반환합니다. 이 프록시 객체는 변형 데이터에 안전하게 접근할 수 있는 다양한 메서드를 제공합니다:

- `GetFeatureName()`: 기능 이름 반환
- `GetVariantName()`: 변형 이름 반환
- `GetRawVariant()`: 원본 변형 객체 반환
- `IsEnabled()`: 기능 활성화 여부 반환
- `BoolVariation(defaultValue)`: 불리언 값 반환
- `NumberVariation(defaultValue)`: 숫자 값 반환
- `StringVariation(defaultValue)`: 문자열 값 반환
- `JsonVariation(defaultValue)`: JSON 객체 값 반환

## 컨텍스트 관리

```lua
-- 컨텍스트 업데이트
client:UpdateContext({
  userId = "new-user-id",
  properties = {
    region = "europe",
    deviceType = "mobile"
  }
}, function()
  print("컨텍스트가 업데이트되었습니다!")
})

-- 현재 컨텍스트 가져오기
local context = client:GetContext()
print("사용자 ID:", context.userId)

-- 특정 컨텍스트 필드 설정
client:SetContextField("userId", "another-user-id", function()
  print("사용자 ID가 업데이트되었습니다!")
})
```
