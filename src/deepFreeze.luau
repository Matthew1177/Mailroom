--!nocheck
-- Checking is disabled as it fails on the `table.isfrozen` function
local function deepFreeze<T>(x: T): T
    if type(x) == "table" then
        if not table.isfrozen(x) then
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