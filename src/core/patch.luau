local TableUtils = require(script.Parent.TableUtils)

--[=[
    @class Patch
]=]

--[=[
    @interface PatchResultSuccess
    @within Patch
    @field success true
    @field data any
]=]
type PatchResultSuccess = {
    success: true,
    data: any,
}

--[=[
    @interface PatchResultFailure
    @within Patch
    @field success false
    @field data any
    @field error any
    @field commit any
    @field index number
]=]
type PatchResultFailure = {
    success: false,
    data: any,
    error: any,
    commit: any,
    index: number,
}

--[=[
    @type PatchResult PatchResultSuccess | PatchResultFailure
    @within Patch
]=]
type PatchResult = PatchResultSuccess | PatchResultFailure

local function patch(data, reducer, commits): PatchResult
    local head = data
    for i, commit in commits do
        local success, result = pcall(reducer, head, commit)
        if not success then
            return {
                success = false,
                error = result,
                commit = commit,
                index = i,
                data = head
            }
        end
        head = result
    end

    return {
        success = true,
        data = TableUtils.deepFreeze(head)
    }
end

return patch