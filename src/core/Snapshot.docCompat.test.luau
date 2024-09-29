local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataStoreServiceMock = require(ReplicatedStorage.DevPackages.DataStoreServiceMock)

local Document = require(script.Parent.Document)
local Snapshot = require(script.Parent.Snapshot)

return function (x)
    local assertEqual = x.assertEqual

    local freeze = table.freeze
    
    local function numericReducer(state, action)
        if action == "increment" then
            return state + 1
        elseif action == "error" then
            error("test error: failed action", 0)
        else
            error("unknown action", 0)
        end
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
        ctx.document = Document.new(dataStore, "key", numericReducer)
        ctx.write(dataStore, "key", 0)

        local snapshot = Snapshot.new(ctx.document)
        snapshot:sync():expect()
        ctx.snapshot = snapshot
    end)

    x.test("should save one commit", function(ctx)
        local snapshot = ctx.snapshot

        snapshot:patch(freeze {"increment"}):expect()

        local saved = snapshot.head
        assertEqual(saved, 1)
    end)

    x.test("should save multiple commits", function(ctx)
        local snapshot = ctx.snapshot

        snapshot:patch(freeze {"increment", "increment", "increment"}):expect()

        local saved = snapshot.head
        assertEqual(saved, 3)
    end)

    x.test("should read saved data", function(ctx)
        local snapshot = ctx.snapshot

        local saved = snapshot:fetch():expect()
        assertEqual(saved, 0)
    end)

    x.test("should stop processing commits after one fails", function(ctx)
        local snapshot = ctx.snapshot

        local result = snapshot:patch(freeze {"increment", "error", "decrement"}):expect()

        assertEqual(result.data, 1)
        assertEqual(result.success, false)

        local saved = snapshot.head

        assertEqual(saved, 1)
    end)

    x.test("should overwrite data on put", function(ctx)
        local snapshot = ctx.snapshot

        snapshot:commit("increment"):expect()
        assertEqual(#snapshot.commits, 1)
        assertEqual(snapshot.base, 0)
        assertEqual(snapshot.head, 1)

        snapshot:put(5):expect()

        assertEqual(snapshot.head, 5)
        assertEqual(snapshot.base, 5)
        assertEqual(#snapshot.commits, 0)
    end)
end