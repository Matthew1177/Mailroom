---
sidebar_position: 3
---
# Transactions
Mailroom provides support for transactions:
```lua
Mailroom:runTransaction({
    [snapshot1] = {
        function(coins)
            return coins + 3
        end
    },
    [snapshot2] = {
        function(coins)
            return coins - 3
        end
    }
})
```
One observation is that two document's data cannot both be accessed at the same time, and this is intentional, as it would make transactions more costly to do than usually necessary. On the off-chance where this is required, assertions can be made in order to ensure that the data has not changed from what is expected:
```lua
local oldCoins1 = snapshot1:get()
local oldCoins2 = snapshot2:get()
Mailroom:runTransaction({
    [snapshot1] = {
        function(coins)
            assert(coins == oldCoins1)
            return coins + 3
        end
    },
    [snapshot2] = {
        function(coins)
            assert(coins == oldCoins2)
            return coins - 3
        end
    }
})
```

## Transaction Stages
Transactions additionally support multiple stages, where if one stage fails, the data as of the previous stage successfully saves:
```lua
Mailroom:runTransaction({
    [snapshot1] = {
        function(coins)
            return coins + 3 -- this would save
        end,
        function(coins)
            error("this stage fails")
        end
    },
    [snapshot2] = {
        function(coins)
            return coins - 3 -- this would save
        end,
        function(coins)
            coins *= 2 -- this would NOT save
        end
    }
})
```