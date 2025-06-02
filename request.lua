local Promise = require("framework.3rdparty.togglet.promise")

local function buildHeaders(options)
  local headers = {}

  if options.appName then
    headers["unleash-appname"] = options.appName
    headers["User-Agent"] = options.appName
  end

  if options.instanceId then
    headers["unleash-instanceid"] = options.instanceId
  end

  if options.etag then
    headers["If-None-Match"] = options.etag
  end

  if options.contentType then
    headers["Content-Type"] = options.contentType
  end

  if options.specVersionSupported then
    headers["unleash-client-spec"] = options.specVersionSupported
  end

  if options.customHeaders then
    for name, value in pairs(options.customHeaders) do
      if value then
        headers[name] = value
      end
    end
  end

  return headers
end

local function post(options)
  local promise = Promise.New()
  return promise
end

local function get(options)
  local promise = Promise.New()

  local headers = options.headers or {}
  local url = options.url
  local timeout = options.timeout or 10
  local method = options.method or "GET"
  local request = options.request

  -- retry

  request(url, method, headers, nil, function(response)
    promise:Resolve(response)
  end,
  timeout)

  return promise
end

return {
  post = post,
  get = get
}
