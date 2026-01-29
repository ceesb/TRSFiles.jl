[![](https://img.shields.io/badge/docs-green.svg)](https://ceesb.github.io/TRSFiles.jl/)

# TRSFiles

A Julia library to read and write Keysight / Riscure Inspector TRS files.

## Installation

```julia
import Pkg; Pkg.add("TRSFiles")
```

## Reading

```julia
using TRSFiles

trs = trs_open("bla.trs")

samples = trs_samples(trs)
data = trs_data(trs)
```

Methods `trs_samples` and `trs_data` return a lazy matrix view of the samples and data in the trace set (column wise). You can call any function on these matrices but it works best with optimized column based readers, because these TRS are typically huge and you don't want to read them row-wise.

For example, compute the sample mean over all traces:
```julia
using Statistics

mean(samples; dims = 2)
```

Newer TRS files have "trace parameter data", which are just named and typed views on the data field.

```julia
@show trs_data_keys(trs)
data_input = trs_data(trs, "INPUT")
```

If you have a trace set and you want to see all the headers, there's an unexported
function that you can call which dumps the header on stdout:

```julia
TRSFiles.dumpheader(trs.header)
```

The read code uses mmap, is thread-safe, there's no locking, and no allocations.

## Writing

You can create a file from scratch, or append to an existing file. Writing is completely distinct from reading, and you cannot open a file in both "write and read" mode, or "append and read" mode. I implemented the writing code mostly for unit testing the reading code.

```julia
using TRSFiles

ntitle = 0
nkey = 16
ninput = 16
noutput = 16
nsamples = 100
sampletype = Int8

trs = trs_open("bla.trs", "w"; header = Dict(
        TRSFiles.TITLE_SPACE => ntitle,
        TRSFiles.NUMBER_SAMPLES => nsamples,
        TRSFiles.SAMPLE_CODING => trs_coding(sampletype),
        TRSFiles.TRACE_SET_PARAMETERS => Dict(
            "SOMEGLOBALVALUE" => Int32[1,2,3],
        ),
        TRSFiles.TRACE_PARAMETER_DEFINITIONS => create_trace_parameter_definitions(
            "INPUT" => (UInt8,ninput),
            "KEY" => (UInt8,nkey),
            "OUTPUT" => (UInt8,noutput)
        )))

for t in 1 : 10
    trs_append(trs,
        rand(UInt8, ntitle),
        vcat(rand(UInt8, ninput),rand(UInt8, nkey),rand(UInt8, noutput)),
        rand(sampletype, nsamples))
end

trs_close(trs)

# append some more traces
trs = trs_open("bla.trs", "a")

for t in 1 : 10
    trs_append(trs,
        rand(UInt8, ntitle),
        vcat(rand(UInt8, ninput),rand(UInt8, nkey),rand(UInt8, noutput)),
        rand(sampletype, nsamples))
end

trs_close(trs)
```

The write code is thread-safe, but uses locks.
