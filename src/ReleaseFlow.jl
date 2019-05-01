"""
# `ReleaseFlow`: a package to help release workflow

Entry points:

```julia
start_release()
finish_release()
```
"""
module ReleaseFlow

using DefaultApplication
using Pkg: TOML
using Setfield
using URIParser

function assert_clean_repo()
    dirty = read(`git status --short`, String)
    if !isempty(dirty)
        error("""
        Git repository is not clean.  Following files are not committed:
        $dirty
        """)
    end
end

function bump_version(version=nothing; project="Project.toml", commit=false)
    if commit
        assert_clean_repo()
    end
    prj = TOML.parsefile(project)

    prev = VersionNumber(prj["version"])
    if version === nothing
        version = VersionNumber(prev)
        @set! version.prerelease = ()
    end
    if version < prev
        error("""
        Version number must be increased.
        Previous:   $prev
        Specified:  $version
        """)
    end
    prj["version"] = string(version)

    open(project, write=true) do io
        TOML.print(io, prj)
    end
    if commit
        msg = "Bump to $version"
        run(`git commit -m $msg -- $project`)
        run(`git tag $(string("v", version))`)
    end
    return prj
end

"""
    start_release(; [release_branch])

Start release process.
"""
function start_release(; release_branch="release")
    m = match(r"github\.com[:/](.*?)(\.git)?$",
              read(`git config --get remote.origin.url`, String))
    repo = m.captures[1]

    run(`git checkout -b $release_branch`)
    prj = bump_version(commit=true)
    run(`git push -u origin $release_branch`)
    github_new_issue(
        repo;
        title = "Release $(prj["version"])",
        body = "@JuliaRegistrator `register(branch=$release_branch)`",
    )
    return
end

"""
    finish_release()

Finalize release process.
"""
function finish_release(; release_branch="release")
    error("Not implemented")
end

escape_query_params(query) =
    join([
        string(key, "=", escape_form(value)) for (key, value) in query
    ], "&")

function github_new_issue_uri(repo; query...)
    url = URI("https://github.com/$repo/issues/new")
    return @set url.query = escape_query_params(query)
end

function github_new_issue(repo; query...)
    DefaultApplication.open(github_new_issue_uri(repo; query...))
end

end # module
