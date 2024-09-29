local Promise = require(script.Parent.Parent.Parent.Promise)
local DataStoreUtils = {}

local NO_CACHE_OPTIONS = Instance.new("DataStoreGetOptions")
NO_CACHE_OPTIONS.UseCache = false

local gameClosed = false
game:BindToClose(function()
    gameClosed = true
end)

--[=[
    @interface DataStoreAPIOptions
    @within Document
    @field maxRetries number
    @field baseDelay number
    @field delayMultiplier number
    @field continueOnClose boolean
    Can be used to set DataStore API options. Set `options.dataStoreAPI` to 
    this to use.
]=]

local function exponentialBackoff(fn, options)
    options = options or {}
    local maxRetries = options.maxRetries or 5
    local baseDelay = options.baseDelay or 1
    local delayMultiplier = options.delayMultiplier or 2
    local continueOnClose = options.continueOnClose or false

    local function try(tryNumber)
        if not continueOnClose and gameClosed then
            return Promise.reject("Game is closing")
        end

        return Promise.new(function(resolve, reject, onCancel)
            if tryNumber == 0 then
                onCancel(function()
                    warn("Do not cancel data store operations. This is an unsafe operation.")
                end)
            end

            local result = table.pack(pcall(fn))
            if result[1] then
                resolve(select(2, table.unpack(result)))
            elseif tryNumber >= maxRetries or (not continueOnClose and gameClosed) then
                reject(result[2])
            else
                local promise = Promise.delay(
                    baseDelay * (delayMultiplier ^ tryNumber)
                ):andThen(function()
                    return try(tryNumber + 1)
                end)
                
                resolve(promise)
            end
        end)
    end

    return try(0)
end

function DataStoreUtils.update(dataStore, key, transformFunction, options)
    return exponentialBackoff(function()
        return dataStore:UpdateAsync(key, transformFunction)
    end, options)
end

function DataStoreUtils.get(dataStore, key, options)
    return exponentialBackoff(function()
        return dataStore:GetAsync(key, NO_CACHE_OPTIONS)
    end, options)
end

function DataStoreUtils.set(dataStore, key, value, setOptions, options)
    return exponentialBackoff(function()
        return dataStore:SetAsync(key, value, setOptions)
    end, options)
end

return DataStoreUtils
