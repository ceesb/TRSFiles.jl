# TRSFiles

A Julia library to read and write Keysight / Riscure Inspector TRS files.

## Reading

```julia
using TRSFiles

trs = trs_open("bla.trs")

samples = trs_samples(trs)
data = trs_data(trs)
```

Methods `trs_samples` and `trs_data` return a lazy matrix view of the samples and data in the trace set (column wise). You can call any function on these matrices but it works best with optimized column based readers, because these TRS are typically huge and you don't want to read them row-wise.

Newer TRS files have "trace parameter data", which are just named and typed views on the data field. 

```julia
@show trs_data_keys(trs)
data_input = trs_data(trs, "INPUT")
```

The read code uses mmap, is thread-safe, there's no locking, and no allocations.

## Writing

You can create a file from scratch, or append to an existing file. Writing is completely distinct from reading, and you cannot open a file in both "write and read" mode, or "append and read" mode. I implemented the writing code mostly for unit testing the reading code.

```julia
using TRSFiles

ntitle = 0
ndata = 48
nsamples = 100
sampletype = Int8

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

for t in 1 : 10
    trs_append(trs,
        rand(UInt8, ntitle),
        rand(UInt8, ndata),
        rand(sampletype, nsamples))
end

trs_close(trs)

# append some more traces
trs = trs_open("bla.trs", "a")

for t in 1 : 10
    trs_append(trs,
        rand(UInt8, ntitle),
        rand(UInt8, ndata),
        rand(sampletype, nsamples))
end

trs_close(trs)
```

The write code is thread-safe, but uses locks.
