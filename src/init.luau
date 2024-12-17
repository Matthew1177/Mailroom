local Collection = require(script.Collection)
local Document = require(script.Document)
local Snapshot = require(script.Snapshot)

export type Document<Data> = Document.Document<Data>
export type Snapshot<Data> = Snapshot.Snapshot<Data>
export type Collection<Data> = Collection.Collection<Data>

return require(script.Mailroom)