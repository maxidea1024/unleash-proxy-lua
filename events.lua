--[[
  Events is a table that defines a set of constants representing various event types
  used in the application. Each key in the table corresponds to a specific event type,
  and its value is a string describing the event.

  Keys and their meanings:
  - INIT: Represents the "init" event, triggered when initialization is complete.
  - ERROR: Represents the "error" event, triggered when an error occurs.
  - READY: Represents the "ready" event, triggered when the system is ready.
  - UPDATE: Represents the "update" event, triggered when an update occurs.
  - IMPRESSION: Represents the "impression" event, triggered when an impression is recorded.
  - SENT: Represents the "sent" event, triggered when data is successfully sent.
  - RECOVERED: Represents the "recovered" event, triggered when a recovery operation is completed.

  This table is returned as a module for use in other parts of the application.
]]
local Events = {
  INIT = "init",
  ERROR = "error",
  READY = "ready",
  UPDATE = "update",
  IMPRESSION = "impression",
  SENT = "sent",
  RECOVERED = "recovered",
}

return Events
