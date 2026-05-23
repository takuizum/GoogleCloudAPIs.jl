# BigQuery.jl


[![CI](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml) [![codecov](https://codecov.io/gh/takuizum/GoogleCloudAPIs.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/takuizum/GoogleCloudAPIs.jl) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)

BigQuery REST API client for Julia. Part of the [GoogleCloudAPIs.jl](../README.md) monorepo.

## Features

- `query(client, sql)` — execute SQL via `jobs.query`, follow `pageToken` automatically.
- Dataset and table CRUD (`list_datasets`, `create_table`, ...).
- Arrow.Table output via client-side conversion (`format=:arrow`).
- Emulator support via `BIGQUERY_EMULATOR_HOST` (e.g. `goccy/bigquery-emulator`).
- Built on top of `GoogleAuth.jl` + `GoogleApiCore.jl` (shared auth + retry).

## Quick start

```julia
using BigQuery

client = BQClient("your-project-id")             # uses ADC
# client = BQClient("your-project-id"; location="asia-northeast1")

rows = query(client, "SELECT 1 AS num, 'hi' AS msg")
# 1-element Vector{NamedTuple}: (num = 1, msg = "hi")

# Arrow.Table output
tbl = query(client, "SELECT name, SUM(number) total
             FROM `bigquery-public-data.usa_names.usa_1910_2013`
             WHERE state='CA' GROUP BY name LIMIT 100";
            format=:arrow)
collect(tbl.name)
```

## Datasets and tables

```julia
# Create
ds  = create_dataset(client, "my_dataset"; location="US")
tbl = create_table(client, "my_dataset", "events", [
    TableFieldSchema("id",        "INT64";  mode="REQUIRED"),
    TableFieldSchema("name",      "STRING"),
    TableFieldSchema("timestamp", "TIMESTAMP"),
])

# List
for d in list_datasets(client)
    println(d.dataset_id)
end
for t in list_tables(client, "my_dataset")
    println(t.table_id)
end

# Delete
delete_table(client, "my_dataset", "events")
delete_dataset(client, "my_dataset"; delete_contents=true)
```

## Arrow note

The BigQuery REST API **does not** expose true Arrow IPC streams (despite some documentation hinting at `formatOptions.useArrowDataFormat`). `format=:arrow` here is a client-side convenience: the REST JSON response is parsed and converted to `Arrow.Table` before returning.

True zero-copy Arrow streaming requires the BigQuery Storage Read API, which is gRPC-only and slated for a future `GoogleBigQueryStorage.jl` package.

## License

[MIT](LICENSE)
