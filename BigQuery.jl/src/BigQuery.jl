module BigQuery

using Arrow
using Base64
using HTTP
using JSON3
using StructTypes
using URIs

import GoogleAuth
import GoogleApiCore

export BQClient, query
export Dataset, list_datasets, get_dataset, create_dataset, delete_dataset
export Table, TableFieldSchema, list_tables, get_table, create_table, delete_table

include("results.jl")
include("client.jl")
include("jobs.jl")
include("datasets.jl")
include("tables.jl")

end # module BigQuery
