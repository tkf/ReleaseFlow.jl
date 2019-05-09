module TestReleaseFlow

using Test

@testset "$path" for path in [
    "test_replace_commits.jl"
]
    include(path)
end

end  # module
