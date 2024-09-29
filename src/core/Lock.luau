local HttpService = game:GetService("HttpService")
local Promise = require(script.Parent.Parent.Parent.Promise)
local Lock = {}
Lock.__index = Lock

function Lock.new()
    local self = setmetatable({}, Lock)

    self.lockId = nil
    self.queue = {}

    return self
end

function Lock:isLocked()
    return self.lockId ~= nil
end

function Lock:lock()
    if self.lockId == nil then
        local lockId = HttpService:GenerateGUID(false)
        self.lockId = lockId
        return Promise.resolve(lockId)
    else
        local promise = Promise.new(function(resolve, reject, onCancel)
            table.insert(self.queue, {resolve = resolve, reject = reject, onCancel = onCancel})
        end)
        return promise
    end
end

function Lock:unlock(lockId)
    if self.lockId ~= lockId then
        error("Invalid lockId")
    end

    self.lockId = nil

    while #self.queue > 0 do
        local nextInQueue = table.remove(self.queue, 1)
        if nextInQueue.onCancel() then continue end

        local newLockId = HttpService:GenerateGUID(false)
        self.lockId = newLockId
        nextInQueue.resolve(newLockId)
    end
end

function Lock:whileLocked(fn)
    local lockId
    return self:lock()
        :andThen(function(id)
            lockId = id
        end)
        :andThenCall(fn)
        :finally(function()
            if lockId then
                self:unlock(lockId)
            end
        end)
end

return Lock
