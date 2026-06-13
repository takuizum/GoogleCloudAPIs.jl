# [BigQuery API](@id bigquery)

`GoogleBigQuery` wraps the [BigQuery REST API](https://cloud.google.com/bigquery/docs/reference/rest).

## Client

```@docs
GoogleBigQuery.BQClient
```

### Emulator

Set `BIGQUERY_EMULATOR_HOST=http://localhost:9050` (or any `http://` URL) before
constructing a `BQClient` and it will skip authentication automatically.

## Query

```@docs
GoogleBigQuery.query
```

### Result formats

`query` supports two result formats:

| `format` | Return type | Notes |
|----------|-------------|-------|
| `:json` (default) | `Vector{NamedTuple}` | Compatible with all environments including emulators |
| `:arrow` | `Arrow.Table` | Client-side JSON→Arrow conversion; columnar interface |

```julia
# NamedTuple rows
rows = GoogleBigQuery.query(bq, "SELECT 1 AS x, 'hi' AS s")
rows[1].x   # 1
rows[1].s   # "hi"

# Arrow.Table (columnar)
tbl = GoogleBigQuery.query(bq, "SELECT 1 AS x UNION ALL SELECT 2"; format=:arrow)
collect(tbl.x)   # [1, 2]
```

## Datasets

```@docs
GoogleBigQuery.Dataset
GoogleBigQuery.list_datasets
GoogleBigQuery.get_dataset
GoogleBigQuery.create_dataset
GoogleBigQuery.delete_dataset
```

## Tables

```@docs
GoogleBigQuery.TableFieldSchema
GoogleBigQuery.Table
GoogleBigQuery.list_tables
GoogleBigQuery.get_table
GoogleBigQuery.create_table
GoogleBigQuery.delete_table
```

## Example

```julia
import GoogleBigQuery

bq = GoogleBigQuery.BQClient("my-project"; location="US")

# Create a dataset and table
ds = GoogleBigQuery.create_dataset(bq, "myds"; location="US")

schema = [
    GoogleBigQuery.TableFieldSchema("id",   "INT64";  mode="REQUIRED"),
    GoogleBigQuery.TableFieldSchema("name", "STRING"),
]
t = GoogleBigQuery.create_table(bq, "myds", "mytable", schema)

# Query it
GoogleBigQuery.query(bq, """
    INSERT INTO `my-project.myds.mytable` (id, name)
    VALUES (1, 'Alice'), (2, 'Bob')
""")

rows = GoogleBigQuery.query(bq, "SELECT id, name FROM `my-project.myds.mytable` ORDER BY id")
for r in rows
    println(r.id, ": ", r.name)
end

# Clean up
GoogleBigQuery.delete_table(bq, "myds", "mytable")
GoogleBigQuery.delete_dataset(bq, "myds"; delete_contents=true)
```
