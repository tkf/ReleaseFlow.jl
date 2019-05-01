using Documenter, ReleaseFlow

makedocs(;
    modules=[ReleaseFlow],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/tkf/ReleaseFlow.jl/blob/{commit}{path}#L{line}",
    sitename="ReleaseFlow.jl",
    authors="Takafumi Arakaki",
    assets=[],
)

deploydocs(;
    repo="github.com/tkf/ReleaseFlow.jl",
)
