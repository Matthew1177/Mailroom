local File = require(script.Parent.File)
local patch = require(script.Parent.patch)
local TransactionManager = require(script.Parent.TransactionManager)
local Document = {}
Document.__index = Document
Document._type = "Document" :: "Document"

export type DocumentData<Data, Metadata, Action> = {
    data: Data,
    metadata: Metadata,
    userIds: {number},
    keyInfo: DataStoreKeyInfo,
    internal: {
        transaction: TransactionManager.TransactionInfo<Action>?,
    }
}

export type Document<Data, Metadata, Action> = typeof(setmetatable(
    {} :: {
        file: File.File<DocumentData<Data, Metadata, Action>>,
        reducer: patch.Reducer<DocumentData<Data, Metadata, Action>, Action>,
        transactionManager: TransactionManager.TransactionManager,
    },
    Document
))

function Document.new<Data, Metadata, Action>(
    dataStore: DataStore,
    key: string,
    loadTransform: File.LoadTransform<DocumentData<Data, Metadata, Action>>,
    saveTransform: File.SaveTransform<DocumentData<Data, Metadata, Action>>,
    reducer: patch.Reducer<DocumentData<Data, Metadata, Action>, Action>,
    transactionManager: TransactionManager.TransactionManager
)
    local self = setmetatable({
        file = File.new(dataStore, key, loadTransform, saveTransform),
        reducer = reducer,
        transactionManager = transactionManager,
    }, Document)
    return self
end

function Document.getAsync<Data, Metadata, Action>(self: Document<Data, Metadata, Action>): DocumentData<Data, Metadata, Action>
    local result = self.file:getAsync()
    local txInfo = result.internal.transaction
    if txInfo then
        local resolved = self.transactionManager:checkResolvedAsync(txInfo)
        result.internal.transaction = nil
        if resolved then
            local patchResult = patch(result, self.reducer, txInfo.actions)
            if not patchResult.success then
                error("Transaction failed to apply")
            end
            return patchResult.data
        end
    end
    return result
end

function Document._patchAsync<Data, Metadata, Action>(
    self: Document<Data, Metadata, Action>,
    actions: {Action},
    transactionId: string?,
    transactionResolved: boolean?
): patch.PatchResult<DocumentData<Data, Metadata, Action>, Action>
    local patchResult: patch.PatchResult<DocumentData<Data, Metadata, Action>, Action>
    local data = self.file:updateAsync(function(data: DocumentData<Data, Metadata, Action>): DocumentData<Data, Metadata, Action>?
        local txInfo = data.internal.transaction
        if txInfo then
            if txInfo.id ~= transactionId then
                return nil
            end

            data.internal.transaction = nil
            if transactionResolved then
                local transactionPatch = patch(data, self.reducer, txInfo.actions)
                assert(transactionPatch.success, "Transaction failed to apply")
                data = transactionPatch.data
            end
        end

        patchResult = patch(data, self.reducer, actions)
        return patchResult.data
    end)

    local txInfo = data.internal.transaction
    if txInfo then
        -- we must resolve this
        local resolved = self.transactionManager:checkResolvedAsync(txInfo)
        return self:_patchAsync(actions, txInfo.id, resolved)
    end

    (patchResult :: any).data = data
    return patchResult
end

function Document.patchAsync<Data, Metadata, Action>(
    self: Document<Data, Metadata, Action>,
    actions: {Action}
): patch.PatchResult<DocumentData<Data, Metadata, Action>, Action>
    return self:_patchAsync(actions, nil, nil)
end

return Document
