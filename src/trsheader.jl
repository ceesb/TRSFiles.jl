const NUMBER_TRACES = 0x41
const NUMBER_SAMPLES = 0x42
const SAMPLE_CODING = 0x43
const LENGTH_DATA = 0x44
const TITLE_SPACE = 0x45
const TRACE_TITLE = 0x46
const DESCRIPTION = 0x47
const OFFSET_X = 0x48
const LABEL_X = 0x49
const LABEL_Y = 0x4A
const SCALE_X = 0x4B
const SCALE_Y = 0x4C
const TRACE_OFFSET = 0x4D
const LOGARITHMIC_SCALE = 0x4E
const TRS_VERSION = 0x4F
const TRACE_BLOCK = 0x5F
const EXTERNAL_CLOCK_USED = 0x60
const NUMBER_VIEW = 0x68
const TRACE_OVERLAP = 0x69
const TRACE_SET_PARAMETERS = 0x76
const TRACE_PARAMETER_DEFINITIONS = 0x77

struct PrimType
    symbol::Symbol
    eltype
    width::Int
end

const PRIMTYPES = Dict(
    0x01 => PrimType(:BYTE, UInt8,  1),
    0x02 => PrimType(:SHORT, Int16,  2),
    0x04 => PrimType(:INT, Int32,  4),
    0x14 => PrimType(:FLOAT, Float32,  4),
    0x08 => PrimType(:LONG, Int64,  8),
    0x18 => PrimType(:DOUBLE, Float64,  8),
    0x20 => PrimType(:STRING, UInt8,  1),
    0x31 => PrimType(:BOOL, Bool,  1),
)

struct HeaderInfo
    name::String
    datatype::Union{UInt8, Symbol}
    description::String
end


const HEADER_TAGS = Dict(
    NUMBER_TRACES => HeaderInfo("NUMBER_TRACES", 0x04, "Number of traces"),
    NUMBER_SAMPLES => HeaderInfo("NUMBER_SAMPLES", 0x04, "Number of samples per trace"),
    SAMPLE_CODING => HeaderInfo("SAMPLE_CODING", 0x01, "Sample coding"),
    LENGTH_DATA => HeaderInfo("LENGTH_DATA", 0x02, "Length of cryptographic data included"),
    TITLE_SPACE => HeaderInfo("TITLE_SPACE", 0x01, "Title space reserved per trace"),
    TRACE_TITLE => HeaderInfo("TRACE_TITLE", 0x20, "Global trace title"),
    DESCRIPTION => HeaderInfo("DESCRIPTION", 0x20, "Description"),
    OFFSET_X => HeaderInfo("OFFSET_X", 0x04, "Offset in X-axis"),
    LABEL_X => HeaderInfo("LABEL_X", 0x20, "Label of X-axis"),
    LABEL_Y => HeaderInfo("LABEL_Y", 0x20, "Label of Y-axis"),
    SCALE_X => HeaderInfo("SCALE_X", 0x14, "Scale value for X-axis"),
    SCALE_Y => HeaderInfo("SCALE_Y", 0x14, "Scale value for Y-axis"),
    TRACE_OFFSET => HeaderInfo("TRACE_OFFSET", 0x04, "Trace offset for displaying trace numbers"),
    LOGARITHMIC_SCALE => HeaderInfo("LOGARITHMIC_SCALE", 0x01, "Logarithmic scale"),
    TRS_VERSION => HeaderInfo("TRS_VERSION", 0x01, "Traceset format version"),
    TRACE_BLOCK => HeaderInfo("TRACE_BLOCK", :none, "Trace block marker (end of header)"),
    EXTERNAL_CLOCK_USED => HeaderInfo("EXTERNAL_CLOCK_USED", 0x31, "External clock used"),
    NUMBER_VIEW => HeaderInfo("NUMBER_VIEW", 0x04, "View number of traces"),
    TRACE_OVERLAP => HeaderInfo("TRACE_OVERLAP", 0x31, "Trace overlap"),
    TRACE_SET_PARAMETERS => HeaderInfo("TRACE_SET_PARAMETERS", :trace_set_parameters, "Custom global trace set parameters"),
    TRACE_PARAMETER_DEFINITIONS => HeaderInfo("TRACE_PARAMETER_DEFINITIONS", :trace_parameter_definitions, "Custom local trace parameter definitions"),
)

export trs_coding
"""
returns the byte that encodes a julia type (or nothing if not supported)
"""
trs_coding(::Type{T}) where {T} = findfirst(x -> x.eltype == (T == Int8 ? UInt8 : T), PRIMTYPES)

# Read length with optional multi-byte length as per TLV spec
function read_length(io)
    len_byte = read(io, UInt8)
    if (len_byte & 0x80) != 0
        n = len_byte & 0x7F
        length_bytes = read(io, n)
        length = 0
        for (i, b) in enumerate(length_bytes)
            length += UInt(b) << (8*(i-1))
        end
        return Int(length)
    else
        return Int(len_byte)
    end
end

# Decode value based on datatype and length
function decode_value(io, tag, datatype::Union{UInt8, Symbol}, length::Int)
    val_bytes = read(io, length)

    if isa(datatype, UInt8)
        typ = PRIMTYPES[datatype]

        if typ.symbol == :STRING
            val = String(val_bytes)
        else
            typ.width == length || 
                error("tag $tag, got $(length) bytes, wanted $(typ.width)")
            val = reinterpret(typ.eltype, val_bytes)[1]
        end

        return val
    elseif datatype == :none
        return nothing
    elseif datatype == :trace_set_parameters
        if length > 0
            return parse_trace_set_parameters(val_bytes)
        else
            return Dict()
        end
    elseif datatype == :trace_parameter_definitions
        if length > 0
            return parse_trace_parameter_definitions(val_bytes)
        else
            return Dict()
        end
    else
        error("don't know how to deal with parameter $tag, $datatype, $length")
    end
end

# Helper to read UInt16 little endian
function read_short(io::IO)
    return read(io, UInt16)
end

# Read parameter name: 2-byte length + UTF8 string
function read_parameter_name(io::IO)
    name_length = read_short(io)
    name_bytes = read(io, name_length)
    return String(name_bytes)
end

# Deserialize TraceSetParameter (stub: just read 1-byte length + string value)
function deserialize_trace_set_parameter(io::IO)
    typ = PRIMTYPES[read(io, UInt8)]
    len = read_short(io)
    val_bytes = read(io, len * typ.width)

    if typ.symbol == :BYTE
        val = val_bytes
    elseif typ.symbol == :STRING
        val = String(val_bytes)
    else
        val = reinterpret(typ.eltype, val_bytes)
    end

    return val
end

export TraceParam
"""
Encodes a trace parameter

- typ is a coding byte, see trs_coding
- len is the number of elements (i.e. number of bytes is len * typ.width)
- offset is the byte offset in the data field where this param lives

For example `TraceParam(trs_coding(UInt16), 16, 0)` is a 16 element short 
array at byte offset 0. A next parameter would thus be at byte offset 32 (even though
you probably shouldn't overlap parameters, the library allows it).

When you create a TRS file and your header has trace parameters, we sanity 
check and adjust the data length so that it fits.

Example use:
```
trs = trs_open("bla.trs", "w"; header = Dict(
        TRSFiles.TITLE_SPACE => ntitle,
        TRSFiles.LENGTH_DATA => ndata,
        TRSFiles.NUMBER_SAMPLES => nsamples,
        TRSFiles.SAMPLE_CODING => trs_coding(sampletype),
        TRSFiles.TRACE_PARAMETER_DEFINITIONS => Dict(
            "INPUT" => TraceParam(trs_coding(UInt8), 16, 0),
            "KEY" => TraceParam(trs_coding(UInt8), 16, 16),
            "OUTPUT" => TraceParam(trs_coding(UInt8), 16, 32),
        )))
```
"""
struct TraceParam
    typ::UInt8
    len::Int
    offset::Int
end
    

function deserialize_trace_parameter_definition(io::IO)
    typ = read(io, UInt8)
    haskey(PRIMTYPES, typ) || error("type $typ not supported")
    len = read_short(io)
    offset = read_short(io)

    return TraceParam(typ,len,offset)
end

function parse_trace_set_parameters(data::Vector{UInt8})
    io = IOBuffer(data)
    result = Dict{String,Any}()

    n_entries = read_short(io)
    for i in 1:n_entries
        name = read_parameter_name(io)
        value = deserialize_trace_set_parameter(io)
        result[name] = value
    end

    return result
end

function parse_trace_parameter_definitions(data::Vector{UInt8})
    io = IOBuffer(data)
    result = Dict{String,TraceParam}()

    n_entries = read_short(io)
    for i in 1:n_entries
        name = read_parameter_name(io)
        value = deserialize_trace_parameter_definition(io)
        result[name] = value
    end

    return result
end

# Pretty print with indentation, supports nested dicts and string maps
function dumpheaders(headers::Dict{UInt8,Any}, indent::Int=0)
    sp = "  "^indent
    for tag in sort(collect(keys(headers)))
        info = get(HEADER_TAGS, tag, HeaderInfo("UNKNOWN", :none, "Unknown tag"))
        val = headers[tag]
        if isa(val, Dict{String})
            println("$sp$(info.name):")
            dumpheaders(val, indent + 1)
        else
            println("$sp$(info.name) (0x$(tag)): $(string(val))")
        end
    end
end

function dumpheaders(headers::Dict{String}, indent::Int=0)
    sp = "  "^indent

    for (key, val) in headers
        println("$sp$key: $val")
    end
end

# Parse the TRS header TLV
function parse_trs_header(filename)
    io = open(filename, "r")
    headers = Dict{UInt8,Any}()

    while true
        if eof(io)
            error("EOF reached before TRACE_BLOCK found")
        end

        tag = read(io, UInt8)
        length = read_length(io)

        if tag == TRACE_BLOCK
            offset = position(io)
            headers[TRACE_BLOCK] = offset
            break
        end

        if length == 0
            @warn("Skipping zero-length tag $tag")
            continue
        end

        info = get(HEADER_TAGS, tag, HeaderInfo("UNKNOWN", 0x20, "Unknown tag"))
        val = decode_value(io, tag, info.datatype, length)
        headers[tag] = val
    end

    close(io)

    if haskey(headers, TRACE_PARAMETER_DEFINITIONS)
        for (k,v) in headers[TRACE_PARAMETER_DEFINITIONS]
            v.offset + v.len * PRIMTYPES[v.typ].width <= get(headers, LENGTH_DATA, 0) || 
                error("borked trace param def $k")
        end
    end

    return headers
end
