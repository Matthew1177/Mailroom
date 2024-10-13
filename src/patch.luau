export type Reducer<Data, Action> = (data: Data, action: Action) -> Data

export type PatchResultSuccess<Data, Action> = {
    success: true,
    data: Data,
}

export type PatchResultFailure<Data, Action> = {
    success: false,
    data: Data,
    error: unknown,
    action: Action,
    index: number,
}

export type PatchResult<Data, Action> = PatchResultSuccess<Data, Action> | PatchResultFailure<Data, Action>

local function patch<Data, Action>(
    data: Data,
    reducer: Reducer<Data, Action>,
    actions: {Action}
): PatchResult<Data, Action>
    local head = data
    for i, action in actions do
        local success, result = pcall(reducer, head, action)
        if not success then
            return {
                success = false,
                data = head,
                error = result,
                action = action,
                index = i,
            }
        end
        head = result
    end

    return {
        success = true,
        data = head
    }
end

return patch