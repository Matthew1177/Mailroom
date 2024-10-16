local File = require(script.Parent.File)
local patch = require(script.Parent.patch)
local TransactionManager = require(script.Parent.TransactionManager)
local Debug = require(script.Parent.Debug)

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
): Document<Data, Metadata, Action>
    local self = setmetatable({
        file = File.new(dataStore, key, loadTransform, saveTransform),
        reducer = reducer,
        transactionManager = transactionManager,
    }, Document)
    return self
end

function Document.get<Data, Metadata, Action>(self: Document<Data, Metadata, Action>): DocumentData<Data, Metadata, Action>
    local result = self.file:get()
    local txInfo = result.internal.transaction
    if txInfo then
        Debug:info(`Document.get for {self.file.key} found transaction {txInfo.id}`)
        local resolved = self.transactionManager:checkResolvedAsync(txInfo)
        Debug:info(`Document.get transaction {txInfo.id} resolved: {resolved}`)
        result.internal.transaction = nil
        if resolved then
            local patchResult = patch(result, self.reducer, txInfo.actions)
            Debug:verbose(`Document.get transaction {txInfo.id} patch result: {patchResult}`)
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
): patch.PatchResult<DocumentData<Data, Metadata, Action>, Action>
    local patchResult: patch.PatchResult<DocumentData<Data, Metadata, Action>, Action>
    local data = self.file:update(function(data: DocumentData<Data, Metadata, Action>): DocumentData<Data, Metadata, Action>?
        local txInfo = data.internal.transaction
        if txInfo then
            Debug:info(`Document.patch for {self} found transaction {txInfo.id}`)
            if txInfo.id ~= oldTransactionId then
                Debug:info(`Document.patch transaction {txInfo.id} resolution unknown, skipping`)
                return nil
            end

            data.internal.transaction = nil
            if oldTransactionResolved then
                Debug:info(`Document.patch transaction {txInfo.id} already resolved, applying patch`)
                local transactionPatch = patch(data, self.reducer, txInfo.actions)
                Debug:verbose(`Document.patch transaction {txInfo.id} patch result: {transactionPatch}`)
                assert(transactionPatch.success, "Old transaction failed to apply")
                data = transactionPatch.data
            end
        end

        if newTransactionInfo then
            Debug:info(`Document.patch for {self} applying new transaction {newTransactionInfo.id}`)
            local result = patch(data, self.reducer, newTransactionInfo.actions)
            Debug:verbose(`Document.patch new transaction {newTransactionInfo.id} patch result: {result}`)
            if not result.success then
                error("New transaction failed to apply")
            end
            data.internal.transaction = newTransactionInfo
        end

        patchResult = patch(data, self.reducer, actions)
        return patchResult.data
    end)

    local txInfo = data.internal.transaction
    if txInfo and (newTransactionInfo == nil or newTransactionInfo.id ~= txInfo.id) then
        -- we must resolve this
        Debug:info(`Document.patch for {self} found transaction {txInfo.id}`)
        local resolved = self.transactionManager:checkResolvedAsync(txInfo)
        return self:patch(actions, txInfo.id, resolved, newTransactionInfo)
    end

    (patchResult :: any).data = data
    return patchResult
end

function Document.__tostring(self: Document<any, any, any>): string
    return `Document({self.file})`
end

return Document
