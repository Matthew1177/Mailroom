local function deepFreeze<T>(x: T): T
    if type(x) == "table" then
        if not table.isfrozen then
            table.freeze(x)
        end

        for k, v in pairs(x :: any) do
            deepFreeze(k)
            deepFreeze(v)
        end
    end
    return x
end

return deepFreeze