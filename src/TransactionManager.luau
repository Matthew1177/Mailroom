local DataStoreService = game:GetService("DataStoreService") :: DataStoreService
local TransactionDataStore = DataStoreService:GetDataStore("MailroomTransactions") :: DataStore

local NO_CACHE_OPTIONS = Instance.new("DataStoreGetOptions")
NO_CACHE_OPTIONS.UseCache = false

local TransactionManager = {}
TransactionManager.__index = TransactionManager

export type TransactionInfo<Action> = {
    id: string,
    -- if resolved and after failsAfter, transaction will be considered failed
    failsAfter: number,
    -- if not resolved after timeoutAfter, transaction will be considered failed
    timeoutAfter: number,
    actions: {Action}
}

export type TransactionManager = typeof(setmetatable(
    {} :: {
        cache: {[string]: {any}},
    },
    TransactionManager
))

function TransactionManager.new(): TransactionManager
    local self = setmetatable({
    }, TransactionManager)

    self.cache = {}

    return self
end

function TransactionManager.forceCheckResolved(self: TransactionManager,info: TransactionInfo<unknown>): boolean
    local fails = 0
    repeat
        local success, result, keyInfo = pcall(function()
            return TransactionDataStore:GetAsync(info.id, NO_CACHE_OPTIONS)
        end)

        local now = DateTime.now().UnixTimestampMillis
        if success then
            if result == nil then
                if now > info.timeoutAfter then
                    return false
                end
            elseif result == true then
                if keyInfo.UpdatedTime > info.failsAfter then
                    return false
                end
                return true
            elseif result == false then
                return false
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

function TransactionManager.checkResolved(self: TransactionManager, info: TransactionInfo<unknown>): boolean
    local cached = self:checkResolvedCache(info.id)
    if cached ~= nil then
        return cached
    end

    local key = string.sub(info.id, 1, 2)
    local newValue = self:forceCheckResolved(info)
    self.cache[key] = {info.id, newValue}
    return newValue
end

function TransactionManager.checkResolvedCache(self: TransactionManager, id: string): boolean?
    local key = string.sub(id, 1, 2)
    local cached = self.cache[key]
    if cached and cached[1] == id then
        return cached[2]
    end

    return nil
end

function TransactionManager.forceMarkResolved(self: TransactionManager, id: string, failsAfter: number, timeoutAfter: number, status: boolean): boolean
    if status == false then return false end

    local now = DateTime.now().UnixTimestampMillis
    if now > timeoutAfter then
        return false
    end

    local _,keyInfo = TransactionDataStore:UpdateAsync(id, function()
        return true, nil, nil
    end)

    return not (keyInfo.UpdatedTime > failsAfter)
end

function TransactionManager.markResolved(self: TransactionManager, id: string, failsAfter: number, timeoutAfter: number, status: boolean): boolean
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