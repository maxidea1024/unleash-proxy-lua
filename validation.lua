local Validation = {}

-- Validates that a value is not nil
-- @param value - The value to check
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
function Validation.RequireValue(value, paramName, functionName)
  if value == nil then
    error(string.format("`%s` is required in `%s`", paramName, functionName))
  end
  return value
end

-- Validates that a value is a string and not empty
-- @param value - The value to check
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
-- @param allowEmpty - (optional) If true, allows empty strings
function Validation.RequireString(value, paramName, functionName, allowEmpty)
  if type(value) ~= "string" then
    error(string.format("`%s` must be a string in `%s`, got %s",
      paramName, functionName, type(value)))
  end

  if not allowEmpty and #value == 0 then
    error(string.format("`%s` cannot be empty in `%s`", paramName, functionName))
  end

  return value
end

-- Validates that a value is a valid name (string with specific format)
-- @param value - The value to check
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
function Validation.RequireName(value, paramName, functionName)
  if type(value) ~= "string" then
    error(string.format("`%s` must be a string in `%s`, got %s",
      paramName, functionName, type(value)))
  end

  if #value == 0 then
    error(string.format("`%s` cannot be empty in `%s`", paramName, functionName))
  end
  
  -- 이름에 허용되지 않는 특수 문자 체크
  --local invalidChars = value:match("[^%w%.%-%_]")
  --if invalidChars then
  --  error(string.format("`%s` contains invalid characters in `%s`. Only alphanumeric characters, dots, hyphens, and underscores are allowed.",
  --    paramName, functionName))
  --end

  return value
end

-- Validates that a value is a table
-- @param value - The value to check
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
function Validation.RequireTable(value, paramName, functionName)
  if type(value) ~= "table" then
    error(string.format("`%s` must be a table in `%s`, got `%s`",
      paramName, functionName, type(value)))
  end

  return value
end

-- Validates that a value is a function
-- @param value - The value to check
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
function Validation.RequireFunction(value, paramName, functionName)
  if type(value) ~= "function" then
    error(string.format("`%s` must be a function in `%s`, got `%s`",
      paramName, functionName, type(value)))
  end

  return value
end

-- Validates that a value is a number
-- @param value - The value to check
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
-- @param min - (optional) Minimum allowed value
-- @param max - (optional) Maximum allowed value
function Validation.RequireNumber(value, paramName, functionName, min, max)
  if type(value) ~= "number" then
    error(string.format("`%s` must be a number in `%s`, got `%s`",
      paramName, functionName, type(value)))
  end

  if min ~= nil and value < min then
    error(string.format("`%s` must be >= `%s` in `%s`", paramName, min, functionName))
  end

  if max ~= nil and value > max then
    error(string.format("`%s` must be <= `%s` in `%s`", paramName, max, functionName))
  end

  return value
end

-- Validates that a value is a boolean
-- @param value - The value to check
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
function Validation.RequireBoolean(value, paramName, functionName)
  if type(value) ~= "boolean" then
    error(string.format("`%s` must be a boolean in `%s`, got `%s`",
      paramName, functionName, type(value)))
  end

  return value
end

-- Validates that a value is one of the allowed values
-- @param value - The value to check
-- @param allowedValues - Table of allowed values
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
function Validation.RequireOneOf(value, allowedValues, paramName, functionName)
  for _, allowedValue in ipairs(allowedValues) do
    if value == allowedValue then
      return value
    end
  end

  error(string.format("`%s` must be one of [%s] in `%s`",
    paramName, table.concat(allowedValues, ", "), functionName))
end

-- Validates that a table has a required field
-- @param tbl - The table to check
-- @param fieldName - The required field name
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
function Validation.RequireField(tbl, fieldName, paramName, functionName)
  Validation.RequireTable(tbl, paramName, functionName)

  local fieldValue = tbl[fieldName]

  if fieldValue == nil then
    error(string.format("`%s.%s` is required in `%s`", paramName, fieldName, functionName))
  end

  return fieldValue
end

-- Validates that a field in a table is of a specific type
-- @param tbl - The table to check
-- @param fieldName - The field name to check
-- @param expectedType - The expected type
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
-- @param required - (optional) If true, field must exist
function Validation.ValidateFieldType(tbl, fieldName, expectedType, paramName, functionName, required)
  Validation.RequireTable(tbl, paramName, functionName)

  local fieldValue = tbl[fieldName]

  if fieldValue == nil then
    if required then
      error(string.format("`%s.%s` is required in `%s`", paramName, fieldName, functionName))
    end
    return nil
  end

  if type(fieldValue) ~= expectedType then
    error(string.format("`%s.%s` must be a `%s` in `%s`, got `%s`",
      paramName, fieldName, expectedType, functionName, type(fieldValue)))
  end

  return fieldValue
end

-- Validates that a value is an instance of a specific class
-- @param value - The value to check
-- @param class - The expected class (metatable)
-- @param paramName - The parameter name for error message
-- @param functionName - The function name for error context
function Validation.RequireInstance(value, class, paramName, functionName)
  if type(value) ~= "table" then
    error(string.format("`%s` must be a table in `%s`, got `%s`",
      paramName, functionName, type(value)))
  end

  local mt = getmetatable(value)
  if mt ~= class then
    local className = "unknown"
    if type(class) == "table" and class.__name then
      className = class.__name
    elseif type(class) == "string" then
      className = class
    end

    error(string.format("`%s` must be an instance of `%s` in `%s`",
      paramName, className, functionName))
  end

  return value
end

return Validation
