local File = {}
File.__index = File

export type DataStoreUpdateCallback = (data: unknown?, keyInfo: DataStoreKeyInfo?) -> 
    (any?, {number}?, {[any]: any}?)

export type LoadTransform<T> = (data: unknown?, keyInfo: DataStoreKeyInfo?) -> T
export type SaveTransform<T> = (data: T) -> (any?, {number}?, {[any]: any}?)

export type UpdateTransform<T> = (T) -> T

export type File<T> = typeof(setmetatable(
    {} :: {
        datastore: DataStore,
        key: string,
        loadTransform: LoadTransform<T>,
        saveTransform: SaveTransform<T>,
    },
    File
))

local NO_CACHE_OPTIONS = Instance.new("DataStoreGetOptions")
NO_CACHE_OPTIONS.UseCache = false

function File.new<T>(
    datastore: DataStore,
    key: string,
    loadTransform: LoadTransform<T>,
    saveTransform: SaveTransform<T>
): File<T>
    local self = setmetatable({
        datastore = datastore,
        key = key,
        loadTransform = loadTransform,
        saveTransform = saveTransform,
    }, File)

    return self
end

function File.get<T>(self: File<T>): T
    local data: unknown, keyInfo: DataStoreKeyInfo = self.datastore:GetAsync(self.key, NO_CACHE_OPTIONS)
    return self.loadTransform(data, keyInfo)
end

function File.set<T>(self: File<T>, value: T): string
    local data, userIds, metadata = self.saveTransform(value)

    local setOptions
    if metadata ~= nil then
        setOptions = Instance.new("DataStoreSetOptions")
        setOptions:SetMetadata(metadata)
    end

    return self.datastore:SetAsync(self.key, data, userIds, setOptions)
end

function File.update<T>(self: File<T>, callback: (T) -> T?): T
    local success: boolean, err: any = false, nil
    local updater: DataStoreUpdateCallback = function(data, keyInfo)
        local loadSuccess, loaded = pcall(self.loadTransform, data, keyInfo)
        if not loadSuccess then
            success, err = false, loaded
            return nil
        end

        local updateSuccess, updated = pcall(callback, loaded)
        if not updateSuccess then
            success, err = false, updated
            return nil
        end

        local saveSuccess, toSave, userIds, metadata = pcall(
            self.saveTransform, 
            if updated == nil then loaded else updated
        )
        if not saveSuccess then
            success, err = false, toSave
            return nil
        end

        success = true
        return toSave, userIds, metadata
    end

    local savedData, keyInfo = self.datastore:UpdateAsync(self.key, updater)
    if not success then
        error(err) -- rethrow the error
    end

    return self.loadTransform(savedData, keyInfo)
end

function File.remove<T>(self: File<T>): T
    local data: unknown, keyInfo: DataStoreKeyInfo = self.datastore:RemoveAsync(self.key)

    return self.loadTransform(data, keyInfo)
end

function File.__tostring(self: File<any>): string
    return `File({self.key})`
end

return File