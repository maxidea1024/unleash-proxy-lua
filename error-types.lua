--[[
  ErrorTypes is a table that defines a set of constants representing various error types
  used in the feature flags client. Each key in the table corresponds to a specific error type,
  and its value is a string describing the error type.

  Keys and their meanings:
  - INVALID_ARGUMENT: Represents invalid argument errors, triggered when required parameters are missing or invalid.
  - STATIC_FIELD_UPDATE_ATTEMPT: Represents attempts to update static context fields that cannot be changed.
  - AUTHENTICATION_ERROR: Represents authentication errors, triggered when API key is invalid or missing.
  - AUTHORIZATION_ERROR: Represents authorization errors, triggered when access is denied due to insufficient permissions.
  - NOT_FOUND_ERROR: Represents resource not found errors, triggered when requested resource doesn't exist.
  - RATE_LIMIT_ERROR: Represents rate limiting errors, triggered when API rate limits are exceeded.
  - SERVER_ERROR: Represents server-side errors, triggered when the server encounters internal issues.
  - UNKNOWN_ERROR: Represents unknown or unclassified errors.
  - CONFIGURATION_ERROR: Represents configuration errors, triggered when client configuration is invalid.
  - JSON_ERROR: Represents JSON parsing errors, triggered when response body cannot be parsed as JSON.
  - HTTP_ERROR: Represents HTTP request errors, triggered when HTTP requests fail.
  - CALLBACK_ERROR: Represents callback execution errors, triggered when user-provided callbacks throw exceptions.
  - EVENT_EMITTER_CALLBACK_ERROR: Represents event emitter callback errors, triggered when event listeners throw exceptions.

  This table is returned as a module for use in other parts of the application.
]]
local ErrorTypes = {
  INVALID_ARGUMENT = "InvalidArgument",
  STATIC_FIELD_UPDATE_ATTEMPT = "StaticFieldUpdateAttempt",
  AUTHENTICATION_ERROR = "AuthenticationError",
  AUTHORIZATION_ERROR = "AuthorizationError",
  NOT_FOUND_ERROR = "NotFoundError",
  RATE_LIMIT_ERROR = "RateLimitError",
  SERVER_ERROR = "ServerError",
  UNKNOWN_ERROR = "UnknownError",
  CONFIGURATION_ERROR = "ConfigurationError",
  JSON_ERROR = "JsonError",
  HTTP_ERROR = "HttpError",
  CALLBACK_ERROR = "CallbackError",
  EVENT_EMITTER_CALLBACK_ERROR = "EventEmitterCallbackError",
  EVENT_EMITTER_WEAK_CALLBACK_ERROR = "EventEmitterWeakCallbackError",
  EVENT_EMITTER_ONCE_CALLBACK_ERROR = "EventEmitterOnceCallbackError",
}

return ErrorTypes
