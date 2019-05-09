module TestReplaceCommits

using ReleaseFlow: replace_commits_since_impl, message_readme_change
using Test

mkurl(tag) =
    "https://img.shields.io/github/commits-since/USER/PACKAGE.jl/$tag.svg"

@testset begin
    readme = replace_commits_since_impl((
        tag = "TAG",
        orig = mkurl("v1.2.3"),
    ))
    @test readme.content == mkurl("TAG")

    readme = replace_commits_since_impl((
        tag = "TAG",
        orig = "ignored",
        other = 123,
    ))
    @test readme.content == "ignored"
    @test readme.other == 123

    @info "↓↓↓ (to be ignored)"
    message_readme_change(((
        origmatch = (
            captures = [
                "https://hostname/paths/"
                "..."
                ".svg"
            ],
        ),
        content = mkurl("v1.2.3"),
    )))
    @info "↑↑↑ (to be ignored)"
end

end  # module
