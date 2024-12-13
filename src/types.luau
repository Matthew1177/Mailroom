--[=[
    @type LoadTransform (data: unknown?, keyInfo: DataStoreKeyInfo?) -> (Data, Metadata)
    @within Document
]=]
export type LoadTransform<Data, Metadata, Action> = (data: unknown?, keyInfo: DataStoreKeyInfo?) -> (Data, Metadata)

--[=[
    @type SaveTransform (data: Data, metadata: Metadata) -> (any, {[any]: any})
    @within Document
]=]
export type SaveTransform<Data, Metadata, Action> = (data: Data, metadata: Metadata) -> (any, {[any]: any})

--[=[
    @interface DocumentData
    @field data Data
    @field metadata Metadata
    @field userIds {number}
    @within Document
]=]
export type DocumentData<Data, Metadata> = {
    data: Data,
    metadata: Metadata,
    userIds: {number},
}

--[=[
    @type Reducer (DocumentData, Action) -> DocumentData
    @within Document
]=]
export type Reducer<Data, Metadata, Action> = (DocumentData<Data, Metadata>, Action) -> DocumentData<Data, Metadata>

export type TransactionInfo<Data> = {
    id: string,
    -- if resolved and after failsAfter, transaction will be considered failed
    failsAfter: number,
    -- if not resolved after timeoutAfter, transaction will be considered failed
    timeoutAfter: number,
    data: {Data},
}

export type TransactionOptions<Action> = {
    id: string,
    -- if resolved and after failsAfter, transaction will be considered failed
    failsAfter: number,
    -- if not resolved after timeoutAfter, transaction will be considered failed
    timeoutAfter: number,
    actions: {Action}
}

export type DocumentDataInternal<Data, Metadata, Action> = DocumentData<Data, Metadata> & {
    mailroom: {
        transaction: TransactionInfo<Data>?,
    }
}

return nil