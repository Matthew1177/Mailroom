local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataStoreServiceMock = require(ReplicatedStorage.DevPackages.DataStoreServiceMock)
local Promise = require(script.Parent.Parent.Parent.Promise)

local Document = require(script.Parent.Document)
local Snapshot = require(script.Parent.Snapshot)

return function (x)
    local assertEqual = x.assertEqual

    local freeze = table.freeze

    local function positiveNumericReducer(state, action)
        local newState = state
        if action == "increment" then
            newState += 1
        elseif action == "decrement" then
            newState -= 1
        elseif action == "error" then
            error("test error: failed action", 0)
        elseif action == "noop" then
            return newState
        else
            error("unknown action", 0)
        end

        assert(newState >= 0, "state should not be negative")

        return newState
    end

    x.beforeEach(function(ctx)
        local dataStoreService = DataStoreServiceMock.manual()
        ctx.dataStoreService = dataStoreService

        dataStoreService.budget:setMaxThrottleQueueSize(0)

        ctx.startYield = function()
            dataStoreService.yield:startYield()
        end

        ctx.stopYield = function()
            dataStoreService.yield:stopYield()
        end

        ctx.dataStore = function(name, scope)
            return dataStoreService:GetDataStore(name, scope)
        end

        ctx.read = function(dataStore, key, data)
            return dataStore.data[key]
        end

        ctx.write = function(dataStore, key, value)
            dataStore:write(key, value)
        end

        local dataStore = ctx.dataStore("test")
        ctx.store = dataStore
        ctx.document = Document.new(dataStore, "key", positiveNumericReducer)
        ctx.write(dataStore, "key", 0)
    end)

    x.test("constructor should set parent", function(ctx)
        local snapshot = Snapshot.new(ctx.document)
        assertEqual(snapshot.parent, ctx.document)
        assertEqual(snapshot.reducer, ctx.document.reducer)
    end)

    x.test("should rebase when empty", function(ctx)
        local snapshot = Snapshot.new(ctx.document)
        snapshot:rebase():expect()

        assertEqual(snapshot.head, 0)
        assertEqual(snapshot.base, 0)
        assertEqual(#snapshot.commits, 0)
    end)

    x.test("should reject bad commits", function(ctx)
        local snapshot = Snapshot.new(ctx.document)
        snapshot:rebase():expect()

        local status = snapshot:commit("decrement"):awaitStatus()
        assertEqual(status, Promise.Status.Rejected)
    end)

    x.test("should commit a valid commit", function(ctx)
        local snapshot = Snapshot.new(ctx.document)
        snapshot:rebase():expect()

        snapshot:commit("increment"):expect()

        assertEqual(snapshot.head, 1)
    end)

    x.test("should rebase after commit", function(ctx)
        local document = ctx.document
        local snapshot = Snapshot.new(document)
        snapshot:rebase():expect()
        
        document:patch(freeze {"increment"}):expect()

        snapshot:commit("increment"):expect()
        snapshot:rebase():expect()

        assertEqual(snapshot.head, 2)
        assertEqual(snapshot.base, 1)
        assertEqual(#snapshot.commits, 1)
    end)

    x.test("should reject when unable to rebase and discardIncompatible is false", function(ctx)
        local document = ctx.document
        ctx.write(ctx.store, "key", 1)
        local snapshot = Snapshot.new(document)
        snapshot:rebase():expect()
        
        snapshot:commit("increment"):expect()
        snapshot:commit("decrement"):expect()
        snapshot:commit("decrement"):expect()

        ctx.write(ctx.store, "key", 0)

        local status, result = snapshot:rebase(false):awaitStatus()

        assertEqual(status, Promise.Status.Rejected)
        assertEqual(result.success, false)
        assertEqual(result.index, 3)
        -- state should be the same as prior
        assertEqual(snapshot.base, 1)
        assertEqual(snapshot.head, 0)
        assertEqual(#snapshot.commits, 3)
    end)

    x.test("should remove incompatible commits on rebase when discarding incompatible", function(ctx)
        local document = ctx.document
        ctx.write(ctx.store, "key", 1)
        local snapshot = Snapshot.new(document)
        snapshot:rebase():expect()
        
        snapshot:commit("increment"):expect()
        snapshot:commit("decrement"):expect()
        snapshot:commit("decrement"):expect()

        ctx.write(ctx.store, "key", 0)

        local status = snapshot:rebase():awaitStatus()

        assertEqual(status, Promise.Status.Resolved)

        assertEqual(snapshot.commits[1], "increment")
        assertEqual(snapshot.commits[2], "decrement")
        assertEqual(snapshot.commits[3], nil)
    end)

    x.test("should rebase when commits occured after starting", function(ctx)
        local document = ctx.document
        ctx.write(ctx.store, "key", 1)
        local snapshot = Snapshot.new(document)
        snapshot:rebase():expect()
        
        ctx.startYield()

        snapshot:commit("increment"):expect()
        snapshot:commit("increment"):expect()
        
        -- change parent and rebase
        ctx.write(ctx.store, "key", 200)
        local promise = snapshot:rebase()
        assertEqual(promise:getStatus(), Promise.Status.Started)

        snapshot:commit("decrement"):expect()

        -- finish first rebase
        ctx.stopYield()

        local status = promise:awaitStatus()
        assertEqual(status, Promise.Status.Resolved)

        assertEqual(snapshot.base, 200)
        assertEqual(snapshot.head, 201)
        assertEqual(#snapshot.commits, 3)
    end)

    x.test("should sync when empty", function(ctx)
        local snapshot = Snapshot.new(ctx.document)
        snapshot:sync():expect()

        assertEqual(snapshot.head, 0)
        assertEqual(snapshot.base, 0)
        assertEqual(#snapshot.commits, 0)
    end)

    x.test("should reject when unable to sync and discardIncompatible is false", function(ctx)
        ctx.write(ctx.store, "key", 1)
        local snapshot = Snapshot.new(ctx.document)
        snapshot:rebase():expect()
        
        snapshot:commit("increment"):expect()
        snapshot:commit("decrement"):expect()
        snapshot:commit("decrement"):expect()

        ctx.write(ctx.store, "key", 0)

        local status, result = snapshot:sync(false):awaitStatus()

        assertEqual(status, Promise.Status.Rejected)
        assertEqual(result.success, false)
        assertEqual(result.index, 3)
        -- state should be the same as prior
        assertEqual(snapshot.base, 1)
        assertEqual(snapshot.head, 0)
        assertEqual(#snapshot.commits, 1)
    end)

    x.test("should remove incompatible commits on sync when discarding incompatible", function(ctx)
        ctx.write(ctx.store, "key", 200)
        local snapshot = Snapshot.new(ctx.document)
        snapshot:rebase():expect()
        
        snapshot:commit("increment"):expect()
        snapshot:commit("decrement"):expect()
        snapshot:commit("decrement"):expect()
        snapshot:commit("decrement"):expect()

        ctx.write(ctx.store, "key", 1)

        local status = snapshot:sync():awaitStatus()

        assertEqual(status, Promise.Status.Resolved)

        assertEqual(#snapshot.commits, 0)
        assertEqual(snapshot.base, 0)
        assertEqual(snapshot.head, 0)
    end)

    x.test("should remove incompatible commits on sync when discarding incompatible if commits added after starting", function(ctx)
        ctx.write(ctx.store, "key", 200)
        local snapshot = Snapshot.new(ctx.document)
        snapshot:rebase():expect()
        
        snapshot:commit("increment"):expect()

        ctx.write(ctx.store, "key", 0)

        ctx.startYield()

        local promise = snapshot:sync()

        snapshot:commit("decrement"):expect()
        snapshot:commit("decrement"):expect()

        ctx.stopYield()

        local status = promise:awaitStatus()

        assertEqual(status, Promise.Status.Resolved)

        assertEqual(#snapshot.commits, 1)
        assertEqual(snapshot.base, 1)
        assertEqual(snapshot.head, 0)
    end)

    x.test("should reject if incompatible commits on sync when not discarding incompatible if commits added after starting", function(ctx)
        ctx.write(ctx.store, "key", 200)
        local snapshot = Snapshot.new(ctx.document)
        snapshot:rebase(false):expect()
        
        snapshot:commit("increment"):expect()

        ctx.write(ctx.store, "key", 0)

        ctx.startYield()

        local promise = snapshot:sync(false)

        snapshot:commit("decrement"):expect()
        snapshot:commit("decrement"):expect()

        ctx.stopYield()

        local status = promise:awaitStatus()

        assertEqual(status, Promise.Status.Rejected)

        assertEqual(#snapshot.commits, 2)
        assertEqual(snapshot.base, 201)
        assertEqual(snapshot.head, 199)
    end)

    x.test("should merge valid commits", function(ctx)
        local document = ctx.document
        local snapshot = Snapshot.new(document)
        snapshot:rebase():expect()

        snapshot:commit("increment"):expect()
        snapshot:commit("increment"):expect()

        snapshot:merge():expect()

        assertEqual(snapshot.base, 2)
        assertEqual(snapshot.head, 2)
        assertEqual(#snapshot.commits, 0)
    end)

    x.test("should keep unmerged commits on merge", function(ctx)
        local document = ctx.document
        local snapshot = Snapshot.new(document)
        snapshot:rebase():expect()

        snapshot:commit("increment"):expect()
        snapshot:commit("increment"):expect()

        ctx.startYield()

        local promise = snapshot:merge()

        snapshot:commit("increment"):expect()

        ctx.stopYield()
        assertEqual(promise:getStatus(), Promise.Status.Resolved)

        assertEqual(snapshot.base, 2)
        assertEqual(snapshot.head, 3)
        assertEqual(#snapshot.commits, 1)
    end)

    x.test("should drop invalid commits on merge when discardIncompatible is true", function(ctx)
        local document = ctx.document
        ctx.write(ctx.store, "key", 1)
        local snapshot = Snapshot.new(document)
        snapshot:rebase():expect()

        snapshot:commit("increment"):expect()
        snapshot:commit("decrement"):expect()
        snapshot:commit("decrement"):expect()

        ctx.write(ctx.store, "key", 0)

        snapshot:merge():expect()

        assertEqual(snapshot.base, 1)
        assertEqual(snapshot.head, 1)
        assertEqual(#snapshot.commits, 0)
    end)
end