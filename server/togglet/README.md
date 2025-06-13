# ToggletClient 사용 가이드

ToggletClient는 Unleash 기반의 Feature Toggle 시스템을 제공합니다. 이 가이드는 각 함수의 올바른 사용법과 주의사항을 설명합니다.

## 목차

1. [초기화 및 기본 설정](#1-초기화-및-기본-설정)
2. [Context 객체 사용](#2-context-객체-사용)
3. [기능 활성화 확인](#3-기능-활성화-확인)
4. [변형(Variant) 가져오기](#4-변형variant-가져오기)
5. [타입별 값 가져오기](#5-타입별-값-가져오기)
6. [ToggleProxy 객체 가져오기](#6-toggleproxy-객체-가져오기)
7. [주의사항](#7-주의사항)
8. [실제 사용 예시](#8-실제-사용-예시)
9. [Server-Side SDK와 Client-Side SDK의 차이점](#9-server-side-sdk와-client-side-sdk의-차이점)

## 1. 초기화 및 기본 설정

```typescript
// 클라이언트 생성
const togglet = new ToggletClient({
  apiUrl: 'https://unleash.example.com/api/',
  accessToken: 'your-token',
  environment: 'production',
  defaultContext: {
    properties: {
      appName: 'MyApp'
    }
  }
});

// 초기화 (비동기)
await togglet.init();

// 기본 Context 설정
togglet.setDefaultContext({
  userId: 'system',
  properties: {
    appName: 'MyApp',
    environment: 'production'
  }
});
```

## 2. Context 객체 사용

Context 객체는 Feature Toggle 평가에 사용되는 정보를 담고 있습니다. **모든 토글 관련 함수에서 context 매개변수는 필수입니다.**

```typescript
// 기본 Context 객체 예시
const userContext: Context = {
  userId: '12345',            // 사용자 ID
  sessionId: 'abc-123',       // 세션 ID
  remoteAddress: '127.0.0.1', // IP 주소
  properties: {               // 추가 속성
    country: 'KR',
    deviceType: 'mobile',
    appVersion: '2.1.0'
  }
};

// User 객체에서 Context 가져오기 예시
function getContextFromUser(user: User): Context {
  return user.getToggletContext();
}
```

## 3. 기능 활성화 확인

```typescript
// 기본 사용법
const isEnabled = togglet.isEnabled('feature-name', userContext);
if (isEnabled) {
  // 기능이 활성화된 경우의 로직
} else {
  // 기능이 비활성화된 경우의 로직
}

// 기본값 지정 (feature-name이 정의되지 않은 경우 false 반환)
const isEnabled = togglet.isEnabled('feature-name', userContext, false);
```

## 4. 변형(Variant) 가져오기

```typescript
// 변형 객체 가져오기
const variant = togglet.getVariant('feature-with-variants', userContext);
console.log(variant.name);    // 변형 이름
console.log(variant.enabled); // 활성화 여부
console.log(variant.payload); // 추가 데이터

// 변형 이름만 가져오기 (기본값 지정)
const variantName = togglet.variation('feature-with-variants', userContext, 'default');
switch (variantName) {
  case 'variant-a':
    // variant-a 처리 로직
    break;
  case 'variant-b':
    // variant-b 처리 로직
    break;
  default:
    // 기본 처리 로직
}
```

## 5. 타입별 값 가져오기

```typescript
// 불리언 값 가져오기
const boolValue = togglet.boolVariation('bool-feature', userContext, false);

// 숫자 값 가져오기
const numValue = togglet.numberVariation('num-feature', userContext, 0);

// 문자열 값 가져오기
const strValue = togglet.stringVariation('str-feature', userContext, 'default');

// JSON 값 가져오기
const jsonValue = togglet.jsonVariation('json-feature', userContext, { fallback: true });
```

## 6. ToggleProxy 객체 가져오기

```typescript
// ToggleProxy 객체 가져오기
const toggle = togglet.getToggle('feature-name', userContext);

// 토글 이름 가져오기
const featureName = toggle.getFeatureName();

// 활성화 여부 확인
if (toggle.isEnabled()) {
  // 기능이 활성화된 경우의 로직
}

// 변형 이름 가져오기
const variantName = toggle.getVariantName();

// 변형 객체 가져오기
const variant = toggle.getVariant();

// 타입별 값 가져오기
const boolValue = toggle.boolVariation(false);
const numValue = toggle.numberVariation(0);
const strValue = toggle.stringVariation('default');
const jsonValue = toggle.jsonVariation({ fallback: true });
```

## 7. 주의사항

### 7.1 Context 매개변수는 생략할 수 없습니다

```typescript
// 잘못된 사용법 - 컴파일 오류 발생
// togglet.isEnabled('feature-name');

// 올바른 사용법
togglet.isEnabled('feature-name', userContext);
```

### 7.2 defaultValue 매개변수는 생략할 수 없습니다

```typescript
// 잘못된 사용법 - 안전하지 않음
// const value = togglet.boolVariation('bool-feature', userContext);

// 올바른 사용법
const value = togglet.boolVariation('bool-feature', userContext, false);
```

### 7.3 Context 객체 재사용 시 주의

```typescript
const sharedContext = { userId: 'user-123', properties: { country: 'KR' } };

// 이 코드는 sharedContext를 수정합니다
sharedContext.properties.deviceType = 'mobile';

// 이후 호출에서는 수정된 context가 사용됩니다
togglet.isEnabled('another-feature', sharedContext);
```

### 7.4 성능 최적화

```typescript
// 비효율적인 방법 - 루프 내에서 매번 새 context 생성
for (const item of items) {
  const context = { userId, properties: { itemId: item } };
  if (togglet.isEnabled('process-item', context)) {
    // 처리 로직...
  }
}

// 효율적인 방법 - context 객체 재사용
const context = { userId, properties: {} };
for (const item of items) {
  context.properties.itemId = item;
  if (togglet.isEnabled('process-item', context)) {
    // 처리 로직...
  }
}
```

## 8. 실제 사용 예시

### 8.1 사용자 기반 기능 토글

```typescript
// 싱글톤 인스턴스 생성
const togglet = new ToggletClient({
  apiUrl: 'https://unleash.example.com/api/',
  accessToken: 'your-token',
  environment: 'production'
});

// 애플리케이션 시작 시 초기화
async function initializeTogglet() {
  await togglet.init();
  console.log('Feature toggle system initialized');
}

// 사용자별 기능 확인
function checkFeatureForUser(user: User, featureName: string): boolean {
  // User 객체에서 context 가져오기
  const context = user.getToggletContext();
  return togglet.isEnabled(featureName, context);
}

// 사용자별 설정값 가져오기
function getUserSetting(user: User, settingName: string, defaultValue: number): number {
  const context = user.getToggletContext();
  return togglet.numberVariation(settingName, context, defaultValue);
}

// 사용자 경험 분기 처리
function getUserExperience(user: User): string {
  const context = user.getToggletContext();
  return togglet.variation('user-experience', context, 'default');
}
```

### 8.2 A/B 테스트 구현

```typescript
// 사용자에게 표시할 UI 버전 결정
function determineUIVersion(user: User): string {
  const context = user.getToggletContext();
  return togglet.variation('ui-experiment', context, 'control');
}

// 사용자 요청 처리
async function handleUserRequest(user: User) {
  // UI 버전 결정
  const uiVersion = determineUIVersion(user);
  
  // 버전에 따른 처리
  switch (uiVersion) {
    case 'variant-a':
      renderNewUI();
      // 분석 이벤트 기록
      analytics.track('ui-experiment', { version: 'variant-a', userId: user.id });
      break;
    case 'variant-b':
      renderAlternativeUI();
      analytics.track('ui-experiment', { version: 'variant-b', userId: user.id });
      break;
    default:
      renderControlUI();
      analytics.track('ui-experiment', { version: 'control', userId: user.id });
  }
}
```

### 8.3 점진적 롤아웃

```typescript
// 새 기능의 점진적 롤아웃 확인
function checkGradualRollout(user: User, featureName: string): boolean {
  const context = user.getToggletContext();
  
  // userId를 기반으로 일관된 롤아웃 결정
  // Unleash 서버에서는 gradualRolloutUserId 전략을 사용
  return togglet.isEnabled(featureName, context, false);
}

// 새 기능 적용
function applyNewFeatures(user: User) {
  // 새 결제 시스템 점진적 롤아웃
  if (checkGradualRollout(user, 'new-payment-system')) {
    enableNewPaymentSystem();
  } else {
    useOldPaymentSystem();
  }
  
  // 새 알림 시스템 점진적 롤아웃
  if (checkGradualRollout(user, 'enhanced-notifications')) {
    enableEnhancedNotifications();
  }
}
```

## 9. Server-Side SDK와 Client-Side SDK의 차이점

ToggletClient는 서버 사이드 SDK로, Unleash의 클라이언트 사이드 SDK와는 몇 가지 중요한 차이점이 있습니다. 이러한 차이점을 이해하는 것은 Feature Toggle 시스템을 올바르게 구현하는 데 중요합니다.

### 9.1 아키텍처 차이

#### Server-Side SDK (ToggletClient)

- **직접 연결**: Unleash API 서버에 직접 연결하여 모든 토글 구성을 가져옵니다.
- **전체 토글 정보**: 모든 토글 정보와 전략을 로컬에 저장하고 평가합니다.
- **실시간 평가**: 요청 시점에 토글 상태를 실시간으로 평가합니다.
- **민감한 정보 접근**: 서버 측에서만 알아야 할 민감한 정보(예: 내부 전략 로직)에 접근할 수 있습니다.

```
[서버 애플리케이션] <---> [ToggletClient] <---> [Unleash API 서버]
                           |
                           v
                     [로컬 토글 저장소]
```

#### Client-Side SDK (브라우저용)

- **프록시 필요**: 보안상의 이유로 Unleash API 서버에 직접 연결하지 않고, 서버 측 프록시를 통해 연결합니다.
- **제한된 토글 정보**: 클라이언트에 필요한 토글 정보만 제공받습니다.
- **사전 평가**: 대부분의 경우 서버에서 사전 평가된 토글 상태를 받습니다.
- **민감한 정보 보호**: 클라이언트에는 민감한 전략 정보가 노출되지 않습니다.

```
[브라우저] <---> [클라이언트 SDK] <---> [프록시 API] <---> [서버 SDK] <---> [Unleash API 서버]
```

### 9.2 보안 고려사항

#### Server-Side SDK

- **API 토큰**: 서버 측 SDK는 Unleash API에 접근하기 위한 API 토큰을 사용합니다. 이 토큰은 민감한 정보이므로 서버 환경 변수나 안전한 구성 저장소에 보관해야 합니다.
- **전체 전략 접근**: 모든 전략 로직에 접근할 수 있으므로, 민감한 비즈니스 로직을 포함할 수 있습니다.

```typescript
// 서버 측 SDK 초기화 (API 토큰 사용)
const togglet = new ToggletClient({
  apiUrl: 'https://unleash.example.com/api/',
  accessToken: process.env.UNLEASH_API_TOKEN, // 환경 변수에서 토큰 가져오기
  environment: 'production'
});
```

#### Client-Side SDK

- **클라이언트 키**: 클라이언트 측 SDK는 API 토큰 대신 제한된 권한을 가진 클라이언트 키를 사용합니다.
- **제한된 접근**: 클라이언트에는 필요한 토글 정보만 제공되며, 전략 로직은 노출되지 않습니다.
- **프록시 필요**: 보안을 위해 서버 측 프록시 API를 통해 토글 정보를 가져옵니다.

```typescript
// 클라이언트 측 SDK 초기화 (프록시 API 사용)
const unleashClient = new UnleashClient({
  url: '/api/feature-toggles', // 서버 측 프록시 API 경로
  clientKey: 'client-side-key', // 제한된 권한의 클라이언트 키
  appName: 'web-app'
});
```

### 9.3 성능 및 네트워크 고려사항

#### Server-Side SDK

- **폴링 메커니즘**: 서버 측 SDK는 주기적으로 Unleash API를 폴링하여 토글 구성 업데이트를 가져옵니다.
- **로컬 캐싱**: 토글 구성을 로컬에 캐싱하여 API 호출 없이 빠르게 평가할 수 있습니다.
- **부트스트래핑**: 서버 재시작 시 이전 상태를 빠르게 복원하기 위해 부트스트래핑을 지원합니다.

```typescript
// 서버 측 SDK 초기화 (폴링 간격 설정)
const togglet = new ToggletClient({
  apiUrl: 'https://unleash.example.com/api/',
  accessToken: 'your-token',
  refreshInterval: 30_000, // 30초마다 업데이트 확인
});
```

#### Client-Side SDK

- **초기 로드**: 페이지 로드 시 필요한 토글 정보를 한 번에 가져옵니다.
- **실시간 업데이트**: 일부 구현에서는 WebSocket을 통한 실시간 업데이트를 지원합니다.
- **네트워크 최적화**: 클라이언트에 필요한 최소한의 정보만 전송하여 네트워크 부하를 줄입니다.

```typescript
// 클라이언트 측 SDK 초기화 (실시간 업데이트 설정)
const unleashClient = new UnleashClient({
  url: '/api/feature-toggles',
  clientKey: 'client-side-key',
  appName: 'web-app',
  refreshInterval: 60, // 60초마다 업데이트 확인
  disableRefresh: false, // 자동 업데이트 활성화
});
```

### 9.4 Context 처리 차이점

#### Server-Side SDK

- **풍부한 Context**: 서버 측에서는 사용자 ID, 세션, IP 주소, 요청 정보 등 다양한 Context 정보를 활용할 수 있습니다.
- **Context 병합**: `defaultContext`와 요청별 Context를 병합하여 사용합니다.
- **실시간 평가**: 각 요청마다 최신 Context로 토글을 평가합니다.

```typescript
// 서버 측에서 요청별 Context 생성
function handleRequest(req, res) {
  const context = {
    userId: req.user?.id,
    sessionId: req.sessionID,
    remoteAddress: req.ip,
    properties: {
      userAgent: req.headers['user-agent'],
      country: req.geoip?.country
    }
  };
  
  if (togglet.isEnabled('new-feature', context)) {
    // 기능 활성화 로직
  }
}
```

#### Client-Side SDK

- **제한된 Context**: 클라이언트 측에서는 브라우저 환경에서 얻을 수 있는 정보로 Context가 제한됩니다.
- **사용자 식별**: 주로 사용자 ID, 세션 ID 등 제한된 식별자를 사용합니다.
- **프라이버시 고려**: 사용자 정보 수집 시 프라이버시 규정(GDPR, CCPA 등)을 고려해야 합니다.

```typescript
// 클라이언트 측에서 Context 생성
const clientContext = {
  userId: currentUser.id,
  sessionId: getSessionId(),
  properties: {
    deviceType: getDeviceType(),
    appVersion: APP_VERSION,
    language: navigator.language
  }
};

if (unleashClient.isEnabled('new-ui', clientContext)) {
  // 새 UI 표시
}
```

### 9.5 구현 패턴 차이

#### Server-Side SDK 패턴

1. **백엔드 전용 기능**: 데이터베이스 스키마 변경, API 엔드포인트, 백그라운드 작업 등
2. **사용자별 기능 제어**: 사용자 요청 처리 시 서버에서 기능 활성화 여부 결정
3. **API 응답 변형**: 응답 데이터에 기능 활성화 정보 포함

```typescript
// 서버 측 API 응답에 기능 정보 포함
app.get('/api/user-settings', (req, res) => {
  const context = getUserContext(req);
  
  res.json({
    settings: getUserSettings(req.user),
    features: {
      newDashboard: togglet.isEnabled('new-dashboard', context),
      betaFeatures: togglet.isEnabled('beta-features', context),
      notificationSystem: togglet.variation('notification-system', context, 'legacy')
    }
  });
});
```
