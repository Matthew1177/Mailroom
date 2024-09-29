local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataStoreServiceMock = require(ReplicatedStorage.DevPackages.DataStoreServiceMock)
local Promise = require(script.Parent.Parent.Parent.Promise)

local Document = require(script.Parent.Document)

return function (x)
    local assertEqual = x.assertEqual
    local shouldThrow = x.shouldThrow

    local freeze = table.freeze

    local function noop() end
    
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
    end)

    x.test("should save one commit", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)

        document:patch(freeze {"increment"}):expect()

        local saved = ctx.read(store, "key")
        assertEqual(saved, 1)
    end)

    x.test("should save multiple commits", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)

        document:patch(freeze {"increment", "increment", "increment"}):expect()

        local saved = ctx.read(store, "key")
        assertEqual(saved, 3)
    end)

    x.test("should read saved data", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", "value")
        local document = Document.new(store, "key", noop)

        local saved = document:fetch():expect()
        assertEqual(saved, "value")
    end)

    x.test("should not read until lock is released", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)
        local lockId = document.lock:lock():expect()

        local promise = document:fetch()

        assertEqual(promise:getStatus(), Promise.Status.Started)
        document.lock:unlock(lockId)
        assertEqual(promise:getStatus(), Promise.Status.Resolved)
    end)

    x.test("should lock while reading", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)

        ctx.startYield()
        
        document:fetch()
        
        assert(document.lock:isLocked(), "should be locked")

        ctx.stopYield()

        assert(not document.lock:isLocked(), "should not be locked")
    end)

    x.test("should not write until lock is released", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)
        local lockId = document.lock:lock():expect()

        local promise = document:patch(freeze {"increment"})

        assertEqual(promise:getStatus(), Promise.Status.Started)

        document.lock:unlock(lockId)

        assertEqual(promise:getStatus(), Promise.Status.Resolved)
    end)

    x.test("should lock while writing", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)

        ctx.startYield()
        
        document:patch(freeze {"increment"})
        
        assert(document.lock:isLocked(), "should be locked")

        ctx.stopYield()

        assert(not document.lock:isLocked(), "should not be locked")
    end)

    x.test("should stop processing commits after one fails", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)

        local result = document:patch(freeze {"increment", "error", "decrement"}):expect()

        assertEqual(result.data, 1)
        assertEqual(result.success, false)

        local saved = ctx.read(store, "key")

        assertEqual(saved, 1)
        assertEqual(document.lock:isLocked(), false)
    end)

    x.test("patch should throw if commits are not deep frozen", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", noop)
    
        shouldThrow(function()
            document:patch({"test"}):expect()
        end)

        shouldThrow(function()
            document:patch(freeze { x = {} }):expect()
        end)

        shouldThrow(function()
            document:patch({ x = {} }):expect()
        end)

        shouldThrow(function()
            document:patch({ 1, 2, {}, 3 }):expect()
        end)

        shouldThrow(function()
            document:patch({ nil, nil, {} }):expect()
        end)
    end)

    x.testSKIP("put should throw if data is not deep frozen", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", noop)
    
        shouldThrow(function()
            document:put({"test"})
        end)

        shouldThrow(function()
            document:put(freeze { x = {} })
        end)

        shouldThrow(function()
            document:put({ x = {} })
        end)

        shouldThrow(function()
            document:put({ 1, 2, {}, 3 })
        end)

        shouldThrow(function()
            document:put({ nil, nil, {} })
        end)
    end)

    x.testSKIP("should overwrite data on put", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)

        document:put(5):expect()

        local saved = ctx.read(store, "key")
        assertEqual(saved, 5)
    end)

    x.testSKIP("should not put until lock is released", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)
        local lockId = document.lock:lock():expect()

        local promise = document:put(5)

        assertEqual(promise:getStatus(), Promise.Status.Started)
        document.lock:unlock(lockId)
        assertEqual(promise:getStatus(), Promise.Status.Resolved)
    end)

    x.testSKIP("should lock during put", function(ctx)
        local store = ctx.dataStore("test")
        ctx.write(store, "key", 0)
        local document = Document.new(store, "key", numericReducer)

        ctx.startYield()
        
        document:put(5)
        
        assert(document.lock:isLocked(), "should be locked")

        ctx.stopYield()

        assert(not document.lock:isLocked(), "should not be locked")
    end)
end