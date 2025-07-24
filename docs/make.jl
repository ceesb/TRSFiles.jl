# docs/make.jl
using Documenter, TRSFiles

makedocs(
    sitename = "TRSFiles.jl",
    modules = [TRSFiles],
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md",
        "API"  => "api.md",
    ]
)
