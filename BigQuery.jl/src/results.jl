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
Convert a JSON-formatted BigQuery row array to a NamedTuple.

`schema_fields` is a vector of (name::Symbol, type_str::String) describing the
columns in column order. Values come from `row["f"]` as `[{"v": value}, ...]`.
"""
function _row_to_namedtuple(row::AbstractDict, schema_fields::Vector{<:Tuple})
    fs = row["f"]
    names = ntuple(i -> schema_fields[i][1], length(schema_fields))
    values = ntuple(length(schema_fields)) do i
        raw = fs[i]["v"]
        _coerce_value(raw, schema_fields[i][2])
    end
    return NamedTuple{names}(values)
end

function _coerce_value(raw, type_str::AbstractString)
    raw === nothing && return missing
    t = uppercase(type_str)
    if t == "INTEGER" || t == "INT64"
        return parse(Int64, raw)
    elseif t == "FLOAT" || t == "FLOAT64"
        return parse(Float64, raw)
    elseif t == "BOOLEAN" || t == "BOOL"
        return parse(Bool, raw)
    else
        return raw  # STRING and anything we don't try to parse
    end
end
