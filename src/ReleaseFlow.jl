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

abstract type SideEffect end
struct Perform <: SideEffect end
struct DryRun <: SideEffect end

isdryrun(::SideEffect) = false
isdryrun(::DryRun) = true

_run(::Perform, cmd) = run(cmd)
_run(::DryRun, cmd) = @info "Dry run: $cmd"

_error(::Perform, msg) = error(msg)
_error(::DryRun, msg) = @error """
    Dry run (Continuing by pretending the error is not occurred):
    $msg"""

function assert_clean_repo(eff)
    dirty = read(`git status --short`, String)
    if !isempty(dirty)
        _error(eff, """
        Terminating since Git repository is not clean.
        Following files are not committed:
        $dirty""")
    end
end

versiontag(version::VersionNumber) = string("v", version)

"""
    bump_version([version]; <keyword arguments>)

Bump version to `version`.

# Keyword Arguments
- `project::String`
- `commit::Bool`
- `dry_run::Bool`
"""
bump_version(version=nothing; dry_run=false, kwargs...) =
    _bump_version(dry_run ? DryRun() : Perform(), version; kwargs...)

function _bump_version(eff, version=nothing;
                       project="Project.toml", commit=false)
    dry_run = isdryrun(eff)
    if commit
        assert_clean_repo(eff)
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

    if dry_run
        @info "Dry run: $project would be modified (skipped)."
    else
        open(project, write=true) do io
            TOML.print(io, prj)
        end
    end
    if commit
        msg = "Bump to $version"
        _run(eff, `git commit -m $msg -- $project`)
        _run(eff, `git tag $(versiontag(version))`)
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
start_release(; dry_run=false, kwargs...) =
    _start_release(dry_run ? DryRun() : Perform(); kwargs...)

function _start_release(eff; release_branch="release")
    m = match(r"github\.com[:/](.*?)(\.git)?$",
              read(`git config --get remote.origin.url`, String))
    repo = m.captures[1]

    _run(eff, `git checkout -b $release_branch`)
    prj = _bump_version(eff; commit=true)
    _run(eff, `git push -u origin $release_branch`)
    _github_new_issue(
        eff, repo;
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
finish_release(; dry_run=false, kwargs...) =
    _finish_release(dry_run ? DryRun() : Perform(); kwargs...)

function _finish_release(eff; release_branch="release", project="Project.toml")
    assert_clean_repo(eff)
    prj = TOML.parsefile(project)
    tag = versiontag(VersionNumber(prj["version"]))
    _run(eff, `git checkout master`)
    _run(eff, `git merge $release_branch`)
    _run(eff, `git branch --delete $release_branch`)
    _run(eff, `git push origin master $tag`)
end

escape_query_params(query) =
    join([
        string(key, "=", escape_form(value)) for (key, value) in query
    ], "&")

function github_new_issue_uri(repo; query...)
    url = URI("https://github.com/$repo/issues/new")
    return @set url.query = escape_query_params(query)
end

_openapp(::Perform, url) = DefaultApplication.open(url)
_openapp(::SideEffect, url) = @info "Dry run: Open URL: $url"

_github_new_issue(eff, repo; query...) =
    _openapp(eff, github_new_issue_uri(repo; query...))

github_new_issue(repo; query...) = _github_new_issue(Perform(), repo; query...)

end # module
