"use strict";(self.webpackChunkdocs=self.webpackChunkdocs||[]).push([[312],{6960:e=>{e.exports=JSON.parse('{"functions":[{"name":"new","desc":"Construct a new Mailroom instance. In general, only one Mailroom instance should be created.","params":[{"name":"options","desc":"","lua_type":"MailroomOptions?"}],"returns":[{"desc":"","lua_type":"Mailroom"}],"function_type":"static","source":{"line":36,"path":"src/Mailroom.luau"}},{"name":"runTransaction","desc":"Run a transaction on a set of snapshots and documents.\\n\\n`actionsMap` is a map of snapshots or documents to an array of Actions to run on them. The actions are applied in the order they are given.","params":[{"name":"actionsMap","desc":"","lua_type":"{[Snapshot | Document]: {Action}}"}],"returns":[{"desc":"","lua_type":"number"}],"function_type":"method","yields":true,"source":{"line":167,"path":"src/Mailroom.luau"}},{"name":"createCollection","desc":"Create a new collection.","params":[{"name":"dataStore","desc":"","lua_type":"DataStore"},{"name":"loadTransform","desc":"","lua_type":"LoadTransform"},{"name":"saveTransform","desc":"","lua_type":"SaveTransform"}],"returns":[{"desc":"","lua_type":"Collection"}],"function_type":"method","source":{"line":230,"path":"src/Mailroom.luau"}},{"name":"createSnapshot","desc":"Create a new snapshot with a document or another snapshot as parent.","params":[{"name":"parent","desc":"","lua_type":"Document | Snapshot"},{"name":"options?","desc":"","lua_type":"{updateCallback: () -> ()?}"}],"returns":[{"desc":"","lua_type":"Snapshot"}],"function_type":"method","yields":true,"source":{"line":267,"path":"src/Mailroom.luau"}}],"properties":[],"types":[],"name":"Mailroom","desc":"","source":{"line":18,"path":"src/Mailroom.luau"}}')}}]);