local File = require(script.Parent.File)
local patch = require(script.Parent.patch)
local TransactionManager = require(script.Parent.TransactionManager)
local Debug = require(script.Parent.Debug)
local types = require(script.Parent.types)

--[=[
    @class Document
    To interact with a document, a [Snapshot] must be created. This is done by calling [Mailroom:createSnapshot].
]=]
local Document = {}
Document.__index = Document
Document._type = "Document" :: "Document"

export type InternalReducer<Data, Metadata, Action> = patch.Reducer<types.DocumentDataInternal<Data, Metadata, Action>, Action>

export type Document<Data, Metadata, Action> = typeof(setmetatable(
    {} :: {
        file: File.File<types.DocumentDataInternal<Data, Metadata, Action>>,
        reducer: InternalReducer<Data, Metadata, Action>,
        transactionManager: TransactionManager.TransactionManager,
    },
    Document
))

local function documentLoadTransformWrapper<Data, Metadata, Action>(loadTransform: types.LoadTransform<Data, Metadata, Action>)
    local transform: File.LoadTransform<types.DocumentDataInternal<Data, Metadata, Action>> = function(data: unknown?, keyInfo: DataStoreKeyInfo?)
        if typeof(data) ~= "table" then
            data = {}
            Debug.debug("Document data was not a table, initializing to empty table")
        end

        local inner, metadata = loadTransform((data :: any).data, keyInfo)
        local userIds = if keyInfo ~= nil then keyInfo:GetUserIds() else {} :: {number}
        return {
            data = inner,
            metadata = metadata,
            userIds = userIds,
            mailroom = (data :: any).mailroom or {} :: any
        }
    end

    return transform
end

local function documentSaveTransformWrapper<Data, Metadata, Action>(saveTransform: (data: Data, metadata: Metadata) -> (any, {[any]: any}))
    local transform: File.SaveTransform<types.DocumentDataInternal<Data, Metadata, Action>> = function(data)
        local inner, metadata = saveTransform(data.data, data.metadata)
        return {
            data = inner,
            mailroom = data.mailroom,
        }, data.userIds, metadata
    end

    return transform
end

local function reducerWrapper<Data, Metadata, Action>(reducer: (types.DocumentData<Data, Metadata>, Action) -> types.DocumentData<Data, Metadata>)
    local wrapped: InternalReducer<Data, Metadata, Action> = function(data: types.DocumentDataInternal<Data, Metadata, Action>, action: Action)
        local mailroom = data.mailroom
        local newData = reducer({
            data = data.data,
            metadata = data.metadata,
            userIds = data.userIds,
        }, action)
        assert(typeof(newData) == "table", "Reducer must return a table")

        assert(typeof(newData.metadata) == "table", "Reducer must return a table with a metadata field")
        assert(typeof(newData.userIds) == "table", "Reducer must return a table with a userIds field")

        return {
            data = newData.data,
            metadata = newData.metadata,
            userIds = newData.userIds,
            mailroom = mailroom,
        }
    end

    return wrapped
end

function Document.new<Data, Metadata, Action>(
    dataStore: DataStore,
    key: string,
    loadTransform: types.LoadTransform<Data, Metadata, Action>,
    saveTransform: types.SaveTransform<Data, Metadata, Action>,
    reducer: types.Reducer<Data, Metadata, Action>,
    transactionManager: TransactionManager.TransactionManager
): Document<Data, Metadata, Action>
    local self = setmetatable({
        file = File.new(dataStore, key, documentLoadTransformWrapper(loadTransform), documentSaveTransformWrapper(saveTransform)),
        reducer = reducerWrapper(reducer),
        transactionManager = transactionManager,
    }, Document)
    return self
end

function Document.get<Data, Metadata, Action>(self: Document<Data, Metadata, Action>): types.DocumentDataInternal<Data, Metadata, Action>
    local result = self.file:get()
    local txInfo = result.mailroom.transaction

    if txInfo then
        Debug.info("Document.get for", self.file.key, "found transaction", {txInfo.id})
        local resolved = self.transactionManager:checkResolved(txInfo)
        Debug.info("Document.get transaction", txInfo.id, "resolved:", resolved)
        result.mailroom.transaction = nil

        if resolved > 0 then
            result.data = txInfo.data[resolved]
        end
    end

    return result
end

function Document.patch<Data, Metadata, Action>(
    self: Document<Data, Metadata, Action>,
    actions: {{Action}},
    oldTransactionId: string?,
    oldTransactionResolved: number?,
    newTransactionInfo: types.TransactionOptions<Action>?
): (patch.PatchResult<types.DocumentDataInternal<Data, Metadata, Action>, Action>, number?)
    local patchResult: patch.PatchResult<types.DocumentDataInternal<Data, Metadata, Action>, Action>
    local newTransactionSucceeded: number? = nil
    local data = self.file:update(function(data: types.DocumentDataInternal<Data, Metadata, Action>): types.DocumentDataInternal<Data, Metadata, Action>?
        local internal = table.clone(data.mailroom)
        local txInfo = internal.transaction
        if txInfo then
            Debug.info("Document.patch for", self, "found transaction", txInfo.id)
            if txInfo.id ~= oldTransactionId then
                -- check the cache to see if we know if this transaction is resolved
                -- since we don't know if it's resolved
                local isResolved = self.transactionManager:checkResolvedCache(txInfo.id)
                if isResolved == nil then
                    Debug.info("Document.patch transaction", txInfo.id, "resolution unknown, skipping")
                    return nil
                else
                    Debug.info("Document.patch transaction", txInfo.id, "resolved (cached):", isResolved)
                    oldTransactionId = txInfo.id
                    oldTransactionResolved = isResolved
                end
            end

            internal.transaction = nil
            Debug.info("Document.patch transaction", txInfo.id, "already resolved, applying patch")
            
            data = table.clone(data)
            if oldTransactionResolved and oldTransactionResolved > 0 then
                data.data = txInfo.data[oldTransactionResolved]               
            end
        end

        data = table.clone(data)
        data.mailroom = internal
        patchResult = patch(data, self.reducer, actions)

        data = table.clone(patchResult.data)
        internal = table.clone(data.mailroom)

        if newTransactionInfo and patchResult.success then
            Debug.info("Document.patch for", self, "applying new transaction", newTransactionInfo.id)
            local result = patch(data, self.reducer, newTransactionInfo.actions)
            Debug.debug("Document.patch new transaction", newTransactionInfo.id, "patch result:", result)

            local dataValues = {} :: {Data}

            for i,v in result.returns do
                table.insert(dataValues, v.data)
            end

            internal.transaction = {
                id = newTransactionInfo.id,
                failsAfter = newTransactionInfo.failsAfter,
                timeoutAfter = newTransactionInfo.timeoutAfter,
                data = dataValues,
            }
            if result.success then
                newTransactionSucceeded = #newTransactionInfo.actions
            else
                newTransactionSucceeded = result.actionGroupIndex - 1
            end
        end

        data = table.clone(patchResult.data)
        data.mailroom = internal

        return data
    end)

    assert(data ~= nil) -- for type checker

    local txInfo = data.mailroom.transaction
    if txInfo and (newTransactionInfo == nil or newTransactionInfo.id ~= txInfo.id) then
        -- we must resolve this
        Debug.info("Document.patch for", self, "found transaction", txInfo.id)
        local resolved = self.transactionManager:checkResolved(txInfo)
        return (self:patch(actions, txInfo.id, resolved, newTransactionInfo))
    end

    Debug.debug("Document.patch for", self, "patch result:", patchResult)

    ;(patchResult :: any).data = data
    return patchResult, newTransactionSucceeded
end

function Document.__tostring(self: Document<any, any, any>): string
    return `Document({self.file})`
end

return Document
