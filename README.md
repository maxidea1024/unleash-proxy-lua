# Unleash Client for Lua

Lua 애플리케이션을 위한 피처 플래그 클라이언트로, Unleash 서버에 연결하여 동작합니다. 이 클라이언트를 사용하면 최소한의 노력으로 Lua 애플리케이션에서 피쳐 플래그를 관리할 수 있습니다.

![Feature Flags Demo](doc/2025-05-21%2019%2023%2048.mp4)

## 특징

- **점진적 출시**: 새 기능을 일부 사용자에게만 먼저 제공하여 위험을 최소화
- **A/B 테스트**: 다양한 기능 변형을 테스트하여 최적의 사용자 경험 발견
- **카나리 배포**: 새 기능을 소수의 사용자에게 먼저 출시하여 문제 조기 발견
- **피쳐 플래그**: 문제 발생 시 코드 롤백 없이 즉시 기능 비활성화 가능
- **조건부 기능**: 특정 사용자, 지역, 디바이스 등에 따라 다른 기능 제공
- **구독 기반 기능**: 프리미엄 사용자에게만 특정 기능 제공
- **계절 이벤트**: 특정 기간에만 활성화되는 기능 관리

## 설치

Lua 프로젝트에 `unleash` 모듈을 포함하세요:

```lua
local Unleash = require("framework.3rdparty.unleash.index")
```

## 초기화

```lua
local Unleash = require("framework.3rdparty.unleash.index")
local UnleashClient = Unleash.UnleashClient

-- 클라이언트 초기화
local client = UnleashClient.New({
  url = "https://unleash.example.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  request = function(url, method, headers, body, callback)
    -- HTTP 요청 함수 구현
    -- 반드시 다음 형식의 응답 객체로 콜백을 호출해야 함:
    -- { status = number, headers = table, body = string }
  end
})
```

선택적 매개변수:

```lua
local client = UnleashClient.New({
  -- 필수 매개변수
  url = "https://unleash.example.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  request = yourHttpRequestFunction,
  
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
  }
})
```

> **참고**: 폴링 주기를 0으로 설정하거나 `disableRefresh = true`로 설정하면 자동 폴링이 비활성화되며, `UpdateToggles()` 메서드를 통해 수동으로만 업데이트할 수 있습니다.

## 사용 방법

### 기본 사용법

```lua
-- 피처 플래그 확인
if client:IsEnabled("feature-a") then
  -- 기능 A가 활성화된 경우 실행할 코드
else
  -- 기능 A가 비활성화된 경우 실행할 코드
end

-- 변형(variant) 가져오기
local variant = client:GetVariant("feature-b")
if variant:IsEnabled() then
  local payload = variant:JsonVariation({}) -- 기본값은 빈 객체
  -- payload를 사용하는 코드
end

-- 토글 변경 이벤트 구독
client:On(FeatureFlags.Events.UPDATE, function()
  -- 토글이 업데이트되면 실행할 코드
end)

-- 특정 토글 변경 이벤트 구독
client:WatchToggle("feature-c", function(variant)
  if variant:IsEnabled() then
    -- 기능 C가 활성화되면 실행할 코드
  else
    -- 기능 C가 비활성화되면 실행할 코드
  end
end)
```

## 피처 플래그란?

피처 플래그(Feature Flag)는 코드 변경 없이 기능을 동적으로 활성화하거나 비활성화할 수 있는 소프트웨어 개발 기법입니다. 이를 통해 개발자는 배포와 기능 출시를 분리하여 더 안전하고 유연하게 소프트웨어를 관리할 수 있습니다.

[featureflags.io](https://featureflags.io/)에 설명된 내용을 살펴보면 피처 플래그에 대한 자세한 내용을 확인할 수 있습니다.

### 피처 플래그의 단점

<!-- 기존 단점 내용 유지 -->

## 부트스트랩 사용 사례

### 1. 서버 연결 전 초기 상태 제공

```lua
local client = UnleashClient.New({
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
end)
```

### 2. 서버 다운타임 대비

```lua
local client = UnleashClient.New({
  -- 기본 구성...
  bootstrap = initialFeatureFlags,
  bootstrapOverride = false  -- 저장된 값이 있으면 사용
})

-- 오류 처리
client:On(FeatureFlags.Events.ERROR, function(error)
  print("서버 연결 오류, 부트스트랩/캐시된 값 사용 중:", error.message)
end)
```

### 3. 개발 환경에서 테스트

```lua
-- 개발 환경에서 특정 기능 강제 활성화
local devBootstrap = {
  {
    name = "new-experimental-feature",
    enabled = true
  }
}
```

## 명시적 동기화 모드

명시적 동기화 모드(Explicit Sync Mode)는 서버에서 받은 피처 플래그 업데이트를 즉시 적용하지 않고, 개발자가 명시적으로 동기화를 요청할 때만 적용하는 기능입니다. 이 모드는 다음과 같은 상황에서 유용합니다:

- 중요한 작업 중 예상치 못한 기능 변경 방지
- 특정 시점(예: 화면 전환, 세션 시작)에만 업데이트 적용
- 여러 관련 기능을 동시에 업데이트해야 하는 경우

**참고**: 명시적 동기화 모드로 동작중일때도 `WatchToggle`, `WatchToggleWithInitialState` 함수를 사용할 수 있습니다. 이 함수들은 Realtime toggles에 기반하여 동작합니다.

### 실시간 업데이트의 잠재적 문제점

<!-- 기존 내용 유지 -->

### 명시적 동기화 모드 활성화

```lua
local client = UnleashClient.New({
  url = "https://unleash.example.com/api",
  clientKey = "your-client-key",
  appName = "your-app-name",
  request = yourHttpRequestFunction,

  -- 명시적 동기화 모드 활성화
  useExplicitSyncMode = true
})
```

### 명시적 동기화 모드 사용 사례

<!-- 기존 내용 유지 -->

## 컨텍스트 초기화

### 초기화 시 컨텍스트 설정

```lua
local client = UnleashClient.New({
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

<!-- 나머지 컨텍스트 관련 내용 유지 -->

## 피처 플래그 노출 데이터(Impression Data)

노출 데이터(Impression Data)는 사용자가 특정 피처 플래그에 노출되었을 때 기록되는 정보입니다. 이 기능을 활용하면 피처 플래그의 사용 패턴을 분석하고, A/B 테스트 결과를 측정하며, 문제를 디버깅하는 데 도움이 됩니다.

### 노출 데이터 활성화

노출 데이터는 다음과 같은 방법으로 활성화할 수 있습니다:

```lua
-- 모든 피처 플래그에 대해 노출 데이터 활성화
local client = UnleashClient.New({
  -- 기본 구성...
  impressionDataAll = true
})

-- 노출 이벤트 구독
client:On(FeatureFlags.Events.IMPRESSION, function(event)
  -- 노출 이벤트 처리
  print("피처 플래그 노출:", event.featureName, "활성화:", event.enabled)
  
  -- 분석 시스템으로 이벤트 전송
  trackAnalyticsEvent("feature_impression", {
    featureName = event.featureName,
    enabled = event.enabled,
    eventType = event.eventType,
    variantName = event.variantName
  })
})
```

### 노출 데이터 활용 사례

노출 데이터는 다음과 같은 용도로 활용할 수 있습니다:

1. **사용량 분석**: 어떤 피처 플래그가 얼마나 자주 평가되는지 추적
2. **A/B 테스트 분석**: 각 변형(variant)에 노출된 사용자 수와 결과 측정
3. **디버깅**: 예상치 못한 동작이 발생했을 때 문제 해결에 활용
4. **사용자 세그먼트 분석**: 특정 기능에 노출된 사용자 그룹 파악

### 성능 최적화

노출 데이터는 유용하지만, 과도한 데이터 생성은 성능에 영향을 줄 수 있습니다. 다음과 같은 최적화 전략을 고려하세요:

1. **선택적 활성화**: 중요한 플래그에 대해서만 노출 데이터 활성화
2. **샘플링**: 모든 노출을 기록하는 대신 일부만 샘플링하여 처리
3. **배치 처리**: 노출 이벤트를 실시간으로 처리하는 대신 배치로 모아서 처리

## Feature Flags 사용 시 주의사항

<!-- 주의사항 관련 내용 유지 -->
    -- 채팅 필터
    if client:IsEnabled("chat-filter") then
      local filterConfig = client:GetVariant("chat-filter-config")
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
  local matchmakingConfig = client:GetVariant("matchmaking-config")
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
  local weaponBalance = client:GetVariant("weapon-balance")
  if weaponBalance:IsEnabled() then
    applyWeaponStats(weaponBalance:JsonVariation({
      assault_rifle: { damage: 25, fireRate: 0.1, recoil: 0.3 },
      shotgun: { damage: 80, fireRate: 0.8, recoil: 0.7 },
      sniper: { damage: 120, fireRate: 1.2, recoil: 0.5 }
    }))
  }

  -- 캐릭터 능력치
  local characterBalance = client:GetVariant("character-balance")
  if characterBalance:IsEnabled() then
    applyCharacterStats(characterBalance:JsonVariation({}))
  }

  -- 경험치 획득률
  local progressionConfig = client:GetVariant("progression-speed")
  if progressionConfig:IsEnabled() then
    setXpMultiplier(progressionConfig:NumberVariation(1.0))
  }
}
```

### 사례: 매치메이킹 알고리즘 조정

```lua
function configureMatchmaking()
  local matchmakingVariant = client:GetVariant("matchmaking-algorithm")

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
    local graphicsConfig = client:GetVariant("graphics-config")
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
    local networkConfig = client:GetVariant("network-config")
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
local client = UnleashClient.New({
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

  local client = UnleashClient.New({
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

  local client = UnleashClient.New({
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
    local saleConfig = client:GetVariant("flash-sale-config")
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
local client = UnleashClient.New({
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

local client = UnleashClient.New({
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

노출 데이터(Impression Data)는 사용자가 특정 피처 플래그에 노출되었을 때 기록되는 정보입니다. 이 기능을 활용하면 피처 플래그의 사용 패턴을 분석하고, A/B 테스트 결과를 측정하며, 문제를 디버깅하는 데 도움이 됩니다.

### 노출 데이터 활성화

노출 데이터는 다음과 같은 방법으로 활성화할 수 있습니다:

```lua
-- 모든 피처 플래그에 대해 노출 데이터 활성화
local client = UnleashClient.New({
  -- 기본 구성...
  impressionDataAll = true
})

-- 노출 이벤트 구독
client:On(FeatureFlags.Events.IMPRESSION, function(event)
  -- 노출 이벤트 처리
  print("피처 플래그 노출:", event.featureName, "활성화:", event.enabled)
  
  -- 분석 시스템으로 이벤트 전송
  trackAnalyticsEvent("feature_impression", {
    featureName = event.featureName,
    enabled = event.enabled,
    eventType = event.eventType,
    variantName = event.variantName
  })
})
```

### 노출 데이터 활용 사례

노출 데이터는 다음과 같은 용도로 활용할 수 있습니다:

1. **사용량 분석**: 어떤 피처 플래그가 얼마나 자주 평가되는지 추적
2. **A/B 테스트 분석**: 각 변형(variant)에 노출된 사용자 수와 결과 측정
3. **디버깅**: 예상치 못한 동작이 발생했을 때 문제 해결에 활용
4. **사용자 세그먼트 분석**: 특정 기능에 노출된 사용자 그룹 파악

### 성능 최적화

노출 데이터는 유용하지만, 과도한 데이터 생성은 성능에 영향을 줄 수 있습니다. 다음과 같은 최적화 전략을 고려하세요:

1. **선택적 활성화**: 중요한 플래그에 대해서만 노출 데이터 활성화
2. **샘플링**: 모든 노출을 기록하는 대신 일부만 샘플링하여 처리
3. **배치 처리**: 노출 이벤트를 실시간으로 처리하는 대신 배치로 모아서 처리

## 노출 데이터 구현 방법

Feature Flags 클라이언트에서 노출 데이터를 활성화하고 사용하는 방법은 다음과 같습니다:

### 1. 클라이언트 초기화 시 설정

```lua
local client = UnleashClient.New({
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

### 기본 피쳐 플래그 노출

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
local client = UnleashClient.New({
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
