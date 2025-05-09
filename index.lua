local Client = require("framework.3rdparty.feature-flags.client")
local InMemoryStorageProvider = require("framework.3rdparty.feature-flags.storage-provider-inmemory")
local FileStorageProvider = require("framework.3rdparty.feature-flags.storage-provider-file")
local Events = require("framework.3rdparty.feature-flags.events")
local Logger = require("framework.3rdparty.feature-flags.logger")

return {
  Client = Client,
  InMemoryStorageProvider = InMemoryStorageProvider,
  FileStorageProvider = FileStorageProvider,
  Events = Events,
  Logger = Logger,
}
