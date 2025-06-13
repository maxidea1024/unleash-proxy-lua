// ----------------------------------------------------------------------------
// COPYRIGHT (C)2017 BY MOTIF CO., LTD. ALL RIGHTS RESERVED.
// ----------------------------------------------------------------------------

/* 주의사항:

1. 각 함수 인자의 context는 생략할 수 없습니다.

client.isEnabled('my-feature', {});                  <-- setDefaultContext() 함수를 통해서 설정된 기본 context가 사용됩니다.
client.isEnabled('my-feature', userContext);         <-- defaultContext + userContext가 사용됩니다.

이런식으로 사용해야합니다. context 인자를 생략해도 되도록 허용할수 있지만, 그렇게 되면
실수로 context를 넣지 않아서 발생하는 문제들을 피할수 있습니다.

2. 다음 함수의 defaultValue는 생략할 수 없습니다.

  boolVariation(featureName: string, context: Context, defaultValue: boolean)
  numberVariation(featureName: string, context: Context, defaultValue: number)
  stringVariation(featureName: string, context: Context, defaultValue: string)
  jsonVariation(featureName: string, context: Context, defaultValue: JSONValue)
  variation(featureName: string, context: Context, defaultVariantName: string)

  위 함수들이 반환하는 값들의 Unleash 서버에 설정된 내용 혹은 평가 결과에 따라서
  원하는 값의 형태가 아닐수 있습니다.

  이러한 경우에도 최소한 안전한 값으로 처리하기 위해 defaultValue를 반드시
  제공해야합니다. 이렇게 처리하게 되면 모호함을 줄일 수 있습니다.
 */
import { Context, initialize, type Unleash } from 'unleash-client';
import { defaultVariant, type Variant } from 'unleash-client/lib/variant';
import ToggleProxy from './toggleProxy';
import type { JSONValue } from './types';
import { v4 as uuidv4 } from 'uuid';
import mlog from '../mlog';

export type ToggletClientConfig = {
  apiUrl: string;
  accessToken: string;
  environment: string;
  defaultContext?: Context;
  appName?: string;
  refreshInterval?: number;
};

export default class ToggletClient {
  private unleash: Unleash | null = null;
  private defaultContext: Context;
  private readonly appName: string;
  private readonly refreshInterval: number;
  private readonly apiUrl: string;
  private readonly accessToken: string;
  // 이건 필요없지 않을까? accesstoken에서 이미 환경이 결정되기때문이다.
  // private readonly environment: string;

  constructor(config?: ToggletClientConfig) {
    this.defaultContext = config?.defaultContext ?? {};
    this.appName = config?.appName ?? process.name;
    this.refreshInterval = config?.refreshInterval ?? 5_000;
    this.apiUrl = config?.apiUrl ?? 'https://us.app.unleash-hosted.com/usii0012/api/';
    this.accessToken = config?.accessToken ?? '*:development.8d662424920812bad929a7f778d607a00779c75a2e8a25575541d5f3';
    // this.environment = config?.environment ?? 'development';
  }

  private mergeWithDefaultContext(context?: Context): Context {
    let result: Context = { ...this.defaultContext, ...context };

    // inject currentTime if not provided
    if (!result.currentTime) {
      result.currentTime = new Date();
    }

    console.log('toggletContext:', result);

    return result;
  }

  /**
   * Initializes the feature toggle client by connecting to the Unleash server.
   * 
   * This method sets up the connection to the Unleash server using environment variables
   * or default values for API URL and access token. It also configures event handlers
   * for error and change events.
   */
  async init(): Promise<void> {
    this.unleash = initialize({
      url: this.apiUrl,
      appName: this.appName,
      instanceId: uuidv4(),
      refreshInterval: this.refreshInterval,
      customHeaders: {
        Authorization: `Bearer ${this.accessToken}`,
      },

      // FIXME 현재 streaming 모드는 제대로 동작하지 않음.
      // (서버 사이드에서 문제가 있는것 같음.)
      // experimentalMode: {
      //   type: 'streaming',
      // }
    });

    this.unleash.on('error', (error) => {
      mlog.error('[TOGGLET] Error:', error);
    });

    this.unleash.on('changed', (data) => {
      // mlog.info(`[TOGGLET] Feature flagging changed: ${JSON.stringify(data)}`);
      mlog.info(`[TOGGLET] Feature flags changed at ${new Date().toISOString()}`);
    });

    await new Promise((resolve) => {
      this.unleash.on('ready', resolve);
    });
  }

  /**
   * Destroys the feature toggle client, cleaning up resources.
   * 
   * This method should be called when the application is shutting down to properly
   * release resources and close connections to the Unleash server.
   */
  destroy() {
    if (this.unleash) {
      this.unleash.destroy();
      this.unleash = null;
    }
  }

  /**
   * Sets the default context for feature toggle evaluations.
   * 
   * @param defaultContext The default context to use for feature toggle evaluations
   * 
   * The default context is merged with any context provided in individual toggle
   * evaluation calls, with the provided context taking precedence over defaults.
   */
  setDefaultContext(defaultContext: Context): void {
    this.defaultContext = defaultContext;
  }

  /**
   * Checks if a feature toggle is enabled.
   * 
   * @param featureName Name of the feature toggle to check
   * @param context Additional context for toggle evaluation
   * @param defaultValue Value to return if the toggle is not defined (defaults to false)
   * @returns true if the toggle is enabled, false otherwise
   * 
   * If the feature flag is not defined in the system, this method returns the provided
   * defaultValue instead of throwing an error, allowing for graceful fallbacks.
   */
  isEnabled(featureName: string, context: Context, defaultValue: boolean = false): boolean {
    const definition = this.unleash.getFeatureToggleDefinition(featureName);
    if (definition === undefined) {
      return defaultValue;
    }

    const mergedContext = this.mergeWithDefaultContext(context);
    return this.unleash.isEnabled(featureName, mergedContext);
  }

  /**
   * Gets the variant for a feature toggle.
   * 
   * @param featureName Name of the feature toggle
   * @param context Additional context for toggle evaluation
   * @returns The variant for the feature toggle
   * 
   * This method always returns a variant object, even if the feature toggle
   * is not defined or disabled.
   */
  getVariant(featureName: string, context: Context): Variant {
    const mergedContext = this.mergeWithDefaultContext(context);
    return this.unleash.getVariant(featureName, mergedContext, defaultVariant);
  }

  /**
   * Gets a ToggleProxy for a feature toggle.
   * 
   * @param featureName Name of the feature toggle
   * @param context Additional context for toggle evaluation
   * @returns A ToggleProxy for the feature toggle
   * 
   * The ToggleProxy provides a convenient interface for accessing toggle values
   * with type safety and fallback values.
   */
  getToggle(featureName: string, context: Context): ToggleProxy {
    const definition = this.unleash.getFeatureToggleDefinition(featureName);
    const variant = this.getVariant(featureName, context);
    return new ToggleProxy(featureName, definition !== undefined, variant);
  }

  /**
   * Gets the boolean value of a feature toggle.
   * 
   * @param featureName Name of the feature toggle
   * @param context Additional context for toggle evaluation
   * @param defaultValue Value to return if the toggle is not defined
   * @returns true if the toggle is enabled and the variant is enabled, false otherwise
   * 
   * When the feature flag is not defined in the system, this method returns the provided
   * defaultValue, allowing the application to continue with a predetermined fallback behavior.
   */
  boolVariation(featureName: string, context: Context, defaultValue: boolean): boolean {
    const toggle = this.getToggle(featureName, context);
    return toggle.boolVariation(defaultValue);
  }

  /**
   * Gets the numeric value of a feature toggle.
   * 
   * @param featureName Name of the feature toggle
   * @param context Additional context for toggle evaluation
   * @param defaultValue Value to return if the toggle is not defined or cannot be converted to a number
   * @returns The numeric value from the variant payload if available, otherwise the default value
   * 
   * If the feature flag is not defined or if its payload is not a valid number type,
   * this method returns the provided defaultValue. This ensures that the application
   * can continue to operate with a known fallback value without errors.
   */
  numberVariation(featureName: string, context: Context, defaultValue: number): number {
    const toggle = this.getToggle(featureName, context);
    return toggle.numberVariation(defaultValue);
  }

  /**
   * Gets the string value of a feature toggle.
   * 
   * @param featureName Name of the feature toggle
   * @param context Additional context for toggle evaluation
   * @param defaultValue Value to return if the toggle is not defined or is not a string type
   * @returns The string value from the variant payload if available, otherwise the default value
   * 
   * When the feature flag is not defined or if its payload is not a string type,
   * this method returns the provided defaultValue. This allows for safe access to
   * configuration values without having to check if the feature exists first.
   */
  stringVariation(featureName: string, context: Context, defaultValue: string): string {
    const toggle = this.getToggle(featureName, context);
    return toggle.stringVariation(defaultValue);
  }

  /**
   * Gets the JSON value of a feature toggle.
   * 
   * @param featureName Name of the feature toggle
   * @param context Additional context for toggle evaluation
   * @param defaultValue Value to return if the toggle is not defined or is not a JSON type
   * @returns The parsed JSON value from the variant payload if available, otherwise the default value
   * 
   * If the feature flag is not defined or if its payload is not a valid JSON type,
   * this method returns the provided defaultValue. This graceful fallback mechanism
   * allows the application to use complex configuration objects with default values
   * when the feature flag system is unavailable or misconfigured.
   */
  jsonVariation(featureName: string, context: Context, defaultValue: JSONValue): JSONValue {
    const toggle = this.getToggle(featureName, context);
    return toggle.jsonVariation(defaultValue);
  }

  /**
   * Gets the variant name of a feature toggle.
   * 
   * @param featureName Name of the feature toggle
   * @param context Additional context for toggle evaluation
   * @param defaultVariantName Default variant name to return if the toggle is not defined or disabled
   * @returns The variant name if the toggle is enabled, otherwise the default variant name
   * 
   * This method is useful for selecting between different implementations or configurations
   * based on the active variant of a feature toggle. If the feature flag is not defined or
   * if it's disabled, the method returns the provided defaultVariantName.
   */
  variation(featureName: string, context: Context, defaultVariantName: string): string {
    const definition = this.unleash.getFeatureToggleDefinition(featureName);
    if (definition === undefined) {
      return defaultVariantName;
    }

    const variant = this.getVariant(featureName, context);
    if (variant.feature_enabled && variant.enabled) {
      return variant.name;
    }

    return defaultVariantName;
  }
}
