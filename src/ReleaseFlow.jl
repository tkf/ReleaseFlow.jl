"""
# `ReleaseFlow`: a package to help release workflow

Entry points:

```julia
bump_version()
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

versiontag(version::VersionNumber) = string("v", version)

"""
    bump_version([version]; <keyword arguments>)

Bump version to `version`.

# Keyword Arguments
- `project::String`
- `commit::Bool`
"""
function bump_version(version=nothing; project="Project.toml", commit=false)
    if commit
        assert_clean_repo()
    end
    prj = TOML.parsefile(project)

    prev = VersionNumber(prj["version"])
    if version === nothing
        version = @set prev.prerelease = ()
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
        run(`git tag $(versiontag(version))`)
    end
    return prj
end

"""
    start_release(; <keyword arguments>)

Start release process.

* Checkout the release branch.
* Bump the version from vX.Y.Z-DEV to vX.Y.Z.
* Push the release branch.
* Open a PR to trigger `@JuliaRegistrator` bot.

# Keyword Arguments
- `dry_run::Bool`
- `release_branch::String`
"""
function start_release(; dry_run=false, release_branch="release")
    _run = dry_run ? (cmd -> @info "Dry run: $cmd") : run
    m = match(r"github\.com[:/](.*?)(\.git)?$",
              read(`git config --get remote.origin.url`, String))
    repo = m.captures[1]

    _run(`git checkout -b $release_branch`)
    dry_run && (prj = bump_version(commit=true))
    _run(`git push -u origin $release_branch`)
    dry_run && return
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

* Merge release branch to `master`.
* Remove the release branch.
* Push `master` and the tag.

# Keyword Arguments
- `dry_run::Bool`
- `release_branch::String`
- `project::String`
"""
function finish_release(; dry_run=false,
                        release_branch="release", project="Project.toml")
    _run = dry_run ? (cmd -> @info "Dry run: $cmd") : run
    assert_clean_repo()
    prj = TOML.parsefile(project)
    tag = versiontag(VersionNumber(prj["version"]))
    _run(`git checkout master`)
    _run(`git merge $release_branch`)
    _run(`git branch --delete $release_branch`)
    _run(`git push master $tag`)
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
