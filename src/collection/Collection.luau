local CollectionDocument = require(script.Parent.CollectionDocument)

--[=[
    @class Collection

    Represents a collection of documents in a data store.
]=]
local Collection = {}
Collection.__index = Collection

--[=[
    Constructs a new Collection object.

    @param dataStore DataStore
    @param reducer function
    @return Collection
]=]
function Collection.new(dataStore, reducer)
    local self = setmetatable({}, Collection)

    local wrappedReducer = function(state, action)
        if type(action) == "table" then
            if action.type == "mailroom:atomic" then
                for i,v in action.actions do
                    local success
                    success, state = pcall(reducer, state, v)
                    if not success then error(state) end
                end
            end
            return state
        end
        return reducer(state, action)
    end

    self.dataStore = dataStore
    self.reducer = wrappedReducer

    return self
end

--[=[
    Returns a Document object for the given key.

    @param key string
    @return CollectionDocument
]=]
function Collection:get(key)
    return CollectionDocument.new(self.dataStore, key, self.reducer)
end

function Collection:__tostring()
    return "Collection(" .. tostring(self.dataStore) .. ")"
end

return Collection
