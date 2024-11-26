local DataStoreService = game:GetService("DataStoreService") :: DataStoreService
local TransactionDataStore = DataStoreService:GetDataStore("MailroomTransactions") :: DataStore
local types = require(script.Parent.types)

local NO_CACHE_OPTIONS = Instance.new("DataStoreGetOptions")
NO_CACHE_OPTIONS.UseCache = false

local TransactionManager = {}
TransactionManager.__index = TransactionManager

export type TransactionManager = typeof(setmetatable(
    {} :: {
        cache: {[string]: {any}},
    },
    TransactionManager
))

function TransactionManager.new(): TransactionManager
    local self = setmetatable({
    }, TransactionManager)

    self.cache = {} -- TODO: make LRU cache

    return self
end

function TransactionManager.forceCheckResolved(self: TransactionManager, info: types.TransactionInfo<unknown>): number
    local fails = 0
    repeat
        local success: boolean, result: unknown, keyInfo: DataStoreKeyInfo = pcall(function()
            return TransactionDataStore:GetAsync(info.id, NO_CACHE_OPTIONS)
        end)

        local now = DateTime.now().UnixTimestampMillis
        if success then
            assert(typeof(result) == "number" or typeof(result) == "nil")
            if result == nil then
                if now > info.timeoutAfter then
                    return 0
                end
            elseif result == 0 then
                return 0
            else
                if keyInfo.UpdatedTime > info.failsAfter then
                    return 0
                end
                return result
            end
        else
            fails += 1
            if fails >= 3 then
                error(result)
            end
        end

        task.wait(6)
    until false
end

function TransactionManager.checkResolved(self: TransactionManager, info: types.TransactionInfo<unknown>): number
    local cached = self:checkResolvedCache(info.id)
    if cached ~= nil then
        return cached
    end

    local key = string.sub(info.id, 1, 2)
    local newValue = self:forceCheckResolved(info)
    self.cache[key] = {info.id, newValue}
    return newValue
end

function TransactionManager.checkResolvedCache(self: TransactionManager, id: string): number?
    local key = string.sub(id, 1, 2)
    local cached = self.cache[key]
    if cached and cached[1] == id then
        return cached[2]
    end

    return nil
end

function TransactionManager.forceMarkResolved(self: TransactionManager, id: string, failsAfter: number, timeoutAfter: number, status: number): number
    if status == 0 then return 0 end

    local now = DateTime.now().UnixTimestampMillis
    if now > timeoutAfter then
        return 0
    end

    local _,keyInfo = TransactionDataStore:UpdateAsync(id, function()
        return status, nil, nil
    end)

    return if keyInfo.UpdatedTime > failsAfter then 0 else status
end

function TransactionManager.markResolved(self: TransactionManager, id: string, failsAfter: number, timeoutAfter: number, status: number): number
    local cached = self:checkResolvedCache(id)
    if cached ~= nil then
        return cached
    end
    
    local key = string.sub(id, 1, 2)
    local newValue = self:forceMarkResolved(id, failsAfter, timeoutAfter, status)
    self.cache[key] = {id, newValue}
    return newValue
end

return TransactionManager