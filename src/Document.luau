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

export type Document<Data> = typeof(setmetatable(
    {} :: {
        file: File.File<types.DocumentDataInternal<Data>>,
        transactionManager: TransactionManager.TransactionManager,
    },
    Document
))

local function documentLoadTransformWrapper<Data>(loadTransform: types.LoadTransform<Data>)
    local transform: File.LoadTransform<types.DocumentDataInternal<Data>> = function(data: unknown?, keyInfo: DataStoreKeyInfo?)
        if typeof(data) ~= "table" then
            data = {}
            Debug.debug("Document data was not a table, initializing to empty table")
        end

        local inner = loadTransform((data :: any).data)
        return {
            data = inner,
            mailroom = (data :: any).mailroom or {} :: any
        }
    end

    return transform
end

local function documentSaveTransformWrapper<Data>(saveTransform: types.SaveTransform<Data>)
    local transform: File.SaveTransform<types.DocumentDataInternal<Data>> = function(data)
        local inner = saveTransform(data.data)
        return {
            data = inner,
            mailroom = data.mailroom,
        }
    end

    return transform
end

function Document.new<Data>(
    dataStore: DataStore,
    key: string,
    loadTransform: types.LoadTransform<Data>,
    saveTransform: types.SaveTransform<Data>,
    transactionManager: TransactionManager.TransactionManager
): Document<Data>
    local self = setmetatable({
        file = File.new(dataStore, key, documentLoadTransformWrapper(loadTransform), documentSaveTransformWrapper(saveTransform)),
        transactionManager = transactionManager,
    }, Document)
    return self
end

function Document.get<Data>(self: Document<Data>): Data
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

    return result.data
end

function Document.patch<Data>(
    self: Document<Data>,
    actions: {types.Action<Data>},
    oldTransactionId: string?,
    oldTransactionResolved: number?,
    newTransactionInfo: types.TransactionOptions<Data>?
): (patch.PatchResult<Data>, number?)
    local patchResult: patch.PatchResult<Data>
    local newTransactionSucceeded: number? = nil
    local data = self.file:update(function(data: types.DocumentDataInternal<Data>): types.DocumentDataInternal<Data>?
        local internal = data.mailroom
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

            if oldTransactionResolved and oldTransactionResolved > 0 then
                data.data = txInfo.data[oldTransactionResolved]
            end
        end

        patchResult = patch(data.data, actions)

        data.data = patchResult.data

        if newTransactionInfo and patchResult.success then
            Debug.info("Document.patch for", self, "applying new transaction", newTransactionInfo.id)
            local result = patch(data.data, newTransactionInfo.actions)
            Debug.debug("Document.patch new transaction", newTransactionInfo.id, "patch result:", result)

            local dataValues = result.returns

            internal.transaction = {
                id = newTransactionInfo.id,
                failsAfter = newTransactionInfo.failsAfter,
                timeoutAfter = newTransactionInfo.timeoutAfter,
                data = dataValues,
            }
            if result.success then
                newTransactionSucceeded = #newTransactionInfo.actions
            else
                newTransactionSucceeded = result.index - 1
            end
        end

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

    return patchResult, newTransactionSucceeded
end

function Document.__tostring(self: Document<any>): string
    return `Document({self.file})`
end

return Document
