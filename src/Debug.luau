local Debug = {}

local DEBUG_ENABLED = _G.MAILROOM_DEBUG or false

local function noop() end

local function logLevel(prefix, fn): any
    return setmetatable({}, {
        __call = if DEBUG_ENABLED then fn else noop,
        __tostring = function()
            return prefix
        end,
    })
end

local Debug = {
    debug = logLevel("[DBG]", print),
    info = logLevel("[INF]", print),
    warn = logLevel("[WRN]", warn),
    error = logLevel("[ERR]", warn),
    critical = logLevel("[CRT]", warn),
}

return Debug
