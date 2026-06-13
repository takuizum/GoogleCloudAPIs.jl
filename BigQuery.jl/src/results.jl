"""
    _rows_to_arrow(rows) -> Arrow.Table

Convert a `Vector{NamedTuple}` returned by the REST JSON path into an
`Arrow.Table` for a columnar in-memory interface.

This is a client-side conversion, not a zero-copy wire-format read.
True zero-copy Arrow streaming requires the BigQuery Storage Read API (gRPC),
which is not implemented in v0.1.
"""
function _rows_to_arrow(rows::Vector{<:NamedTuple})
    isempty(rows) && return Arrow.Table(UInt8[])
    buf = IOBuffer()
    Arrow.write(buf, rows)
    return Arrow.Table(take!(buf))
end

"""
    BQField

One column of a BigQuery result schema: `name`, canonical uppercase `type`
(e.g. `"TIMESTAMP"`), `mode` (`"NULLABLE"`, `"REQUIRED"` or `"REPEATED"`),
and `fields` holding the nested schema for `RECORD`/`STRUCT` columns.
"""
struct BQField
    name::Symbol
    type::String
    mode::String
    fields::Vector{BQField}
end

BQField(name, type; mode="NULLABLE", fields=BQField[]) =
    BQField(Symbol(name), uppercase(String(type)), String(mode),
            collect(BQField, fields))

"""
Convert a JSON-formatted BigQuery row to a NamedTuple.

`fields` describes the columns in order. Values come from `row["f"]` as
`[{"v": value}, ...]`; `RECORD` values recurse with the nested field list.
"""
function _row_to_namedtuple(row::AbstractDict, fields::Vector{BQField})
    fs = row["f"]
    names = ntuple(i -> fields[i].name, length(fields))
    values = ntuple(length(fields)) do i
        _coerce_value(fs[i]["v"], fields[i])
    end
    return NamedTuple{names}(values)
end

"""
    _coerce_value(raw, field::BQField)

Convert a raw REST value into a Julia value according to the column type:

| BigQuery type | Julia type |
|---|---|
| `INT64`/`INTEGER` | `Int64` |
| `FLOAT64`/`FLOAT` | `Float64` |
| `BOOL`/`BOOLEAN` | `Bool` |
| `TIMESTAMP` | `Dates.DateTime` (UTC; millisecond precision, µs truncated) |
| `DATE` | `Dates.Date` |
| `DATETIME` | `Dates.DateTime` (millisecond precision, µs truncated) |
| `TIME` | `Dates.Time` (microsecond precision) |
| `BYTES` | `Vector{UInt8}` (base64-decoded) |
| `RECORD`/`STRUCT` | nested `NamedTuple` |
| `NUMERIC`/`BIGNUMERIC` | `String` (kept lossless — `Float64` would corrupt) |
| anything else (`STRING`, `GEOGRAPHY`, `JSON`, …) | `String` |

`REPEATED` columns become a `Vector` of the element type. SQL `NULL` becomes
`missing`.
"""
function _coerce_value(raw, field::BQField)
    raw === nothing && return missing
    if field.mode == "REPEATED"
        # raw is [{"v": element}, ...]; BigQuery arrays cannot contain NULL.
        return [_coerce_scalar(el["v"], field) for el in raw]
    end
    return _coerce_scalar(raw, field)
end

# Backwards-compatible helper for scalar coercion by bare type tag.
_coerce_value(raw, type_str::AbstractString) =
    _coerce_value(raw, BQField(:_, type_str))

function _coerce_scalar(raw, field::BQField)
    raw === nothing && return missing
    t = field.type
    if t == "INTEGER" || t == "INT64"
        return parse(Int64, raw)
    elseif t == "FLOAT" || t == "FLOAT64"
        return parse(Float64, raw)
    elseif t == "BOOLEAN" || t == "BOOL"
        return parse(Bool, raw)
    elseif t == "TIMESTAMP"
        # REST returns epoch seconds as a decimal string, possibly in
        # scientific notation (e.g. "1.7297836E9").
        return Dates.unix2datetime(parse(Float64, raw))
    elseif t == "DATE"
        return Dates.Date(raw, Dates.dateformat"yyyy-mm-dd")
    elseif t == "DATETIME"
        return _parse_bq_datetime(raw)
    elseif t == "TIME"
        return _parse_bq_time(raw)
    elseif t == "BYTES"
        return Base64.base64decode(raw)
    elseif t == "RECORD" || t == "STRUCT"
        return _row_to_namedtuple(raw, field.fields)
    else
        # STRING, NUMERIC, BIGNUMERIC, GEOGRAPHY, JSON, INTERVAL, …
        return raw
    end
end

# "2026-06-13T12:34:56.789123" -> DateTime (fraction truncated to milliseconds)
function _parse_bq_datetime(s::AbstractString)
    base, frac = _split_fraction(s)
    dt = Dates.DateTime(base, Dates.dateformat"yyyy-mm-ddTHH:MM:SS")
    return dt + Dates.Millisecond(_fraction_to(frac, 3))
end

# "12:34:56.789123" -> Time (microsecond precision preserved)
function _parse_bq_time(s::AbstractString)
    base, frac = _split_fraction(s)
    h, m, sec = parse.(Int, split(base, ':'))
    return Dates.Time(h, m, sec) + Dates.Microsecond(_fraction_to(frac, 6))
end

function _split_fraction(s::AbstractString)
    i = findfirst('.', s)
    i === nothing ? (s, "") : (s[1:i-1], s[i+1:end])
end

# Interpret a fraction string as an integer count of 10^-digits units,
# truncating extra precision (e.g. _fraction_to("789123", 3) == 789).
function _fraction_to(frac::AbstractString, digits::Int)
    isempty(frac) && return 0
    padded = length(frac) >= digits ? frac[1:digits] : rpad(frac, digits, '0')
    return parse(Int, padded)
end
