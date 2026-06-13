# params.jl
#
# Serialization of Julia values into BigQuery REST queryParameters
# (https://cloud.google.com/bigquery/docs/reference/rest/v2/jobs/query).

"""
    _bq_param_type(v) -> Dict

Build the `parameterType` JSON object for a Julia value.

| Julia | BigQuery |
|---|---|
| `AbstractString` | `STRING` |
| `Bool` | `BOOL` |
| `Integer` | `INT64` |
| `AbstractFloat` | `FLOAT64` |
| `Dates.Date` | `DATE` |
| `Dates.DateTime` | `TIMESTAMP` (interpreted as **UTC**) |
| `Dates.Time` | `TIME` |
| `Vector{UInt8}` | `BYTES` |
| `AbstractVector{T}` | `ARRAY` of the mapped `T` |

`missing`/`nothing`, `Dict` and `NamedTuple` (STRUCT) parameters are not
supported and throw `ArgumentError`.
"""
function _bq_param_type(v)
    # NOTE: Bool <: Integer and Vector{UInt8} <: AbstractVector — order matters.
    if v isa AbstractString
        return Dict("type" => "STRING")
    elseif v isa Bool
        return Dict("type" => "BOOL")
    elseif v isa Integer
        return Dict("type" => "INT64")
    elseif v isa AbstractFloat
        return Dict("type" => "FLOAT64")
    elseif v isa Dates.Date
        return Dict("type" => "DATE")
    elseif v isa Dates.DateTime
        return Dict("type" => "TIMESTAMP")
    elseif v isa Dates.Time
        return Dict("type" => "TIME")
    elseif v isa Vector{UInt8}
        return Dict("type" => "BYTES")
    elseif v isa AbstractVector
        return Dict("type" => "ARRAY", "arrayType" => _bq_param_eltype(v))
    elseif v === missing || v === nothing
        throw(ArgumentError(
            "NULL query parameters are not supported (the type cannot be " *
            "inferred). Use SQL NULL directly or a typed sentinel value."))
    else
        throw(ArgumentError(
            "Unsupported query parameter type $(typeof(v)). Supported: " *
            "String, Bool, Integer, Float, Date, DateTime, Time, " *
            "Vector{UInt8} (BYTES) and typed Vectors (ARRAY)."))
    end
end

function _bq_param_eltype(v::AbstractVector)
    T = eltype(v)
    if T === Any
        isempty(v) && throw(ArgumentError(
            "Cannot infer the BigQuery element type of an empty Vector{Any}; " *
            "use a typed empty vector such as Int[] or String[]."))
        return _bq_param_type(first(v))
    end
    return _bq_param_type(_dummy_value(T, v))
end

# A representative value used only for type mapping.
_dummy_value(::Type{T}, v::AbstractVector) where {T} =
    isempty(v) ? _dummy_of(T) : first(v)

_dummy_of(::Type{T}) where {T <: AbstractString} = ""
_dummy_of(::Type{Bool}) = false
_dummy_of(::Type{T}) where {T <: Integer} = zero(T)
_dummy_of(::Type{T}) where {T <: AbstractFloat} = zero(T)
_dummy_of(::Type{Dates.Date}) = Dates.Date(1970)
_dummy_of(::Type{Dates.DateTime}) = Dates.DateTime(1970)
_dummy_of(::Type{Dates.Time}) = Dates.Time(0)
_dummy_of(::Type{T}) where {T} =
    throw(ArgumentError("Unsupported query parameter element type $(T)."))

"""
    _bq_param_value(v) -> Dict

Build the `parameterValue` JSON object for a Julia value.
"""
function _bq_param_value(v)
    if v isa Bool
        return Dict("value" => v ? "true" : "false")
    elseif v isa Vector{UInt8}
        return Dict("value" => Base64.base64encode(v))
    elseif v isa AbstractVector
        return Dict("arrayValues" => [_bq_param_value(x) for x in v])
    elseif v isa Dates.Date
        return Dict("value" => Dates.format(v, "yyyy-mm-dd"))
    elseif v isa Dates.DateTime
        # Naive DateTime values are interpreted as UTC (matching the result
        # path, where TIMESTAMP columns decode to UTC DateTimes).
        return Dict("value" => Dates.format(v, "yyyy-mm-dd HH:MM:SS.sss") * "+00")
    elseif v isa Dates.Time
        return Dict("value" => Dates.format(v, "HH:MM:SS.sss"))
    else
        return Dict("value" => string(v))
    end
end

"""
    _query_parameter(v; name=nothing) -> Dict

Build one entry of the `queryParameters` array. `name` is included for
named parameters (`parameterMode=NAMED`) and omitted for positional ones.
"""
function _query_parameter(v; name::Union{AbstractString, Symbol, Nothing}=nothing)
    p = Dict{String, Any}(
        "parameterType"  => _bq_param_type(v),
        "parameterValue" => _bq_param_value(v),
    )
    name === nothing || (p["name"] = String(name))
    return p
end

"""
    _build_query_parameters(params) -> (mode::String, Vector{Dict})

Convert user-supplied `params` into (`parameterMode`, `queryParameters`):

* `AbstractDict` (String or Symbol keys) → `"NAMED"`; reference as `@name`.
* `AbstractVector` → `"POSITIONAL"`; reference as `?` in order.
"""
function _build_query_parameters(params::AbstractDict)
    qp = [_query_parameter(v; name=k) for (k, v) in params]
    return "NAMED", qp
end

function _build_query_parameters(params::AbstractVector)
    eltype(params) <: Pair && throw(ArgumentError(
        "Got a Vector of Pairs — use a Dict for named parameters " *
        "(e.g. Dict(\"x\" => 1)) or a plain Vector for positional ones."))
    return "POSITIONAL", [_query_parameter(v) for v in params]
end
