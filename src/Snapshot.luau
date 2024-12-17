local Document = require(script.Parent.Document)
local Lock = require(script.Parent.Lock)
local patch = require(script.Parent.patch)
local types = require(script.Parent.types)

local deepFreeze = require(script.Parent.deepFreeze)

--[=[
    @class Snapshot
]=]
local Snapshot = {}
Snapshot.__index = Snapshot
Snapshot._type = "Snapshot" :: "Snapshot"

type SnapshotParent<Data> = Snapshot<Data> | Document.Document<Data>

export type Snapshot<Data> = typeof(setmetatable(
    {} :: {
        parent: SnapshotParent<Data>,
        head: Data,
        base: Data,
        actions: {types.Action<Data>},
        lock: Lock.Lock,
        updateCallback: () -> ()?,
    },
    Snapshot
))

function Snapshot.new<Data>(
    parent: SnapshotParent<Data>,
    data: Data,
    updateCallback: () -> ()?
): Snapshot<Data>
    deepFreeze(data)

    local self = setmetatable({
        parent = parent,
        head = data,
        base = data,
        actions = {},
        lock = Lock.new(),
        updateCallback = updateCallback,
    }, Snapshot)

    if self.updateCallback then
        task.spawn(self.updateCallback)
    end

    return self
end

--[=[
    Get the current data and metadata of the snapshot.

    @method get
    @return Data
    @within Snapshot
]=]
function Snapshot.get<Data>(
    self: Snapshot<Data>
): Data
    return self.head
end

--[=[
    Update the snapshot.

    @method update
    @param action Action
    @return PatchResult
    @within Snapshot
]=]
function Snapshot.update<Data>(
    self: Snapshot<Data>,
    action: types.Action<Data>
): patch.PatchResult<Data>
    -- apply patch
    local result = patch(self.head,{action})
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
function Snapshot.patch<Data>(
    self: Snapshot<Data>,
    actions: {types.Action<Data>}
): patch.PatchResult<Data>
    local result = patch(self.head, actions)
    self.head = result.data

    for i, action in actions do
        if not result.success and i >= result.index then break end
        table.insert(self.actions, action)
    end

    if (result.success or result.actionGroupIndex ~= 1) and self.updateCallback then
        task.spawn(self.updateCallback)
    end

    return result
end

function Snapshot._sync<Data>(
    self: Snapshot<Data>,
    newTransactionInfo: types.TransactionOptions<Data>?
): (patch.PatchResult<Data>, number?)
    local actions = table.clone(self.actions)
    local result: patch.PatchResult<Data>
    local didTransactionSucceed: number?
    if newTransactionInfo then
        assert(self.parent._type == "Document", "Cannot run a transaction on a snapshot that does not have a document as parent")
        result, didTransactionSucceed = (self.parent :: Document.Document<Data>):patch(actions, nil, nil, newTransactionInfo)
    else
        result, didTransactionSucceed = (self.parent :: Snapshot<Data>):patch(actions)
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

    local newResult = patch(result.data, newActions)

    self.base = result.data
    self.head = newResult.data
    self.actions = {unpack(newActions, 1, if newResult.success then nil else newResult.index - 1)}

    if self.updateCallback then
        task.spawn(self.updateCallback)
    end

    if not newResult.success then
        return newResult, didTransactionSucceed
    end

    return result, didTransactionSucceed
end

--[=[
    Sync the snapshot with the DataStore.

    @method sync
    @return PatchResult
    @within Snapshot
]=]
function Snapshot.sync<Data>(
    self: Snapshot<Data>
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

function Snapshot:__tostring()
    return `Snapshot({self.parent})`
end

return Snapshot