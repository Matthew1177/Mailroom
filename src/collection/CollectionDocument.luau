local Document = require(script.Parent.Parent.core.Document)
local CollectionDocument = {}
CollectionDocument.__index = CollectionDocument
CollectionDocument.type = "CollectionDocument"

-- should implement:
-- :fetch
-- :patch
-- :put

--[[
    Remarks:
    - The CollectionDocument class is a wrapper around the Document class.
    - The CollectionDocument class is used to represent a document of a collection
      which is a non-ordered (regular) data store.
    - Transactions should be supported, both between multiple documents and within a single document.
    - Versioning should be supported.
    - Metadata should be supported.
]]

local function collectionLoadTransform(data, keyInfo)
    return {
        data = data,
        userIds = keyInfo.userIds,
        metadata = keyInfo.metadata,
        keyInfo = keyInfo
    }
end

local function collectionSaveTransform(data)
    return data.data, data.userIds, data.metadata
end

function CollectionDocument.new(dataStore, key, reducer)
    local self = setmetatable({
        document = Document.new(dataStore, key, reducer, collectionLoadTransform, collectionSaveTransform)
    }, CollectionDocument)

    self.lock = self.document.lock
    self.reducer = reducer

    return self
end

function CollectionDocument:fetch(options, bypassLock)
    return self.document:fetch(options, bypassLock)
end

function CollectionDocument:patch(actions, options, bypassLock)
    return self.document:patch(actions, options, bypassLock)
end

function CollectionDocument:put(data, options, bypassLock)
    return self.document:put(data, options, bypassLock)
end

return CollectionDocument