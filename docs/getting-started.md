---
sidebar_position: 2
---
# Getting Started
Mailroom takes a few different approaches from other DataStore abstractions, which will be explored first.

## Interacting with data
In order to interact with data, including reading it, a Snapshot is required:
```lua
local snapshot = Mailroom:createSnapshot(document)

print(snapshot:get()) -- prints the data
```

## Updating data
One concern when operating locklessly is overwriting data saved on another server. Mailroom prevents this issue by taking an approach similar to UpdateAsync:
```lua
snapshot:update(function(data)
    -- data can be updated here and then returned
    return {
        coins = data.coins + 3
    }
end)
```
