local Timer = require("framework.3rdparty.togglet.timer")
local Promise = require("framework.3rdparty.togglet.promise")

local Ticker = function()
    Timer.Update()
    Promise.Update()
end

return Ticker
