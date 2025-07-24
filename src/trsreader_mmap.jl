using Mmap

struct Traceset
    mm::Vector{UInt8}          # mmap'ed file contents
    header::Dict{UInt8, Any}
    offset::Int                # offset of TRACE_BLOCK
    trace_length::Int
    title_offset::Int
    title_length::Int
    data_offset::Int
    data_length::Int
    samples_offset::Int
    samples_length::Int
    ntraces::Int
    filename::AbstractString
end

Base.length(ts::Traceset) = ts.ntraces

Base.size(ts::Traceset) = (get(ts.header, NUMBER_SAMPLES, 0), ts.ntraces)
function Base.size(ts::Traceset, idx)
    return size(ts)[idx]
end
    
export trs_close
trs_close(::Traceset) = nothing

function Traceset(mm::Vector{UInt8}, header::Dict{UInt8,Any}, filesize, filename)
    offset = header[TRACE_BLOCK]
    ntraces = header[NUMBER_TRACES]

    title_offset = 0
    title_length = get(header, TITLE_SPACE, 0)
    data_offset = title_offset + title_length
    data_length = get(header, LENGTH_DATA, 0)
    samples_offset = data_offset + data_length
    samples_length = get(header, NUMBER_SAMPLES, 0) * PRIMTYPES[header[SAMPLE_CODING]].width

    trace_length = title_length + data_length + samples_length
    samples_length > 0 || error("0 samples_length")

    ntraces_in_file = div(filesize - offset, trace_length)
    if ntraces_in_file == 0
        error("trs has $ntraces_in_file traces versus $ntraces claimed in header")
    elseif ntraces_in_file != ntraces
        @warn("trs has $ntraces_in_file traces versus $ntraces claimed in header")
        ntraces = ntraces_in_file
    end

    Traceset(
        mm,
        header,
        offset,
        trace_length,
        title_offset,
        title_length,
        data_offset,
        data_length,
        samples_offset,
        samples_length,
        ntraces,
        filename
    )
end

export trs_open
"""
Opens a trace set, you can use modes "r" or "w" or "a", but no combinations. Using mode "w" 
requires you to pass a header dictionary.
"""
function trs_open(path::AbstractString, mode::AbstractString = "r"; header = nothing)
    if mode == "r"
        header = parse_trs_header(path)

        filesize = stat(path).size

        mm = Mmap.mmap(path)
        Traceset(mm, header, filesize, path)
    elseif mode == "a"
        header = parse_trs_header(path)

        filesize = stat(path).size
        filesize > 0 || error("invalid trs file for mode a")

        io = open(path, "a")

        Tracesetwriter(io, header, filesize)
    elseif mode == "w"
        !isnothing(header) || error("mode w needs header dict")

        get(header, NUMBER_SAMPLES, 0) > 0 || error("NUMBER_SAMPLES in headers needs to be set > 0")
        haskey(header, SAMPLE_CODING) || error("SAMPLE_CODING needs to be set")
        if haskey(header, TRACE_PARAMETER_DEFINITIONS) || haskey(header, TRACE_SET_PARAMETERS)
            header[TRS_VERSION] = 2
        else
            header[TRS_VERSION] = 1
        end
        io = open(path, "w")
        header[NUMBER_TRACES] = 0
        headerbytes = serialize_trs_header(header)
        write(io, headerbytes)

        Tracesetwriter(io, header, length(headerbytes))
    else
        error("mode $mode not supported, we only do read (r), append (a) or write (w), not a combination of these")
    end
end

struct Data{T} <: AbstractMatrix{T}
    traceset::Traceset
    offset::Int        # offset within each trace
    nrows::Int         # number of elements
end

export trs_xaxis
"""
Returns the values of the x-axis for this trace set
"""
function trs_xaxis(ts::Traceset)
    xoffset = get(ts.header, OFFSET_X, 0)
    xscale = get(ts.header, SCALE_X, 1)
    nsamples = ts.header[NUMBER_SAMPLES]

    ((0 : nsamples - 1) .- xoffset) .* xscale
end

export trs_xlabel
"""
Returns the label for the x-axis for this trace set, or "" if none
"""
function trs_xlabel(ts::Traceset)
    get(ts.header, LABEL_X, "")
end

export trs_yscsale
"""
Returns the scaling factor for the y-values in this traces. Multiplying the samples
with this factor makes the values of the unit label returned by `trs_ylabel`.
"""
function trs_yscale(ts::Traceset)
    get(ts.header, SCALE_Y, 1)
end

export trs_ylabel
"""
Returns the label for the y-axis for this trace set, or "" if none
"""
function trs_ylabel(ts::Traceset)
    get(ts.header, LABEL_X, "")
end

export trs_samples
"""
Returns a matrix view of the samples in the trace set. 
Every column `i` contains the samples of trace `i`.
"""
function trs_samples(ts::Traceset)
    coding = PRIMTYPES[ts.header[SAMPLE_CODING]]
    offset = ts.samples_offset
    T = coding.eltype

    # special hack because our default for bytes is unsigned, but some scopes output signed bytes
    if T == UInt8
        T = Int8
    end
    nrows = ts.header[NUMBER_SAMPLES]
    return Data{T}(ts, offset, nrows)
end

export trs_data_keys
"""
Returns a set of the data keys in the trace set, for 
example "LEGACY_DATA" or "INPUT", "OUTPUT", etc.

These keys are used as the key parameters in `trs_data`.
"""
function trs_data_keys(ts::Traceset)
    haskey(ts.header, TRACE_PARAMETER_DEFINITIONS) || return nothing
    return keys(ts.header[TRACE_PARAMETER_DEFINITIONS])
end

export trs_data
"""
Returns a matrix view of the data for key `key` in the trace set. 
Every column `i` contains the data for key `key` of trace `i`.

Calling this function without a key returns a matrix view of all data.
"""
function trs_data(ts::Traceset, key::String)
    haskey(ts.header, TRACE_PARAMETER_DEFINITIONS) || error("trs set has no trace param defs")
    param = ts.header[TRACE_PARAMETER_DEFINITIONS][key]
    T = PRIMTYPES[param.typ].eltype
    offset = ts.data_offset + param.offset
    nrows = param.len
    return Data{T}(ts, offset, nrows)
end

function trs_data(ts::Traceset)
    offset = ts.data_offset
    nrows = ts.data_length
    return Data{UInt8}(ts, offset, nrows)
end

export trs_title
"""
Returns a matrix view of the title bytes in the trace set. 
Every column `i` contains the title bytes of trace `i`.
"""
function trs_title(ts::Traceset)
    offset = ts.title_offset
    nrows = ts.title_length
    return Data{UInt8}(ts, offset, nrows)
end


@inline function trace_offset(ts::Traceset, idx::Int)
    @boundscheck checkbounds(1:ts.ntraces, idx)
    return ts.offset + (idx - 1) * ts.trace_length
end

@inline function Base.getindex(x::Data{T}, row::Int, col::Int) where {T}
    base = trace_offset(x.traceset, col) + x.offset
    ptr = @inbounds view(x.traceset.mm, base+1 : base + x.nrows * sizeof(T))
    return @inbounds reinterpret(T, ptr)[row]
end

@inline function Base.getindex(x::Data{T}, ::Colon, col::Int) where {T}
    base = trace_offset(x.traceset, col) + x.offset
    ptr = @inbounds view(x.traceset.mm, base+1 : base + x.nrows * sizeof(T))
    return reinterpret(T, ptr)
end

Base.size(x::Data) = (x.nrows, length(x.traceset))
Base.axes(x::Data) = (Base.OneTo(x.nrows), Base.OneTo(length(x.traceset)))
