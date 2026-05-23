# [BigQuery API](@id bigquery)

`BigQuery` wraps the [BigQuery REST API](https://cloud.google.com/bigquery/docs/reference/rest).

## Client

```@docs
BigQuery.BQClient
```

### Emulator

Set `BIGQUERY_EMULATOR_HOST=http://localhost:9050` (or any `http://` URL) before
constructing a `BQClient` and it will skip authentication automatically.

## Query

```@docs
BigQuery.query
```

### Result formats

`query` supports two result formats:

| `format` | Return type | Notes |
|----------|-------------|-------|
| `:json` (default) | `Vector{NamedTuple}` | Compatible with all environments including emulators |
| `:arrow` | `Arrow.Table` | Client-side JSON→Arrow conversion; columnar interface |

```julia
# NamedTuple rows
rows = BigQuery.query(bq, "SELECT 1 AS x, 'hi' AS s")
rows[1].x   # 1
rows[1].s   # "hi"

# Arrow.Table (columnar)
tbl = BigQuery.query(bq, "SELECT 1 AS x UNION ALL SELECT 2"; format=:arrow)
collect(tbl.x)   # [1, 2]
```

## Datasets

```@docs
BigQuery.Dataset
BigQuery.list_datasets
BigQuery.get_dataset
BigQuery.create_dataset
BigQuery.delete_dataset
```

## Tables

```@docs
BigQuery.TableFieldSchema
BigQuery.Table
BigQuery.list_tables
BigQuery.get_table
BigQuery.create_table
BigQuery.delete_table
```

## Example

```julia
import BigQuery

bq = BigQuery.BQClient("my-project"; location="US")

# Create a dataset and table
ds = BigQuery.create_dataset(bq, "myds"; location="US")

schema = [
    BigQuery.TableFieldSchema("id",   "INT64";  mode="REQUIRED"),
    BigQuery.TableFieldSchema("name", "STRING"),
]
t = BigQuery.create_table(bq, "myds", "mytable", schema)

# Query it
BigQuery.query(bq, """
    INSERT INTO `my-project.myds.mytable` (id, name)
    VALUES (1, 'Alice'), (2, 'Bob')
""")

rows = BigQuery.query(bq, "SELECT id, name FROM `my-project.myds.mytable` ORDER BY id")
for r in rows
    println(r.id, ": ", r.name)
end

# Clean up
BigQuery.delete_table(bq, "myds", "mytable")
BigQuery.delete_dataset(bq, "myds"; delete_contents=true)
```
