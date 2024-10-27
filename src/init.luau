local Collection = require(script.Collection)
local Document = require(script.Document)
local Snapshot = require(script.Snapshot)

export type Document<Data,Metadata,Action> = Document.Document<Data,Metadata,Action>
export type Snapshot<Data,Metadata,Action> = Snapshot.Snapshot<Data,Metadata,Action>
export type Collection<Data,Metadata,Action> = Collection.Collection<Data,Metadata,Action>

return require(script.Mailroom)