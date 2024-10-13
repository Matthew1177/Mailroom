local Lock = {}
Lock.__index = Lock

function Lock.new(): Lock
    local self = setmetatable({
        lockThread = nil :: thread?,
        queue = {},
    }, Lock)

    return self
end

function Lock.hasLock(self: Lock): boolean
    return self.lockThread == coroutine.running()
end

function Lock.lock(self: Lock): boolean
    local running = coroutine.running()
    if running == self.lockThread then
        return false
    end

    if self.lockThread == nil then
        -- silence typechecker
        self.lockThread = running :: any
        return true
    end

    table.insert(self.queue, running)
    coroutine.yield()

    self.lockThread = running
    
    return true
end

function Lock.unlock(self: Lock)
    local canUnlock = not self.lockThread
        or self.lockThread == coroutine.running()
    if not canUnlock then
        error("Cannot unlock a lock that is not owned by the current thread")
    end
    self.lockThread = nil
    if #self.queue > 0 then
        local nextCoroutine = table.remove(self.queue, 1) :: thread
        task.defer(nextCoroutine)
    end
end

export type Lock = typeof(setmetatable(
    {} :: {
        lockThread: thread?,
        queue: {thread},
    },
    Lock
))

return Lock