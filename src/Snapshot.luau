local Document = require(script.Parent.Document)
local Lock = require(script.Parent.Lock)
local patch = require(script.Parent.patch)
local TransactionManager = require(script.Parent.TransactionManager)

local deepFreeze = require(script.Parent.deepFreeze)

local Snapshot = {}
Snapshot.__index = Snapshot
Snapshot._type = "Snapshot" :: "Snapshot"

type SnapshotParent<Data,Metadata,Action> = Snapshot<Data,Metadata,Action> | Document.Document<Data,Metadata,Action>

export type Snapshot<Data,Metadata,Action> = typeof(setmetatable(
    {} :: {
        parent: SnapshotParent<Data,Metadata,Action>,
        head: Document.DocumentData<Data,Metadata,Action>,
        base: Document.DocumentData<Data,Metadata,Action>,
        actions: {Action},
        reducer: Document.InternalReducer<Data,Metadata,Action>,
        lock: Lock.Lock,
        updateCallback: () -> ()?,
    },
    Snapshot
))

function Snapshot.new<Data,Metadata,Action>(
    parent: SnapshotParent<Data,Metadata,Action>,
    data: Document.DocumentData<Data,Metadata,Action>,
    updateCallback: () -> ()?
): Snapshot<Data,Metadata,Action>
    deepFreeze(data)

    local self = setmetatable({
        parent = parent,
        head = data,
        base = data,
        actions = {},
        reducer = parent.reducer,
        lock = Lock.new(),
        updateCallback = updateCallback,
    }, Snapshot)

    if self.updateCallback then
        task.spawn(self.updateCallback)
    end

    return self
end

function Snapshot.get<Data,Metadata,Action>(
    self: Snapshot<Data,Metadata,Action>
): Document.BaseDocumentData<Data,Metadata>
    return table.freeze({
        data = self.head.data,
        metadata = self.head.metadata,
        userIds = self.head.userIds,
    })
end

function Snapshot.dispatch<Data,Metadata,Action>(
    self: Snapshot<Data,Metadata,Action>,
    action: Action
): patch.PatchResult<Document.DocumentData<Data,Metadata,Action>, Action>
    -- apply patch
    local result = patch(self.head, self.reducer, {action})
    if result.success then
        self.head = result.data
        table.insert(self.actions, action)

        if self.updateCallback then
            task.spawn(self.updateCallback)
        end
    end

    return result
end

-- not actually async
function Snapshot.patch<Data,Metadata,Action>(
    self: Snapshot<Data,Metadata,Action>,
    actions: {Action}
): patch.PatchResult<Document.DocumentData<Data,Metadata,Action>, Action>
    local result = patch(self.head, self.reducer, actions)
    self.head = result.data

    for i, action in actions do
        if not result.success and i >= result.index then break end
        table.insert(self.actions, action)
    end

    if (result.success or result.index ~= 1) and self.updateCallback then
        task.spawn(self.updateCallback)
    end

    return result
end

function Snapshot._sync<Data,Metadata,Action>(
    self: Snapshot<Data,Metadata,Action>,
    newTransactionInfo: TransactionManager.TransactionInfo<Action>?
): patch.PatchResult<Document.DocumentData<Data,Metadata,Action>, Action>
    local actions = table.clone(self.actions)
    local result: patch.PatchResult<Document.DocumentData<Data,Metadata,Action>, Action> 
    if newTransactionInfo then
        assert(self.parent._type == "Document", "Cannot run a transaction on a snapshot that does not have a document as parent")
        result = (self.parent :: Document.Document<Data,Metadata,Action>):patch(actions, nil, nil, newTransactionInfo)
    else
        result = (self.parent :: any):patch(actions)
    end

    -- reapply actions
    local newActions
    if result.success then
        -- if the patch was successful, we can remove all actions that we patched
        newActions = {unpack(self.actions, #actions)}
    else
        -- if the patch was not successful, we discard all actions that were not applied
        -- including those after :sync was called
        newActions = {}
    end

    local newResult = patch(result.data, self.reducer, newActions)

    self.base = result.data
    self.head = newResult.data
    self.actions = {unpack(newActions, 1, if newResult.success then nil else newResult.index - 1)}

    if self.updateCallback then
        task.spawn(self.updateCallback)
    end

    if not newResult.success then
        return newResult
    end

    return result
end

function Snapshot.sync<Data,Metadata,Action>(
    self: Snapshot<Data,Metadata,Action>
)
    local doUnlock = self.lock:lock()

    local success, result = pcall(self._sync, self)

    if doUnlock then
        self.lock:unlock()
    end

    if not success then
        error(result)
    end

    return result
end

return Snapshot