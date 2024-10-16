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

export type FileOptions<T> = {
    datastore: DataStore,
    key: string,
    loadTransform: LoadTransform<T>,
    saveTransform: SaveTransform<T>,
}

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

function File.getAsync<T>(self: File<T>): T
    local data: unknown, keyInfo: DataStoreKeyInfo = self.datastore:GetAsync(self.key)
    return self.loadTransform(data, keyInfo)
end

function File.setAsync<T>(self: File<T>, value: T): string
    local data, userIds, metadata = self.saveTransform(value)

    local setOptions
    if metadata ~= nil then
        setOptions = Instance.new("DataStoreSetOptions")
        setOptions:SetMetadata(metadata)
    end

    return self.datastore:SetAsync(self.key, data, userIds, setOptions)
end

function File.updateAsync<T>(self: File<T>, callback: (T) -> T?): T
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

function File.removeAsync<T>(self: File<T>): T
    local data: unknown, keyInfo: DataStoreKeyInfo = self.datastore:RemoveAsync(self.key)

    return self.loadTransform(data, keyInfo)
end

function File.__tostring(self: File<any>): string
    return `File({self.key})`
end

return File