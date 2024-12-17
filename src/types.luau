--[=[
    @type LoadTransform (data: unknown?) -> Data
    @within Document
]=]
export type LoadTransform<Data> = (data: unknown?) -> Data

--[=[
    @type SaveTransform (data: Data) -> any
    @within Document
]=]
export type SaveTransform<Data> = (data: Data) -> any

--[=[
    @type Action (data: Data) -> Data?
    @within Document
]=]
export type Action<Data> = (Data) -> Data?

export type TransactionInfo<Data> = {
    id: string,
    -- if resolved and after failsAfter, transaction will be considered failed
    failsAfter: number,
    -- if not resolved after timeoutAfter, transaction will be considered failed
    timeoutAfter: number,
    data: {Data},
}

export type TransactionOptions<Data> = {
    id: string,
    -- if resolved and after failsAfter, transaction will be considered failed
    failsAfter: number,
    -- if not resolved after timeoutAfter, transaction will be considered failed
    timeoutAfter: number,
    actions: {Action<Data>}
}

export type DocumentDataInternal<Data> = {
    data: Data,
    mailroom: {
        transaction: TransactionInfo<Data>?,
    }
}

return nil