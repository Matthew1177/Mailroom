local TableUtils = require(script.Parent.TableUtils)
local Promise = require(script.Parent.Parent.Parent.Promise)
local patch = require(script.Parent.patch)

--[=[
    @class Snapshot

    Represents a snapshot of a document. Construct using 
    [Mailroom.newSnapshot].
]=]
local Snapshot = {}
Snapshot.__index = Snapshot
Snapshot.type = "Snapshot"

function Snapshot.new(parent)
    local self = setmetatable({}, Snapshot)

    self.parent = parent
    self.reducer = parent.reducer
    self.base = nil
    self.head = nil
    self.commits = {}

    return self
end

function Snapshot.fromExisting(snapshot)
    local self = setmetatable({}, Snapshot)

    self.parent = snapshot.parent
    self.reducer = snapshot.reducer
    self.base = snapshot.base -- immutable
    self.head = snapshot.head -- immutable
    self.commits = table.clone(snapshot.commits)

    return self
end

-- // Begin Document Compat Layer

--[=[
    Returns a resolved promise of Snapshot's head.

    :::note

    This function is a compatibility layer for the [Document] class. It is not
    recommended to use this function directly. Instead, use the
    [Snapshot:getHead]. 

    :::

    @return Promise<any>
]=]
function Snapshot:fetch()
    return Promise.resolve(self.head)
end

--[=[
    Applies the given commits to the Snapshot. Returns an already resolved
    promise.

    :::note

    This function is a compatibility layer for the [Document] class. It is not
    recommended to use this function directly. Instead, use the
    [Snapshot:commit] function.

    :::

    @param commits table
    @return Promise<PatchResult>
]=]
function Snapshot:patch(commits)
    local result = patch(self.head, self.reducer, commits)

    self.head = result.data
    -- add to commits
    for i, commit in ipairs(commits) do
        if not result.success and i == result.index then
            break
        end
        table.insert(self.commits, commit)
    end

    return Promise.resolve(result)
end

--[=[
    Sets the Snapshot's base and head and clears its commits. Returns a
    resolved promise.

    :::note

    This function is a compatibility layer for the [Document] class. It is not
    recommended to use this function directly. Instead, use the
    [Snapshot:commit] function.

    :::

    @param data any
    @return Promise<void>
]=]
function Snapshot:put(data)
    self.base = data
    self.head = data
    self.commits = {}

    return Promise.resolve()
end

-- // End Document Compat Layer

--[=[
    Commits the given commit to the Snapshot. Returns an already resolved or
    rejected promise.

    @param commit any
    @return Promise<void>
]=]
function Snapshot:commit(commit)
    local success, result = pcall(self.reducer, self.head, commit)
    if not success then
        return Promise.reject(result)
    end

    self.head = result
    -- freeze commit
    TableUtils.deepFreeze(commit)
    table.insert(self.commits, commit)

    return Promise.resolve()
end

-- // Utility functions

--[=[
    Returns the Snapshot's head.

    @return any
]=]
function Snapshot:getHead()
    return self.head
end

--[=[
    Resets the Snapshot's head to its base and clears its commits.

    @return void
]=]
function Snapshot:resetHead()
    self.head = self.base
    self.commits = {}
end

--[=[
    Returns the Snapshot's base.

    @return any
]=]
function Snapshot:getBase()
    return self.base
end

--[=[
    Sets the Snapshot's base and head. If the base is incompatible with the
    Snapshot's commits, the incompatible commits are discarded if 
    `discardIncompatible` is true. Returns a boolean indicating whether the 
    base was set successfully and the result of the patch operation, and the 
    [PatchResult].

    @param base any
    @param discardIncompatible boolean
    @return (boolean, PatchResult)
]=]
function Snapshot:setBase(base, discardIncompatible)
    discardIncompatible = if discardIncompatible == nil then true else discardIncompatible

    local result = patch(base, self.reducer, self.commits)
    if not result.success and not discardIncompatible then
        return false, result
    end

    self.base = base
    self.head = result.data
    if not result.success then
        -- remove incompatible commits
        self.commits = TableUtils.slice(self.commits, 1, result.index - 1)
    end

    return true, result
end

--[=[
    Returns a frozen copy of the Snapshot's commits.

    @return table 
]=]
function Snapshot:getCommits()
    return table.freeze(table.clone(self.commits))
end

function Snapshot:squashCommits(numberToSquash)
    local result = patch(self.base, self.reducer, TableUtils.slice(self.commits, 1, numberToSquash))
    assert(result.success, "Squash failed -- reducer must have a side effect")

    self.base = result.data
    self.commits = TableUtils.slice(self.commits, numberToSquash + 1)
end

function Snapshot:squashAndSetBase(numberToSquash, base, discardIncompatible)
    discardIncompatible = if discardIncompatible == nil then true else discardIncompatible
    -- 1. squash commits (silently)
    local commits = TableUtils.slice(self.commits, numberToSquash + 1)
    -- 2. set base
    local result = patch(base, self.reducer, commits)
    if not result.success and not discardIncompatible then
        return false, result
    end

    self.base = base
    self.head = result.data
    if not result.success then
        -- remove incompatible commits
        commits = TableUtils.slice(commits, 1, result.index - 1)
    end
    
    self.commits = commits -- set new commits

    return true, result
end

-- // End Utility functions

--[=[
    Merges the Snapshot's commits with the parent. If `discardIncompatible` is
    true, incompatible commits are discarded. Returns a promise that resolves
    when the merge is complete. If the merge fails, the promise is rejected
    with the [PatchResult].

    :::warning

    Does not update the Snapshot's head. Use [Snapshot:sync] to update the
    Snapshot's head and merge.

    :::

    @param discardIncompatible boolean
    @param options any?
    @return Promise<void, PatchResult>
]=]
function Snapshot:merge(discardIncompatible, options, bypassLock)
    discardIncompatible = if discardIncompatible == nil then true else discardIncompatible
    
    if #self.commits == 0 then
        return Promise.resolve()
    end
    
    local commits = self:getCommits()
    return self.parent:patch(commits, options, bypassLock)
        :andThen(function(result)
            if result.success then
                self:squashCommits(#commits) -- success! squash all commits
            elseif discardIncompatible then
                self:squashCommits(result.index - 1) -- squash compatible commits
                self:resetHead() -- discard incompatible commits
            else
                self:squashCommits(result.index - 1) -- squash compatible commits
                return Promise.reject(result) -- reject if incompatible
            end

            return Promise.resolve()
        end)
end

--[=[
    Rebases the Snapshot to the parent. If `discardIncompatible` is true,
    incompatible commits are discarded. Returns a promise that resolves when
    the rebase is complete. If the rebase fails, the promise is rejected with
    the [PatchResult].

    @param discardIncompatible boolean
    @param options any?
    @return Promise<void, PatchResult>
]=]
function Snapshot:rebase(discardIncompatible, options, bypassLock)
    discardIncompatible = if discardIncompatible == nil then true else discardIncompatible
    return self.parent:fetch(options, bypassLock)
        :andThen(function(newBase)
            local didSucceed, result = self:setBase(newBase, discardIncompatible)

            if not didSucceed then -- base was NOT set
                return Promise.reject(result)
            end

            return Promise.resolve()
        end)
end

--[=[
    Syncs the Snapshot with the parent. If `discardIncompatible` is true,
    incompatible commits are discarded. Returns a promise that resolves when
    the sync is complete. If the sync fails, the promise is rejected with the
    [PatchResult].

    @param discardIncompatible boolean
    @param options any?
    @return Promise<void, PatchResult>
]=]
function Snapshot:sync(discardIncompatible, options, bypassLock)
    discardIncompatible = if discardIncompatible == nil then true else discardIncompatible

    if #self.commits == 0 then
        return self:rebase(discardIncompatible, options, bypassLock)
    end

    local commits = self:getCommits()
    return self.parent:patch(commits, options, bypassLock)
        :andThen(function(result)
            if result.success or discardIncompatible then
                local didSucceed, newResult = self:squashAndSetBase(#commits, result.data, discardIncompatible)
                -- only can fail if discardIncompatible is false
                if not didSucceed then
                    -- we should still squash the compatible commits
                    self:squashCommits(#commits)
                    return Promise.reject(newResult)
                end

                return Promise.resolve()
            else
                -- if the patch failed, and not discarding incompatible commits, reject
                -- we should still squash the compatible commits
                self:squashCommits(result.index - 1)
                return Promise.reject(result)
            end
        end)
end

function Snapshot:__tostring()
    return "Snapshot(" .. tostring(self.parent) .. ")"
end


return Snapshot
