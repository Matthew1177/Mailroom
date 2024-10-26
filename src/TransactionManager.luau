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
    },
    TransactionManager
))

function TransactionManager.new(): TransactionManager
    local self = setmetatable({
    }, TransactionManager)

    return self
end

function TransactionManager:checkResolved(info: TransactionInfo<unknown>): boolean
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

function TransactionManager:markResolved(id: string, failsAfter: number, timeoutAfter: number, status: boolean): boolean
    if status == false then return false end

    local now = DateTime.now().UnixTimestampMillis
    if now > timeoutAfter then
        return false
    end

   local _,keyInfo = TransactionDataStore:UpdateAsync(id, function()
        return true, nil, nil
   end)

    return keyInfo.UpdatedTime > failsAfter
end

return TransactionManager