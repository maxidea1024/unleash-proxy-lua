local ToggletClient = require("framework.3rdparty.togglet.togglet-client")
local ToggletClientBuilder = require("framework.3rdparty.togglet.togglet-client-builder")
local InMemoryStorageProvider = require("framework.3rdparty.togglet.storage-provider-inmemory")
local FileStorageProvider = require("framework.3rdparty.togglet.storage-provider-file")
local Events = require("framework.3rdparty.togglet.events")
local Logging = require("framework.3rdparty.togglet.logging")
local Util = require("framework.3rdparty.togglet.util")
local Timer = require("framework.3rdparty.togglet.timer")
local Promise = require("framework.3rdparty.togglet.promise")

local UpdateTogglet = function()
  Timer.Update()
  Promise.Update()
end

return {
  ToggletClient = ToggletClient,
  ToggletClientBuilder = ToggletClientBuilder,
  InMemoryStorageProvider = InMemoryStorageProvider,
  FileStorageProvider = FileStorageProvider,
  Events = Events,
  Logging = Logging,
  Util = Util,
  UpdateTogglet = UpdateTogglet,
}
