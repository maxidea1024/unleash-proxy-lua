// ----------------------------------------------------------------------------
// COPYRIGHT (C)2017 BY MOTIF CO., LTD. ALL RIGHTS RESERVED.
// ----------------------------------------------------------------------------

import type { Variant } from "unleash-client/lib/variant";
import { JSONValue } from "./types";

export default class ToggleProxy {
  private readonly featureName: string;
  private readonly variant: Variant;
  private readonly isDefined: boolean;

  constructor(
    featureName: string,
    isDefined: boolean,
    variant: Variant) {
    this.featureName = featureName;
    this.isDefined = isDefined;
    this.variant = variant;
  }

  /**
   * Returns the name of the feature toggle.
   * @returns The feature toggle name
   */
  getFeatureName(): string {
    return this.featureName
  }

  /**
   * Returns the name of the currently active variant.
   * @returns The variant name
   */
  getVariantName(): string {
    return this.variant.name;
  }

  /**
   * Checks if the feature toggle is enabled.
   * @param defaultValue Value to return if the toggle is not defined (defaults to false)
   * @returns true if the toggle is enabled, false otherwise
   * 
   * If the feature flag is not defined in the system, this method returns the provided
   * defaultValue instead of throwing an error, allowing for graceful fallbacks.
   */
  isEnabled(defaultValue: boolean = false): boolean {
    if (!this.isDefined) {
      return defaultValue;
    }

    return this.variant.feature_enabled;
  }

  /**
   * Returns the current variant object.
   * @returns The Variant object
   */
  getVariant(): Variant {
    return this.variant;
  }

  /**
   * Returns the boolean value of the feature toggle.
   * @param defaultValue Value to return if the toggle is not defined
   * @returns true if the toggle is enabled and the variant is enabled, false otherwise
   * 
   * When the feature flag is not defined in the system, this method returns the provided
   * defaultValue, allowing the application to continue with a predetermined fallback behavior.
   */
  boolVariation(defaultValue: boolean): boolean {
    if (!this.isDefined) {
      return defaultValue;
    }

    return this.variant.feature_enabled && this.variant.enabled;
  }

  /**
   * Returns the numeric value of the feature toggle.
   * @param defaultValue Value to return if the toggle is not defined or cannot be converted to a number
   * @returns The numeric value from the variant payload if available, otherwise the default value
   * 
   * If the feature flag is not defined or if its payload is not a valid number type,
   * this method returns the provided defaultValue. This ensures that the application
   * can continue to operate with a known fallback value without errors.
   */
  numberVariation(defaultValue: number): number {
    if (!this.isDefined) {
      return defaultValue;
    }

    if (this.variant.payload && this.variant.payload.type === 'number') {
      const value = Number.parseFloat(this.variant.payload.value);
      if (!Number.isNaN(value)) {
        return value;
      }
    }

    return defaultValue;
  }

  /**
   * Returns the string value of the feature toggle.
   * @param defaultValue Value to return if the toggle is not defined or is not a string type
   * @returns The string value from the variant payload if available, otherwise the default value
   * 
   * When the feature flag is not defined or if its payload is not a string type,
   * this method returns the provided defaultValue. This allows for safe access to
   * configuration values without having to check if the feature exists first.
   */
  stringVariation(defaultValue: string): string {
    if (!this.isDefined) {
      return defaultValue;
    }

    if (this.variant.payload && this.variant.payload.type === 'string') {
      return this.variant.payload.value;
    }

    return defaultValue;
  }

  /**
   * Returns the JSON value of the feature toggle.
   * @param defaultValue Value to return if the toggle is not defined or is not a JSON type
   * @returns The parsed JSON value from the variant payload if available, otherwise the default value
   * 
   * If the feature flag is not defined or if its payload is not a valid JSON type,
   * this method returns the provided defaultValue. This graceful fallback mechanism
   * allows the application to use complex configuration objects with default values
   * when the feature flag system is unavailable or misconfigured.
   */
  jsonVariation(defaultValue: JSONValue): JSONValue {
    if (!this.isDefined) {
      return defaultValue;
    }

    if (this.variant.payload && this.variant.payload.type === 'json') {
      return JSON.parse(this.variant.payload.value) as JSONValue;
    }

    return defaultValue;
  }
}
