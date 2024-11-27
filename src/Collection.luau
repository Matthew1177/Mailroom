local TransactionManager = require(script.Parent.TransactionManager)
local Document = require(script.Parent.Document)
local types = require(script.Parent.types)

--[=[
    @class Collection
]=]
local Collection = {}
Collection.__index = Collection

local DOCUMENT_CACHE_METATABLE = {
    __mode = "v"
}

export type Collection<Data, Metadata, Action> = typeof(setmetatable({} :: {
    dataStore: DataStore,
    loadTransform: types.LoadTransform<Data, Metadata, Action>,
    saveTransform: types.SaveTransform<Data, Metadata, Action>,
    reducer: types.Reducer<Data, Metadata, Action>,
    transactionManager: TransactionManager.TransactionManager,
    documents: typeof(setmetatable({} :: { [string]: Document.Document<Data, Metadata, Action>? }, DOCUMENT_CACHE_METATABLE))
}, Collection))

function Collection.new<Data, Metadata, Action>(
    dataStore: DataStore,
    loadTransform: types.LoadTransform<Data, Metadata, Action>,
    saveTransform: types.SaveTransform<Data, Metadata, Action>,
    reducer: types.Reducer<Data, Metadata, Action>,
    transactionManager: TransactionManager.TransactionManager
): Collection<Data, Metadata, Action>
    local self = setmetatable({
        dataStore = dataStore,
        loadTransform = loadTransform,
        saveTransform = saveTransform,
        reducer = reducer,
        transactionManager = transactionManager,
        documents = setmetatable({}, DOCUMENT_CACHE_METATABLE),
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
