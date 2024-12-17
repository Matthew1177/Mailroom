local Debug = require(script.Parent.Debug)

local Collection = require(script.Parent.Collection)
local Document = require(script.Parent.Document)
local patch = require(script.Parent.patch)
local Snapshot = require(script.Parent.Snapshot)
local TransactionManager = require(script.Parent.TransactionManager)
local types = require(script.Parent.types)

local HttpService = game:GetService("HttpService") :: HttpService

local DataStoreService = game:GetService("DataStoreService") :: DataStoreService
local DEFAULT_TRANSACTION_DATASTORE = DataStoreService:GetDataStore("MailroomTransactions") :: DataStore

--[=[
    @class Mailroom
]=]
local Mailroom = {}
Mailroom.__index = Mailroom

export type Mailroom = typeof(setmetatable(
    {} :: {
        transactionManager: TransactionManager.TransactionManager,
    },
    Mailroom
))

type MailroomOptions = {
    transactionDataStore: DataStore?,
}

--[=[
    Construct a new Mailroom instance. In general, only one Mailroom instance should be created.
    @return Mailroom
]=]
function Mailroom.new(options: MailroomOptions?): Mailroom
    local transactionDataStore = if options and options.transactionDataStore
        then options.transactionDataStore else DEFAULT_TRANSACTION_DATASTORE

    local self = setmetatable({
        transactionManager = TransactionManager.new(transactionDataStore),
    }, Mailroom)

    return self
end

function Mailroom._runTransaction(
    self: Mailroom, 
    actionsMap: {[Snapshot.Snapshot<any> | Document.Document<any>]: {any}}
): number
    local mainThread = coroutine.running()

    local transactionId = HttpService:GenerateGUID(false)
    local failsAfter = DateTime.now().UnixTimestampMillis + 1000 * 10
    local timeoutAfter = failsAfter + 1000 * 2 -- 2 seconds extra

    Debug.info(
        `Mailroom._runTransaction starting transaction with info id={transactionId}, `
        .. `failsAfter={failsAfter}, timeoutAfter={timeoutAfter}`
    )

    local totalCnt = 0
    local resolvedCnt = 0
    local maxActions = 0
    for snapshotOrDocument, actions in actionsMap do
        totalCnt += 1
        maxActions = math.max(maxActions, #actions)
    end
    local resolved = maxActions

    for snapshotOrDocument, actions in actionsMap do
        local coro = coroutine.create(function()
            local txInfo: types.TransactionOptions<any> = {
                id = transactionId,
                failsAfter = failsAfter,
                timeoutAfter = timeoutAfter,
                actions = actions,
            }
            local _, didTransactionSucceed: number? = nil
            local success, message = (pcall :: any)(function()
                if snapshotOrDocument._type == "Document" then
                    _, didTransactionSucceed = (snapshotOrDocument :: Document.Document<any>):patch({}, nil, nil, txInfo)
                else
                    _, didTransactionSucceed = (snapshotOrDocument :: Snapshot.Snapshot<any>):_sync(txInfo)
                end
            end)

            if resolved == 0 then -- already resolved
                return
            end

            if not success then -- transaction failed
                Debug.debug("Mailroom._runTransaction transaction errored", message)
                resolved = 0
                task.defer(mainThread)
                return
            end

            if didTransactionSucceed == nil then
                Debug.debug("Mailroom._runTransaction transaction failed before transaction added")
                resolved = 0
                task.defer(mainThread)
                return
            end

            if didTransactionSucceed < #actions and didTransactionSucceed < resolved then
                resolved = didTransactionSucceed
            end

            if resolved == 0 then
                Debug.debug("Mailroom._runTransaction transaction failed")
                resolved = 0
                task.defer(mainThread)
                return
            end

            Debug.debug("Mailroom._runTransaction transaction resolved for", snapshotOrDocument)
            
            resolvedCnt += 1
            if resolvedCnt >= totalCnt then
                task.defer(mainThread)
            end
        end)
        task.defer(coro)
    end

    coroutine.yield()
    Debug.info("Mailroom._runTransaction main thread resumed")

    local didResolve = self.transactionManager:markResolved(transactionId, failsAfter, timeoutAfter, resolved)

    for snapshotOrDocument, actions in actionsMap do
        if snapshotOrDocument._type == "Snapshot" then
            local base = (snapshotOrDocument :: Snapshot.Snapshot<any>).base
            local tResult = patch(base, actions, didResolve)
            if not tResult.success then
                -- throw error in new thread
                task.spawn(error, "Transaction failed to apply after resolution - reducer may have side effects")
                task.spawn(error, tResult.error)
            end
            local newBase = tResult.data
            ;(snapshotOrDocument :: any).base = newBase
            local result = patch(newBase, (snapshotOrDocument :: any).actions)
            -- remove any actions that were not applied
            if not result.success then
                (snapshotOrDocument :: any).actions = {unpack((snapshotOrDocument :: any).actions, 1, result.index - 1)}
            end
            ;(snapshotOrDocument :: any).head = result.data
        end
    end

    return didResolve
end

-- TODO: type correctly
--[=[
    Run a transaction on a set of snapshots and documents.
    
    `actionsMap` is a map of snapshots or documents to an array of Actions to run on them. The actions are applied in the order they are given.

    @method runTransaction
    @param actionsMap {[Snapshot | Document]: {Action}}
    @return number
    @yields
    @within Mailroom
]=]
function Mailroom.runTransaction(
    self: Mailroom,
    actionsMap: any
): number
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
                local lock = (snapshotOrDocument :: Snapshot.Snapshot<any>).lock
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

    Debug.info("Mailroom.runTransaction waiting for all snapshots to lock")
    coroutine.yield()
    Debug.info("Mailroom.runTransaction all snapshots locked")

    local success, result = pcall(self._runTransaction, self, actionsMap)
    -- unlock all snapshots
    for lock, doUnlock in unlockMap do
        if doUnlock then
            lock:unlock(mainThread)
        end
    end

    Debug.info("Mailroom.runTransaction all snapshots unlocked")

    if not success then
        error(result)
    end

    return result :: number
end

--[=[
    Create a new collection.

    @method createCollection
    @param dataStore DataStore
    @param loadTransform LoadTransform
    @param saveTransform SaveTransform
    @return Collection
    @within Mailroom
]=]
function Mailroom.createCollection<Data>(
    self: Mailroom,
    dataStore: DataStore,
    loadTransform: types.LoadTransform<Data>,
    saveTransform: types.SaveTransform<Data>
): Collection.Collection<Data>
    return Collection.new(
        dataStore,
        loadTransform,
        saveTransform,
        self.transactionManager
    )
end

function Mailroom.createDocument<Data>(
self: Mailroom, dataStore, key, loadTransform, saveTransform, reducer
): Document.Document<Data>
    return Document.new(
        dataStore,
        key,
        loadTransform,
        saveTransform,
        reducer,
        self.transactionManager
    )
end

--[=[
    Create a new snapshot with a document or another snapshot as parent.

    @method createSnapshot
    @param parent Document | Snapshot
    @param options? {updateCallback: () -> ()?}
    @return Snapshot
    @yields
    @within Mailroom
]=]
function Mailroom.createSnapshot<Data>(
    self: Mailroom,
    parent: Document.Document<Data> | Snapshot.Snapshot<Data>,
    options: {
        updateCallback: () -> ()?,
    }?
): Snapshot.Snapshot<Data>
    local updateCallback = options and options.updateCallback or nil
    if parent._type == "Document" then
        return Snapshot.new(parent, (parent :: Document.Document<Data>):get(), updateCallback)
    else
        return Snapshot.new(parent, (parent :: Snapshot.Snapshot<Data>).head, updateCallback)
    end
end

return Mailroom
