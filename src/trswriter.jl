struct Tracesetwriter{T}
    io::IOStream
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
    writelock::ReentrantLock
end

import Base.length
length(ts::Tracesetwriter) = ts.ntraces

function Tracesetwriter(io, header::Dict{UInt8}, filesize)
    offset = header[TRACE_BLOCK]
    ntraces = header[NUMBER_TRACES]

    title_offset = 0
    title_length = get(header, TITLE_SPACE, 0)
    data_offset = title_offset + title_length
    data_length = get(header, LENGTH_DATA, 0)
    samples_offset = data_offset + data_length
    samples_length = get(header, NUMBER_SAMPLES, 0) * PRIMTYPES[header[SAMPLE_CODING]].width

    trace_length = title_length + data_length + samples_length
    samples_length > 0 || 
        error("0 samples_length")

    ntraces_in_file = div(filesize - offset, trace_length)
    ntraces == ntraces_in_file || 
        error("mismatch between ntraces in header $ntraces and computed $ntraces_in_file (file size $filesize, offset $offset, trace_length $trace_length)")

    # special hack because our default for bytes is unsigned, but some scopes output signed bytes
    coding = PRIMTYPES[header[SAMPLE_CODING]]
    T = coding.eltype
    if T == UInt8
        T = Int8
    end

    Tracesetwriter{T}(
        io,
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
        ReentrantLock()
    )
end

export trs_append
function trs_append(
        t::Tracesetwriter{T}, 
        title::AbstractVector{UInt8}, 
        data::AbstractVector{UInt8}, 
        samples::AbstractVector{T}) where {T}

    lock(t.writelock)
    try
        length(title) == t.title_length || error("wrong title length $(length(title)) != $(t.title_length)")
        length(data) == t.data_length || error("wrong data length $(length(data)) != $(t.data_length)")
        length(samples) == t.header[NUMBER_SAMPLES] || error("wrong samples length $(length(samples)) != $(t.header[NUMBER_SAMPLES])")

        seek(t.io, t.offset + t.header[NUMBER_TRACES] * t.trace_length)
        write(t.io, title)
        write(t.io, data)
        write(t.io, samples)

        t.header[NUMBER_TRACES] += 1
    finally
        unlock(t.writelock)
    end
end

export trs_close
function trs_close(t::Tracesetwriter)
    seek(t.io, 0)
    headerbytes = serialize_trs_header(t.header)
    write(t.io, headerbytes)
    close(t.io)
end
