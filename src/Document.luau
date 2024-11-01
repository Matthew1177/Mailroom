local File = require(script.Parent.File)
local patch = require(script.Parent.patch)
local TransactionManager = require(script.Parent.TransactionManager)
local Debug = require(script.Parent.Debug)

local Document = {}
Document.__index = Document
Document._type = "Document" :: "Document"

export type LoadTransform<Data, Metadata, Action> = (data: unknown?, keyInfo: DataStoreKeyInfo?) -> (Data, Metadata)
export type SaveTransform<Data, Metadata, Action> = (data: Data, metadata: Metadata) -> (any, {[any]: any})
export type Reducer<Data, Metadata, Action> = (BaseDocumentData<Data, Metadata>, Action) -> BaseDocumentData<Data, Metadata>
export type InternalReducer<Data, Metadata, Action> = patch.Reducer<DocumentData<Data, Metadata, Action>, Action>

export type BaseDocumentData<Data, Metadata> = {
    data: Data,
    metadata: Metadata,
    userIds: {number},
}

export type DocumentData<Data, Metadata, Action> = BaseDocumentData<Data, Metadata> & {
    mailroom: {
        transaction: TransactionManager.TransactionInfo<Action>?,
    }
}

export type Document<Data, Metadata, Action> = typeof(setmetatable(
    {} :: {
        file: File.File<DocumentData<Data, Metadata, Action>>,
        reducer: InternalReducer<Data, Metadata, Action>,
        transactionManager: TransactionManager.TransactionManager,
    },
    Document
))

local function documentLoadTransformWrapper<Data, Metadata, Action>(loadTransform: LoadTransform<Data, Metadata, Action>)
    local transform: File.LoadTransform<DocumentData<Data, Metadata, Action>> = function(data: unknown?, keyInfo: DataStoreKeyInfo?)
        if typeof(data) ~= "table" then
            data = {}
            Debug:debug("Document data was not a table, initializing to empty table")
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
    local transform: File.SaveTransform<DocumentData<Data, Metadata, Action>> = function(data)
        local inner, metadata = saveTransform(data.data, data.metadata)
        return {
            data = inner,
            mailroom = data.mailroom,
        }, data.userIds, metadata
    end

    return transform
end

local function reducerWrapper<Data, Metadata, Action>(reducer: (BaseDocumentData<Data, Metadata>, Action) -> BaseDocumentData<Data, Metadata>)
    local wrapped: InternalReducer<Data, Metadata, Action> = function(data, action)
        local mailroom = data.mailroom
        local newData = reducer(data, action)
        assert(typeof(newData) == "table", "Reducer must return a table")

        assert(typeof(newData.data) == "table", "Reducer must return a table with a data field")
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
    loadTransform: LoadTransform<Data, Metadata, Action>,
    saveTransform: SaveTransform<Data, Metadata, Action>,
    reducer: Reducer<Data, Metadata, Action>,
    transactionManager: TransactionManager.TransactionManager
): Document<Data, Metadata, Action>
    local self = setmetatable({
        file = File.new(dataStore, key, documentLoadTransformWrapper(loadTransform), documentSaveTransformWrapper(saveTransform)),
        reducer = reducerWrapper(reducer),
        transactionManager = transactionManager,
    }, Document)
    return self
end

function Document.get<Data, Metadata, Action>(self: Document<Data, Metadata, Action>): DocumentData<Data, Metadata, Action>
    local result = self.file:get()
    local txInfo = result.mailroom.transaction
    if txInfo then
        Debug:info("Document.get for", self.file.key, "found transaction", {txInfo.id})
        local resolved = self.transactionManager:checkResolved(txInfo)
        Debug:info("Document.get transaction", txInfo.id, "resolved:", resolved)
        result.mailroom.transaction = nil
        if resolved then
            local patchResult = patch(result, self.reducer, txInfo.actions)
            Debug:debug("Document.get transaction", txInfo.id, "patch result:", patchResult)
            if not patchResult.success then
                error("Transaction failed to apply")
            end
            return patchResult.data
        end
    end
    return result
end

function Document.patch<Data, Metadata, Action>(
    self: Document<Data, Metadata, Action>,
    actions: {Action},
    oldTransactionId: string?,
    oldTransactionResolved: boolean?,
    newTransactionInfo: TransactionManager.TransactionInfo<Action>?
): (patch.PatchResult<DocumentData<Data, Metadata, Action>, Action>, boolean?)
    local patchResult: patch.PatchResult<DocumentData<Data, Metadata, Action>, Action>
    local newTransactionSucceeded: boolean? = nil
    local data = self.file:update(function(data: DocumentData<Data, Metadata, Action>): DocumentData<Data, Metadata, Action>?
        local internal = table.clone(data.mailroom)
        local txInfo = internal.transaction
        if txInfo then
            Debug:info("Document.patch for", self, "found transaction", txInfo.id)
            if txInfo.id ~= oldTransactionId then
                -- check the cache to see if we know if this transaction is resolved
                -- since we don't know if it's resolved
                local isResolved = self.transactionManager:checkResolvedCache(txInfo.id)
                if isResolved == nil then
                    Debug:info("Document.patch transaction", txInfo.id, "resolution unknown, skipping")
                    return nil
                else
                    Debug:info("Document.patch transaction", txInfo.id, "resolved (cached):", isResolved)
                    oldTransactionId = txInfo.id
                    oldTransactionResolved = isResolved
                end
            end

            internal.transaction = nil
            if oldTransactionResolved then
                Debug:info("Document.patch transaction", txInfo.id, "already resolved, applying patch")
                local transactionPatch = patch(data, self.reducer, txInfo.actions)
                Debug:debug("Document.patch transaction", txInfo.id, "patch result:", transactionPatch)
                if not transactionPatch.success then
                    warn("Failed to apply transaction patch; " ..
                        "the reducer may have side effects or have changed since the transaction was created for", self)
                    -- we can't fully apply the transaction, so we'll just apply as much as we can
                    -- this isn't ideal, but it's better than forcing the document to remain in an
                    -- invalid state
                end
                data = transactionPatch.data                
            end
        end

        data = table.clone(data)
        data.mailroom = internal
        patchResult = patch(data, self.reducer, actions)

        data = table.clone(patchResult.data)
        internal = table.clone(data.mailroom)

        if newTransactionInfo and patchResult.success then
            Debug:info("Document.patch for", self, "applying new transaction", newTransactionInfo.id)
            local result = patch(data, self.reducer, newTransactionInfo.actions)
            Debug:debug("Document.patch new transaction", newTransactionInfo.id, "patch result:", result)
            if result.success then
                newTransactionSucceeded = true
                internal.transaction = newTransactionInfo
            else
                newTransactionSucceeded = false
            end
        end

        data.mailroom = internal

        return data
    end)

    assert(data ~= nil) -- for type checker

    local txInfo = data.mailroom.transaction
    if txInfo and (newTransactionInfo == nil or newTransactionInfo.id ~= txInfo.id) then
        -- we must resolve this
        Debug:info("Document.patch for", self, "found transaction", txInfo.id)
        local resolved = self.transactionManager:checkResolved(txInfo)
        return (self:patch(actions, txInfo.id, resolved, newTransactionInfo))
    end

    Debug:debug("Document.patch for", self, "patch result:", patchResult)

    ;(patchResult :: any).data = data
    return patchResult, newTransactionSucceeded
end

function Document.__tostring(self: Document<any, any, any>): string
    return `Document({self.file})`
end

return Document
