local Debug = {}

local DEBUG_ENABLED = true

local function format(fn: any, msg: string)
    return {fn, msg}
end

local LOG_LEVELS = {
    critical = format(warn, "[CRT] !"),
    error = format(warn, "[ERR] !"),
    warn = format(warn, "[WRN]"),
    info = format(print, "[INF]"),
    debug = format(print, "[DBG]"),
}

local noop = function() end

function Debug:__index(key: string)
    if not DEBUG_ENABLED then return noop end
    local logFn = LOG_LEVELS[key]
    if logFn then
        self.prefix = logFn[2]
        return logFn[1]
    end

    error("Invalid log level: " .. key)
end

function Debug:__tostring()
    return self.prefix or ""
end

return setmetatable({}, Debug) :: any