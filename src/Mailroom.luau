local Debug = require(script.Parent.Debug)

local Collection = require(script.Parent.Collection)
local Document = require(script.Parent.Document)
local patch = require(script.Parent.patch)
local Snapshot = require(script.Parent.Snapshot)
local TransactionManager = require(script.Parent.TransactionManager)

local HttpService = game:GetService("HttpService") :: HttpService

local Mailroom = {}
Mailroom.__index = Mailroom

export type Mailroom = typeof(setmetatable(
    {} :: {
        transactionManager: TransactionManager.TransactionManager,
    },
    Mailroom
))

function Mailroom.new(): Mailroom
    local self = setmetatable({
        transactionManager = TransactionManager.new(),
    }, Mailroom)

    return self
end

function Mailroom._runTransaction(
    self: Mailroom, 
    actionsMap: {[Snapshot.Snapshot<any, any, any> | Document.Document<any, any, any>]: {any}}
): boolean
    local mainThread = coroutine.running()

    local transactionId = HttpService:GenerateGUID(false)
    local failsAfter = DateTime.now().UnixTimestampMillis + 1000 * 10
    local timeoutAfter = failsAfter + 1000 * 2 -- 2 seconds extra

    Debug:info(
        `Mailroom._runTransaction starting transaction with info id={transactionId}, `
        .. `failsAfter={failsAfter}, timeoutAfter={timeoutAfter}`
    )

    local totalCnt = 0
    local resolvedCnt = 0
    local resolved = nil
    for snapshotOrDocument, actions in actionsMap do
        totalCnt += 1
        local coro = coroutine.create(function()
            local txInfo = {
                id = transactionId,
                failsAfter = failsAfter,
                timeoutAfter = timeoutAfter,
                actions = actions,
            }
            local success, message = (pcall :: any)(function()
                if snapshotOrDocument._type == "Document" then
                    (snapshotOrDocument :: Document.Document<any, any, any>):patch({}, nil, nil, txInfo)
                else
                    (snapshotOrDocument :: Snapshot.Snapshot<any, any, any>):_sync(txInfo)
                end
            end)

            if resolved ~= nil then -- already resolved
                return
            end

            if not success then -- transaction failed
                Debug:debug("Mailroom._runTransaction transaction failed with message", message)
                resolved = false
                task.defer(mainThread)
                return
            end

            Debug:debug("Mailroom._runTransaction transaction resolved for", snapshotOrDocument)
            
            resolvedCnt += 1
            if resolvedCnt >= totalCnt then
                resolved = true
                task.defer(mainThread)
            end
        end)
        task.defer(coro)
    end

    coroutine.yield()
    Debug:info("Mailroom._runTransaction main thread resumed")

    assert(typeof(resolved) == "boolean")
    local didResolve = self.transactionManager:markResolved(transactionId, failsAfter, timeoutAfter, resolved)

    if didResolve then
        for snapshotOrDocument, actions in actionsMap do
            if snapshotOrDocument._type == "Snapshot" then
                local base = (snapshotOrDocument :: Snapshot.Snapshot<any, any, any>).base
                local tResult = patch(base, snapshotOrDocument.reducer, actions)
                if not tResult.success then
                    -- throw error in new thread
                    task.spawn(error, "Transaction failed to apply after resolution - reducer may have side effects")
                end
                local newBase = tResult.data
                ;(snapshotOrDocument :: any).base = newBase
                local result = patch(newBase, snapshotOrDocument.reducer, (snapshotOrDocument :: any).actions)
                ;(snapshotOrDocument :: any).head = result.data
                -- remove any actions that were not applied
                if not result.success then
                    (snapshotOrDocument :: any).actions = {unpack((snapshotOrDocument :: any).actions, result.index)}
                end
            end
        end
    end

    return didResolve
end

function Mailroom.runTransaction(
    self: Mailroom,
    actionsMap: {[Snapshot.Snapshot<any, any, any> | Document.Document<any, any, any>]: {any}}
): boolean
    for snapshotOrDocument in actionsMap do
        assert(snapshotOrDocument._type == "Document" 
            or (snapshotOrDocument :: any).parent._type == "Document",
            "Document or child of Document expected"
        )
    end

    local mainThread = coroutine.running()
    -- lock all snapshots
    local unlockMap = {}
    local cntSnapshots = 0
    local cntSnapshotsUnlocked = 0
    for snapshotOrDocument in actionsMap do
        if snapshotOrDocument._type == "Snapshot" then
            cntSnapshots += 1
            local coro = coroutine.create(function()
                local lock = (snapshotOrDocument :: Snapshot.Snapshot<any, any, any>).lock
                local res = lock:lock(mainThread)
                unlockMap[lock] = res
                cntSnapshotsUnlocked += 1
                if cntSnapshotsUnlocked >= cntSnapshots then
                    task.defer(mainThread)
                end
            end)
            task.defer(coro)
        end
    end

    Debug:info("Mailroom.runTransaction waiting for all snapshots to lock")
    coroutine.yield()
    Debug:info("Mailroom.runTransaction all snapshots locked")

    local success, result = pcall(self._runTransaction, self, actionsMap)
    -- unlock all snapshots
    for lock, doUnlock in unlockMap do
        if doUnlock then
            lock:unlock(mainThread)
        end
    end

    Debug:info("Mailroom.runTransaction all snapshots unlocked")

    if not success then
        error(result)
    end

    return result :: boolean
end

function Mailroom.createCollection<Data, Metadata, Action>(
    self: Mailroom,
    dataStore: DataStore,
    loadTransform: Document.LoadTransform<Data, Metadata, Action>,
    saveTransform: Document.SaveTransform<Data, Metadata, Action>,
    reducer: Document.Reducer<Data, Metadata, Action>
): Collection.Collection<Data, Metadata, Action>
    return Collection.new(
        dataStore,
        loadTransform,
        saveTransform,
        reducer,
        self.transactionManager
    )
end

function Mailroom.createDocument<Data, Metadata, Action>(
self: Mailroom, dataStore, key, loadTransform, saveTransform, reducer
): Document.Document<Data, Metadata, Action>
    return Document.new(
        dataStore,
        key,
        loadTransform,
        saveTransform,
        reducer,
        self.transactionManager
    )
end

function Mailroom.createSnapshot<Data, Metadata, Action>(
    self: Mailroom,
    parent: Document.Document<Data, Metadata, Action> | Snapshot.Snapshot<Data, Metadata, Action>,
    options: {
        updateCallback: () -> ()?,
    }?
): Snapshot.Snapshot<Data, Metadata, Action>
    local updateCallback = options and options.updateCallback or nil
    if parent._type == "Document" then
        return Snapshot.new(parent, (parent :: Document.Document<Data, Metadata, Action>).file:get(), updateCallback)
    else
        return Snapshot.new(parent, (parent :: Snapshot.Snapshot<Data, Metadata, Action>).head, updateCallback)
    end
end

return Mailroom
