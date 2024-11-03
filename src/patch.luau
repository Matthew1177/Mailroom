local deepFreeze = require(script.Parent.deepFreeze)

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
    actionGroup: {Action},
    index: number,
}

export type PatchResult<Data, Action> = PatchResultSuccess<Data, Action> | PatchResultFailure<Data, Action>

local function patch<Data, Action>(
    data: Data,
    reducer: Reducer<Data, Action>,
    actions: {{Action}}
): PatchResult<Data, Action>
    local head = deepFreeze(data)
    for i, actionGroup in actions do
        local newHead = head
        for j, action in actionGroup do
            local success, result = pcall(reducer, newHead, action)

            if not success then
                return {
                    success = false,
                    data = head,
                    error = result,
                    action = action,
                    actionGroup = actionGroup,
                    index = i,
                }
            end
            
            newHead = deepFreeze(result)
        end
        head = newHead
    end

    return {
        success = true,
        data = deepFreeze(head)
    }
end

return patch