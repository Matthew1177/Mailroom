local deepFreeze = require(script.Parent.deepFreeze)
local types = require(script.Parent.types)

export type Reducer<Data, Action> = (data: Data, action: Action) -> Data
export type PatchResultSuccess<Data> = {
    success: true,
    data: Data,
    returns: {Data}
}

export type PatchResultFailure<Data> = {
    success: false,
    data: Data,
    error: unknown,
    action: types.Action<Data>,
    index: number,
    returns: {Data}
}

export type PatchResult<Data> = PatchResultSuccess<Data> | PatchResultFailure<Data>

local function patch<Data>(
    data: Data,
    actions: {types.Action<Data>},
    stopAfter: number?
): PatchResult<Data>
    local head = deepFreeze(data)
    local returns = {} :: {Data}
    for i, action in actions do
        if stopAfter and i > stopAfter then
            break
        end

        local success, result = pcall(action, head)

        if not success then
            return {
                success = false,
                data = head,
                error = result,
                action = action,
                index = i,
                returns = returns,
            }
        end

        head = if result == nil then head else deepFreeze(result)
        table.insert(returns, head)
    end

    return {
        success = true,
        data = deepFreeze(head),
        returns = returns,
    }
end

return patch