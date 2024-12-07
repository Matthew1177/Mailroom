local TransactionManager = require(script.Parent.TransactionManager)
local Document = require(script.Parent.Document)

--[=[
    @class Collection
]=]
local Collection = {}
Collection.__index = Collection

export type Collection<Data, Metadata, Action> = typeof(setmetatable({} :: {
    dataStore: DataStore,
    loadTransform: Document.LoadTransform<Data, Metadata, Action>,
    saveTransform: Document.SaveTransform<Data, Metadata, Action>,
    reducer: Document.Reducer<Data, Metadata, Action>,
    transactionManager: TransactionManager.TransactionManager,
    documents: { [string]: Document.Document<Data, Metadata, Action>? }
}, Collection))

local DOCUMENT_CACHE_METATABLE = {
    __mode = "v"
}

function Collection.new<Data, Metadata, Action>(
    dataStore: DataStore,
    loadTransform: Document.LoadTransform<Data, Metadata, Action>,
    saveTransform: Document.SaveTransform<Data, Metadata, Action>,
    reducer: Document.Reducer<Data, Metadata, Action>,
    transactionManager: TransactionManager.TransactionManager
): Collection<Data, Metadata, Action>
    local self = setmetatable({
        dataStore = dataStore,
        loadTransform = loadTransform,
        saveTransform = saveTransform,
        reducer = reducer,
        transactionManager = transactionManager,
        documents = setmetatable({}, DOCUMENT_CACHE_METATABLE) :: any,
    }, Collection)

    return self
end

--[=[
    Get a document from the collection.

    @method get
    @param key string
    @return Document
    @within Collection
]=]
function Collection.get<Data, Metadata, Action>(
    self: Collection<Data, Metadata, Action>,
    key: string
): Document.Document<Data, Metadata, Action>
    local cached = self.documents[key]

    if not cached then
        local doc = Document.new(self.dataStore, key, self.loadTransform, self.saveTransform, self.reducer, self.transactionManager)
        self.documents[key] = doc
        
        return doc
    end

    return cached
end

return Collection
