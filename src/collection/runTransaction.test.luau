local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataStoreServiceMock = require(ReplicatedStorage.DevPackages.DataStoreServiceMock)
local Promise = require(script.Parent.Parent.Parent.Promise)

local Collection = require(script.Parent.Collection)
local Snapshot = require(script.Parent.Parent.core.Snapshot)
local runTransaction = require(script.Parent.runTransaction)

return function (x)
    local assertEqual = x.assertEqual

    local freeze = table.freeze
    
    local function positiveNumericReducer(state, action)
        local newState = table.clone(state)
        if action == "increment" then
            newState.data += 1
        elseif action == "decrement" then
            newState.data -= 1
        elseif action == "error" then
            error("test error: failed action", 0)
        elseif action == "noop" then
            return newState
        else
            error("unknown action", 0)
        end

        assert(newState.data >= 0, "state should not be negative")

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
        ctx.write(dataStore, "key1", 0)

        local collection = Collection.new(dataStore, positiveNumericReducer)
        ctx.collection = collection

        ctx.document1 = collection:get("key1")
    end)

    x.test("single document transactions should run commits", function(ctx)
        local document1 = ctx.document1

        runTransaction({
            [document1] = freeze {
                "increment",
                "increment",
            },
        }):expect()

        local saved = ctx.read(ctx.collection.dataStore, "key1")
        assertEqual(saved, 2)
    end)

    x.test("single document transactions be atomic", function(ctx)
        local document1 = ctx.document1

        ctx.write(ctx.collection.dataStore, "key1", 1)

        local promise = runTransaction({
            [document1] = {
                "decrement",
                "decrement",
            },
        })

        assertEqual((promise:awaitStatus()), Promise.Status.Rejected)

        local saved = ctx.read(ctx.collection.dataStore, "key1")
        assertEqual(saved, 1)
    end)

    x.test("single document transactions work with snapshots", function(ctx)
        local document1 = ctx.document1

        ctx.write(ctx.collection.dataStore, "key1", 2)
        local snapshot = Snapshot.new(document1)
        snapshot:sync():expect()
        snapshot:commit("increment")

        local promise = runTransaction({
            [snapshot] = {
                "decrement",
                "decrement",
            },
        })

        promise:expect()

        local saved = ctx.read(ctx.collection.dataStore, "key1")
        assertEqual(saved, 1)
        assertEqual(snapshot.base.data, 1)
        assertEqual(#snapshot.commits, 0)
    end)

    x.testFOCUS("single document transactions are atomic with snapshots", function(ctx)
        local document1 = ctx.document1

        ctx.write(ctx.collection.dataStore, "key1", 2)
        local snapshot = Snapshot.new(document1)
        snapshot:sync():expect()
        snapshot:commit("increment")

        ctx.startYield()

        ctx.write(ctx.collection.dataStore, "key1", 0)

        local promise = runTransaction({
            [snapshot] = {
                "decrement",
                "decrement",
                "decrement",
            },
        })

        snapshot:commit("increment")

        ctx.stopYield()

        assertEqual((promise:awaitStatus()), Promise.Status.Rejected)

        local saved = ctx.read(ctx.collection.dataStore, "key1")
        assertEqual(saved, 1)
        assertEqual(snapshot.base.data, 1)
        assertEqual(snapshot.head.data, 2)
        assertEqual(#snapshot.commits, 1)
    end)
end