local Util = require("framework.3rdparty.togglet.util")

local ErrorHelper = {}

-- HTTP Error Solutions
function ErrorHelper.GetHttpErrorSolution(statusCode, context)
  context = context or "general"

  if statusCode == 400 then
    return "Check request payload format and ensure all required fields are present and valid."
  elseif statusCode == 401 then
    return "Verify API key/client key is correct and has not expired. Check authentication configuration."
  elseif statusCode == 403 then
    if context == "metrics" then
      return "Ensure API key has sufficient permissions to send metrics. Contact administrator if needed."
    else
      return "Ensure API key has sufficient permissions to access feature flags. Contact administrator if needed."
    end
  elseif statusCode == 404 then
    if context == "metrics" then
      return "Verify the metrics endpoint URL is correct. Check if the service is properly configured."
    else
      return "Verify the feature flags endpoint URL is correct. Check if the service is properly configured."
    end
  elseif statusCode == 429 then
    return "Reduce request frequency or implement exponential backoff. Check rate limiting configuration."
  elseif statusCode >= 500 and statusCode < 600 then
    return "Server-side issue detected. Wait for automatic retry or contact service provider if issue persists."
  else
    return "Check network connectivity and server status. Review request configuration and retry."
  end
end

-- HTTP Error Troubleshooting Steps
function ErrorHelper.GetHttpErrorTroubleshooting(statusCode, context)
  context = context or "general"

  local commonSteps = {
    "1. Check network connectivity and DNS resolution",
    "2. Verify service endpoint is accessible",
    "3. Review client configuration settings"
  }

  if statusCode == 400 then
    if context == "metrics" then
      return Util.MergeArrays(commonSteps, {
        "4. Validate JSON payload structure and data types",
        "5. Check for missing or invalid required fields",
        "6. Ensure Content-Type header is set correctly"
      })
    else
      return Util.MergeArrays(commonSteps, {
        "4. Validate request payload structure and data types",
        "5. Check for missing or invalid required fields",
        "6. Ensure Content-Type header is set correctly"
      })
    end
  elseif statusCode == 401 then
    return Util.MergeArrays(commonSteps, {
      "4. Verify clientKey is correctly configured",
      "5. Check if API key has expired or been revoked",
      "6. Ensure Authorization header format is correct"
    })
  elseif statusCode == 403 then
    if context == "metrics" then
      return Util.MergeArrays(commonSteps, {
        "4. Verify API key permissions and scope",
        "5. Check if metrics reporting is enabled for your account",
        "6. Contact administrator to review access rights"
      })
    else
      return Util.MergeArrays(commonSteps, {
        "4. Verify API key permissions and scope",
        "5. Check if feature flags access is enabled for your account",
        "6. Contact administrator to review access rights"
      })
    end
  elseif statusCode == 404 then
    if context == "metrics" then
      return Util.MergeArrays(commonSteps, {
        "4. Verify the base URL and metrics endpoint path",
        "5. Check if the service version supports metrics API",
        "6. Ensure the service is properly deployed and running"
      })
    else
      return Util.MergeArrays(commonSteps, {
        "4. Verify the base URL and feature flags endpoint path",
        "5. Check if the service version supports feature flags API",
        "6. Ensure the service is properly deployed and running"
      })
    end
  elseif statusCode == 429 then
    if context == "metrics" then
      return Util.MergeArrays(commonSteps, {
        "4. Implement exponential backoff strategy",
        "5. Review and adjust metricsInterval configuration",
        "6. Check if multiple clients are sending from same source"
      })
    else
      return Util.MergeArrays(commonSteps, {
        "4. Implement exponential backoff strategy",
        "5. Review and adjust refreshInterval configuration",
        "6. Check if multiple clients are sending from same source"
      })
    end
  elseif statusCode >= 500 and statusCode < 600 then
    return Util.MergeArrays(commonSteps, {
      "4. Wait for automatic retry with exponential backoff",
      "5. Check service status and health endpoints",
      "6. Contact service provider if issue persists beyond expected timeframe"
    })
  else
    return Util.MergeArrays(commonSteps, {
      "4. Review complete request/response cycle",
      "5. Enable debug logging for detailed information",
      "6. Check for any middleware or proxy interference"
    })
  end
end

-- JSON Error Solutions and Troubleshooting
function ErrorHelper.GetJsonEncodingErrorDetail(errorMessage, dataType)
  dataType = dataType or "data"

  return {
    prevention = "Ensure " ..
    dataType ..
    " contains only JSON-serializable data types (string, number, boolean, table). Avoid functions, userdata, or circular references.",
    solution = "Check " ..
    dataType ..
    " structure and remove any non-serializable values. Consider using Util.DeepClone() to sanitize data before encoding.",
    troubleshooting = {
      "1. Verify all " .. dataType .. " values are basic Lua types",
      "2. Check for circular references in nested tables",
      "3. Ensure no functions or userdata are included in the " .. dataType,
      "4. Use Json.encode() with error handling in development to identify problematic fields",
      "5. Consider using Util.DeepClone() to sanitize " .. dataType .. " before encoding"
    }
  }
end

function ErrorHelper.GetJsonDecodingErrorDetail(errorType)
  errorType = errorType or "general"

  local baseDetail = {
    prevention = "Ensure server returns valid JSON response format.",
    solution = "Check server response format and verify API endpoint is functioning correctly."
  }

  if errorType == "exception" then
    baseDetail.prevention = "Ensure server returns valid JSON response format and handle malformed JSON gracefully."
    baseDetail.solution =
    "Check server response format, verify API endpoint is functioning correctly, and ensure JSON parsing is robust."
    baseDetail.troubleshooting = {
      "1. Verify server is returning valid JSON content",
      "2. Check Content-Type header is set to application/json",
      "3. Ensure response body is not truncated or corrupted",
      "4. Test API endpoint manually to verify JSON format",
      "5. Check for any middleware or proxy interference",
      "6. Verify JSON structure matches expected schema",
      "7. Check for special characters or encoding issues in response"
    }
  elseif errorType == "nil_result" then
    baseDetail.troubleshooting = {
      "1. Verify server is returning valid JSON content",
      "2. Check Content-Type header is set to application/json",
      "3. Ensure response body is not truncated or corrupted",
      "4. Test API endpoint manually to verify JSON format",
      "5. Check for any middleware or proxy interference",
      "6. Verify JSON syntax is correct (no trailing commas, proper quotes, etc.)"
    }
  else
    baseDetail.troubleshooting = {
      "1. Verify server is returning valid JSON content",
      "2. Check Content-Type header is set to application/json",
      "3. Ensure response body is not truncated or corrupted",
      "4. Test API endpoint manually to verify JSON format",
      "5. Check for any middleware or proxy interference"
    }
  end

  return baseDetail
end

-- Common HTTP Error Detail Builder
function ErrorHelper.BuildHttpErrorDetail(url, statusCode, options)
  options = options or {}

  local detail = {
    url = url,
    statusCode = statusCode,
    prevention = "Ensure stable network connection, valid API endpoint, and correct authentication credentials.",
    solution = ErrorHelper.GetHttpErrorSolution(statusCode, options.context),
    troubleshooting = ErrorHelper.GetHttpErrorTroubleshooting(statusCode, options.context)
  }

  -- Add optional fields
  if options.responseBody then
    detail.responseBodyPreview = string.sub(options.responseBody, 1, options.bodyPreviewLength or 256)
  end

  if options.method then
    detail.method = options.method
  end

  if options.headers then
    detail.headers = options.headers
  end

  if options.retryInfo then
    detail.retryInfo = options.retryInfo
  end

  if options.nextFetchDelay then
    detail.nextFetchDelay = options.nextFetchDelay
  end

  if options.failures then
    detail.failures = options.failures
  end

  return detail
end

-- Utility function to get table keys for debugging
function ErrorHelper.GetTableKeys(tbl)
  if type(tbl) ~= "table" then
    return {}
  end

  local keys = {}
  for key, _ in pairs(tbl) do
    table.insert(keys, tostring(key))
  end
  return keys
end

return ErrorHelper
