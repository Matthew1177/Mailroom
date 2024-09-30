local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Midori = require(ReplicatedStorage.DevPackages.Midori)

Midori.runTests(ReplicatedStorage.Packages.Mailroom, {
    timeoutWarningDelay = 6,
    concurrent = true,
})