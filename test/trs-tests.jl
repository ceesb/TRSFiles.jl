using Trsfiles
import Trsfiles: PRIMTYPES, HEADER_TAGS, TraceParam

using Test

function genheader(ntraces = 100, nsamples = 200, ntitle = 16)
    header = Dict{UInt8, Any}()

    for (k,v) in HEADER_TAGS
        datatype = v.datatype
        if isa(datatype, UInt8)
            typ = PRIMTYPES[datatype]
            
            if typ.symbol == :STRING
                header[k] = String(rand(0x61:0x7a, 32))
            else
                header[k] = rand(typ.eltype)
            end
        elseif datatype == :trace_set_parameters
            nparameters = rand(1:10)

            tsp = Dict{String, Any}()
            for i in 1 : nparameters
                name = String(rand(0x61:0x7a, 32))
                eltype = rand([String, UInt8, Int16, Int32, Int64, Float32, Float64, Bool])
                len = rand(1:64)
                if eltype == String
                    val = String(rand(0x61:0x7a, 32))
                else
                    val = rand(eltype, len)
                end

                tsp[name] = val
            end
            header[Trsfiles.TRACE_SET_PARAMETERS] = tsp     

        elseif datatype == :trace_parameter_definitions
            nparameters = rand(1:10)

            tpd = Dict{String, TraceParam}()
            offset = 0
            for i in 1 : nparameters
                name = String(rand(0x61:0x7a, 32))
                eltype = rand([UInt8, Int16, Int32, Int64, Float32, Float64, Bool])
                # @show eltype
                typ = trs_coding(eltype)
                # @show typ
                width = PRIMTYPES[typ].width
                len = rand(1:64)
                tp = TraceParam(typ, len, offset)
                offset += len * width
                tpd[name] = tp
            end

            header[Trsfiles.TRACE_PARAMETER_DEFINITIONS] = tpd
        end
    end

    header[Trsfiles.NUMBER_TRACES] = ntraces
    header[Trsfiles.NUMBER_SAMPLES] = nsamples
    header[Trsfiles.TITLE_SPACE] = ntitle
    header[Trsfiles.SAMPLE_CODING] = rand(keys(Trsfiles.PRIMTYPES))
    return header
end

function test()
    ntraces = 100
    nsamples = 200
    ntitle = 16
    header = genheader(ntraces, nsamples, ntitle)
    @show fname = tempname(cleanup = true)

    trsout = trs_open(fname, "w"; header = header)
    sampletype = typeof(trsout).parameters[1]
    header[Trsfiles.LENGTH_DATA]

    samples = rand(sampletype, nsamples, ntraces)
    title = rand(UInt8, ntitle, ntraces)
    data = rand(UInt8, header[Trsfiles.LENGTH_DATA], ntraces)
    
    for t in 1 : ntraces
        @views begin
            trs_append(trsout, title[:, t], data[:, t], samples[:, t])
        end
    end

    trs_close(trsout)

    trsin = trs_open(fname)
    if trsin.header != header
        @test keys(trsin.header) == keys(header)
        for k in keys(header)
            v = header[k]
            if isa(v, Dict)
                @test keys(trsin.header[k]) == keys(header[k])
                for k2 in keys(header[k])
                    @test header[k][k2] == trsin.header[k][k2]
                end
            else
                @test header[k] == trsin.header[k]
            end
        end
    end
    
    insamples = trs_samples(trsin)
    intitle = trs_title(trsin)
    indata = trs_data(trsin)

    for t in 1 : ntraces
        @views begin
            @test insamples[:, t] == samples[:, t]
            @test indata[:, t] == data[:, t]
            @test intitle[:, t] == title[:, t]
        end
    end


    keys = trs_data_keys(trsin)
    if !isnothing(keys)
        for key in keys
            datakey = trs_data(trsin, key)
            tp = trsin.header[Trsfiles.TRACE_PARAMETER_DEFINITIONS][key]
            offset = tp.offset
            len = tp.len
            width = Trsfiles.PRIMTYPES[tp.typ].width
            eltyp = Trsfiles.PRIMTYPES[tp.typ].eltype
            for t in 1 : ntraces
                @views begin
                    expected = reinterpret(eltyp, data[offset + 1 : offset + len * width, t])
                    @test length(expected) == size(datakey)[1]
                    # @test datakey[:, t] == expected
                    for j in 1 : length(expected)
                        @test isequal(datakey[j, t], expected[j])
                    end
                end
            end
        end
    end

    trs_close(trsin)

end

for i in 1 : 20
    test()
end