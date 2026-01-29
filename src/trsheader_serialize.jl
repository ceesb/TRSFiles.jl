function write_length(io::IO, len::Int)
    if len < 0x80
        write(io, UInt8(len))
    else
        bytes = UInt8[]
        while len > 0
            push!(bytes, UInt8(len & 0xFF))
            len >>= 8
        end
        write(io, UInt8(0x80 | length(bytes)))
        write(io, bytes)
    end
end

function encode_value(tag::UInt8, val)::Vector{UInt8}
    info = get(HEADER_TAGS, tag, HeaderInfo("UNKNOWN", :none, "Unknown tag"))
    datatype = info.datatype
    buf = IOBuffer()

    if isa(datatype, UInt8)
        typ = PRIMTYPES[datatype]

        if typ.symbol == :STRING
            write(buf, codeunits(val))
        else
            write(buf, typ.eltype(val))
        end
    elseif datatype == :none
        # nothing to write
    elseif datatype == :trace_set_parameters
        write_trace_set_parameters(buf, val)
    elseif datatype == :trace_parameter_definitions
        write_trace_parameter_definitions(buf, val)
    else
        error("Unsupported datatype $datatype")
    end

    return take!(buf)
end

function write_parameter_name(io::IO, name::String)
    b = codeunits(ascii(name))
    write(io, UInt16(length(b)))
    write(io, b)
end

function write_trace_set_parameters(io::IO, params::Dict)
    write(io, UInt16(length(params)))
    for (k, v) in params
        write_parameter_name(io, k)

        if isa(v, String)
            typcode = findfirst(p -> p.symbol == :STRING, PRIMTYPES)
        else
            typcode = findfirst(p -> p.eltype == eltype(v) && p.symbol != :STRING, PRIMTYPES)
        end
        
        !isnothing(typcode) || error("don't know how to handle parameter $k of type $(eltype(v))")

        write(io, UInt8(typcode))

        if isa(v, String)
            data = codeunits(ascii(v))
        else
            data = reinterpret(UInt8, v)
        end
        
        typ = PRIMTYPES[typcode]
        write(io, UInt16(length(data) ÷ typ.width))
        write(io, data)
    end
end

function write_trace_parameter_definitions(io::IO, defs::Dict{String,TraceParam})
    write(io, UInt16(length(defs)))
    for (k, tp) in sort(collect(defs); by = p -> p[2].offset)
        write_parameter_name(io, k)
        haskey(PRIMTYPES, tp.typ) || error("param type $(tp.typ) does not exist")
        write(io, UInt8(tp.typ))
        write(io, UInt16(tp.len))
        write(io, UInt16(tp.offset))
    end
end

function serialize_trs_header(headers::Dict{UInt8})::Vector{UInt8}
    buf = IOBuffer()

    needs_len = 0
    if haskey(headers, TRACE_PARAMETER_DEFINITIONS)
        for (k,v) in headers[TRACE_PARAMETER_DEFINITIONS]
            needs_len = max(needs_len, v.offset + v.len * PRIMTYPES[v.typ].width)
        end
    end

    headers[LENGTH_DATA] = max(get(headers, LENGTH_DATA, 0), needs_len)

    for tag in sort(collect(keys(headers)))
        if tag == TRACE_BLOCK
            continue
        end

        val = headers[tag]
        data = encode_value(tag, val)

        write(buf, UInt8(tag))
        write_length(buf, length(data))
        write(buf, data)
    end

    write(buf, TRACE_BLOCK)
    write(buf, 0x00)
    
    bytes = take!(buf)

    if haskey(headers, TRACE_BLOCK)
        length(bytes) == headers[TRACE_BLOCK] || error("header size has changed, this not supported")
    else
        headers[TRACE_BLOCK] = length(bytes)
    end

    return bytes
end
