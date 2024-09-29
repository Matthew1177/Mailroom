local TableUtils = require(script.Parent.Parent.core.TableUtils)
local Snapshot = require(script.Parent.Parent.core.Snapshot)
local Promise = require(script.Parent.Parent.Parent.Promise)

local function resolveDocument(snapshotOrDocument)
    if snapshotOrDocument.type == "CollectionDocument" then
        return snapshotOrDocument
    else
        local parent = snapshotOrDocument.parent
        assert(parent and parent.type == "CollectionDocument")
        return parent
    end
end

local function resolveDocuments(transactionData)
    local documents = {}
    for i,v in transactionData do
        local doc = resolveDocument(i)
        assert(doc.type == "CollectionDocument", "Expected CollectionDocument, got " .. doc.type)
        documents[i] = doc
    end
    return documents
end

local function acquireLocks(documents)
    local lockPromises = {}
    for i, document in documents do
        lockPromises[i] = document.lock:lock()
    end
    return Promise.all(lockPromises) -- lock will never reject so this is safe
end

local function whileAllLocked(documents, fn)
    local lockIds
    return acquireLocks(documents)
        :andThen(function(ids)
            lockIds = ids
        end)
        :andThenCall(fn)
        :finally(function()
            for i, lockId in lockIds do
                documents[i].lock:unlock(lockId)
            end
        end)
end

local function resolveSnapshots(transactionData)
    local snapshots = {}
    for i in transactionData do
        if i.type == "Snapshot" then
            local derivedSnapshot = Snapshot.fromExisting(i)
            snapshots[i] = {
                originCommitCount = #derivedSnapshot.commits,
                snapshot = derivedSnapshot
            }
        elseif i.type == "CollectionDocument" then
            snapshots[i] = {
                snapshot = Snapshot.new(i)
            }
        else
            error("Invalid type")
        end
    end
    -- resolve all snapshots
    local snapshotPromises = {}
    for i,v in snapshots do
        if v.snapshot and not v.originCommitCount then
            table.insert(snapshotPromises, v.snapshot:rebase(false, nil, true))
        end
    end

    return Promise.all(snapshotPromises)
        :andThenReturn(snapshots)
end

local function runSingleDocumentTransaction(transactionData)
    local documents = resolveDocuments(transactionData)
    return whileAllLocked(documents, function()
        return Promise.new(function(resolve, reject)
            local snapshotInfo = resolveSnapshots(transactionData):expect()
            local snapshots = {}
            for i,v in snapshotInfo do
                snapshots[i] = v.snapshot
            end

            local origin, info = next(snapshotInfo)
            local snapshot = info.snapshot
            local result = snapshot:patch(TableUtils.deepFreeze({
                {
                    type = "mailroom:atomic",
                    actions = transactionData[origin]
                }
            })):expect()
            if not result.success then reject(result) end
            local mergePromise = snapshot:sync(false, nil, true)

            if info.originCommitCount then
                mergePromise = mergePromise:andThen(function()
                    origin:squashAndSetBase(info.originCommitCount, snapshot.head, true)
                end, function(result)
                    origin:squashAndSetBase(result.index - 1, result.data, true)
                    return Promise.reject(result) -- rethrow
                end)
            end

            resolve(mergePromise)
        end)
    end)
end

--[[
    Runs a transaction. Discards any incompatible commits that
    were added to the snapshots after the transaction was started.
]]
local function runTransaction(transactionData)
    local count = 0
    for _,commits in transactionData do
        TableUtils.tryFreeze(commits)
        count += 1
    end

    TableUtils.tryFreeze(transactionData)
    assert(count > 0, "Expected at least one snapshot or document")

    if count == 1 then
        return runSingleDocumentTransaction(transactionData)
    end
    error("Not implemented")
end

return runTransaction