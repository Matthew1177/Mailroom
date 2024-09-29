local TableUtils = {}

local deepFreezeCache = {}
setmetatable(deepFreezeCache, {__mode = "k"})

function TableUtils.tryFreeze(tbl)
    if typeof(tbl) == "table" and not table.isfrozen(tbl) then
        return table.freeze(tbl)
    end
    return tbl
end

function TableUtils.deepFreeze(tbl)
    if typeof(tbl) ~= "table" then
        return tbl -- deepfreeze of non-tables is the same value
    end

    if deepFreezeCache[tbl] then
        return tbl -- already deep frozen
    end

    for i,v in tbl do
        TableUtils.deepFreeze(v)
        TableUtils.deepFreeze(i)
    end

    deepFreezeCache[tbl] = true
    return TableUtils.tryFreeze(tbl)
end

function TableUtils.isDeepFrozen(tbl)
    if typeof(tbl) ~= "table" or deepFreezeCache[tbl] then
        return true
    end

    if not table.isfrozen(tbl) then
        return false
    end

    -- check if all values are deep frozen
    for i,v in tbl do
        if not TableUtils.isDeepFrozen(i) or not TableUtils.isDeepFrozen(v) then
            return false
        end
    end

    deepFreezeCache[tbl] = true
    return true
end

function TableUtils.slice(tbl, start, stop)
    return {unpack(tbl, start, stop)}
end

return TableUtils