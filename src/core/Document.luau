local DataStoreUtils = require(script.Parent.DataStoreUtils)
local Lock = require(script.Parent.Lock)
local TableUtils = require(script.Parent.TableUtils)
local patch = require(script.Parent.patch)

--[=[
    @class Document

    Represents a document in a data store. Construct using [Collection:get].

    :::warning

    This class is not meant to be interacted with directly. Instead,
    construct a [Snapshot] to interact with documents.

    :::
]=]
local Document = {}
Document.__index = Document
Document.type = "Document"

function defaultLoadTransform(data, keyInfo)
    return data
end

function defaultSaveTransform(data)
    return data
end

function Document.new(dataStore, key, reducer, loadTransform, saveTransform)
    local self = setmetatable({}, Document)

    self.dataStore = dataStore
    self.key = key
    self.reducer = reducer
    self.lock = Lock.new()

    self.loadTransform = loadTransform or defaultLoadTransform
    self.saveTransform = saveTransform or defaultSaveTransform

    return self
end

function Document:_fetch(options)
    return DataStoreUtils.get(self.dataStore, self.key, options)
        :andThen(function(data, keyInfo)
            return self.loadTransform(data, keyInfo)
        end)
end

function Document:_patch(commits, options)
    assert(TableUtils.isDeepFrozen(commits), "Commits must be frozen")

    local result
    return DataStoreUtils.update(self.dataStore, self.key, function(data, keyInfo)
        local loaded = self.loadTransform(data, keyInfo)
        result = patch(loaded, self.reducer, commits)
    
        return self.saveTransform(result.data)
    end, options):andThen(function()
        return result
    end)
end

function Document:_put(data, options)
    assert(TableUtils.isDeepFrozen(data), "Data must be frozen")
    
    local dataToSave, userIds, metadata = self.saveTransform(data, nil)
    local setOptions = Instance.new("DataStoreSetOptions")
    setOptions:SetMetadata(metadata)
    setOptions:SetUserIds(userIds)
    return DataStoreUtils.set(self.dataStore, self.key, dataToSave, setOptions, options)
        :andThenReturn()
end
    
--[=[
    Returns a resolved promise of the Document's data.

    @param options DataStoreAPIOptions?
    @return Promise<any>
]=]
function Document:fetch(options, bypassLock)
    if bypassLock then
        return self:_fetch(options)
    end

    return self.lock:whileLocked(function()
        return self:_fetch(options)
    end)
end

--[=[
    Applies the given commits to the Document. Returns a promise that resolves
    with the result of the patch operation.

    @param commits {any}
    @param options DataStoreAPIOptions?
    @return Promise<PatchResult>
]=]
function Document:patch(commits, options, bypassLock)
    if bypassLock then
        return self:_patch(commits, options)
    end

    return self.lock:whileLocked(function()
        return self:_patch(commits, options)
    end)
end

--[=[
    Replaces the Document's data with the given data.

    @param data any
    @param options DataStoreAPIOptions?
    @return Promise<void>
]=]
function Document:put(data, options, bypassLock)
    if bypassLock then
        return self:_put(data, options)
    end
    
    return self.lock:whileLocked(function()
        return self:_put(data, options)
    end)
end

function Document:__tostring()
    return "Document(" .. tostring(self.dataStore) .. ", " .. tostring(self.key) .. ")"
end


return Document
