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

export type Collection<Data> = typeof(setmetatable({} :: {
    dataStore: DataStore,
    loadTransform: types.LoadTransform<Data>,
    saveTransform: types.SaveTransform<Data>,
    transactionManager: TransactionManager.TransactionManager,
    documents: typeof(setmetatable({} :: { [string]: Document.Document<Data>? }, DOCUMENT_CACHE_METATABLE))
}, Collection))

function Collection.new<Data>(
    dataStore: DataStore,
    loadTransform: types.LoadTransform<Data>,
    saveTransform: types.SaveTransform<Data>,
    transactionManager: TransactionManager.TransactionManager
): Collection<Data>
    local self = setmetatable({
        dataStore = dataStore,
        loadTransform = loadTransform,
        saveTransform = saveTransform,
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
function Collection.get<Data>(
    self: Collection<Data>,
    key: string
): Document.Document<Data>
    local cached = self.documents[key]

    if not cached then
        local doc = Document.new(self.dataStore, key, self.loadTransform, self.saveTransform, self.transactionManager)
        self.documents[key] = doc
        
        return doc
    end

    return cached
end

return Collection
