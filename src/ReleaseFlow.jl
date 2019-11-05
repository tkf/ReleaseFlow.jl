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
using Pkg.Types: write_project
using Setfield
using URIParser

abstract type SideEffect end
struct Perform <: SideEffect end
struct DryRun <: SideEffect end

isdryrun(::SideEffect) = false
isdryrun(::DryRun) = true

_run(::Perform, cmd) = (@info "Run: $cmd"; run(cmd))
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

_versionnumber(v::VersionNumber) = v
_versionnumber(v::AbstractString) = VersionNumber(v)
_versionnumber(v::Nothing) = v

versiontag(version::VersionNumber) = string("v", version)

"""
    bump_version([version]; <keyword arguments>)

Bump version to `version`.

# Arguments
- `version::Union{VersionNumber, AbstractString, Nothing}`

# Keyword Arguments
- `project::String`
- `commit::Bool = false`: Commit change.
- `tag::Bool = false`: Run `git tag`.
- `dry_run::Bool = false`: Print operations to be performed.
- `limit_commit::Bool = true`: Only commit the change to `Project.toml` file.
- `for_release::Bool = false`: If `true`, do not bump to a `-DEV` version.
"""
function bump_version(
    version::Union{VersionNumber, AbstractString, Nothing} = nothing;
    dry_run::Bool = false,
    commit::Bool = false,
    kwargs...
)
    eff = dry_run ? DryRun() : Perform()
    if commit
        assert_clean_repo(eff)
    end
    return _bump_version(
        eff, _versionnumber(version);
        commit = commit,
        kwargs...)
end

function _bump_version(
    eff,
    version = nothing;
    project = "Project.toml",
    commit = false,
    tag = false,
    limit_commit = true,
    for_release = false,
)
    dry_run = isdryrun(eff)
    prj = TOML.parsefile(project)

    prev = if haskey(prj, "version")
        VersionNumber(prj["version"])
    end
    if version === nothing
        if prev === nothing
            error("""
            Please specify `version`.
            As `version` not found in `Project.toml`, a new version cannot
            be guessed from the previous version.
            """)
        end
        if for_release
            version = prev
            prev.prerelease == () && @set! version.patch += 1
            @set! version.prerelease = ()
        else
            if prev.prerelease == ()
                version = prev
                @set! version.prerelease = ("DEV",)
                @set! version.patch += 1
            else
                version = @set prev.prerelease = ()
            end
        end
    end
    if prev !== nothing && version <= prev
        error("""
        Version number must be increased.
        Previous:   $prev
        Specified:  $version
        """)
    end
    @info "Bump: $(something(prev, "not set")) → $version"
    prj["version"] = string(version)

    if dry_run
        @info "Dry run: $project would be modified (skipped)."
    else
        write_project(prj, project)
    end
    if commit
        _commit_bump_version(
            eff,
            version;
            project = project,
            limit_commit = limit_commit,
        )
    end
    if tag
        _run(eff, `git tag $(versiontag(version))`)
    end
    return prj
end

function _commit_bump_version(
    eff,
    version;
    project = "Project.toml",
    limit_commit = limit_commit,
)
    msg = "Bump to $version"
    commit_cmd = `git commit -m $msg`
    if limit_commit
        commit_cmd = `$commit_cmd -- $project`
    end
    _run(eff, `git add -- $project`)
    _run(eff, commit_cmd)
    return
end

"""
    replace_commits_since(version; <keyword arguments>)

# Arguments
- `version::VersionNumber`

# Keyword Arguments
- `dry_run::Bool`
- `readme_path::String`
"""
replace_commits_since(
    version::Union{VersionNumber, Nothing} = nothing;
    dry_run::Bool = false,
    kwargs...
) = _replace_commits_since(
    dry_run ? DryRun() : Perform(),
    version;
    kwargs...)

function _replace_commits_since(
    eff::SideEffect,
    version;
    readme_path::String = "README.md",
    git_add = false,
)
    orig = read(readme_path, String)
    origmatch = match(rx_commits_since, orig)
    if origmatch === nothing
        @info "No commits-since badge found in $readme_path"
        return
    end
    readme = replace_commits_since_impl((
        path = readme_path,
        orig = orig,
        origmatch = origmatch,
        tag = versiontag(version),
    ))
    message_readme_change(readme)
    write_replace_commits_since(eff, readme)
    if git_add
        _run(eff, `git add -- $readme_path`)
    end
    return readme
end

const rx_commits_since =
    r"(https://img\.shields\.io/github/commits-since/[^/]+/[^/]+/)(v[0-9\.]+)(\.svg)"

function replace_commits_since_impl(readme)
    subst = SubstitutionString(string(
        s"\1",
        readme.tag,
        s"\3",
    ))
    return (
        content = replace(readme.orig, rx_commits_since => subst),
        readme...,
    )
end

function message_readme_change(readme)
    origmatch = readme.origmatch
    newmatch = match(rx_commits_since, readme.content) :: RegexMatch
    tagmetavar = raw"$tag"
    url = string(
        origmatch.captures[1],
        tagmetavar,
        origmatch.captures[3],
    )
    @info """
    Replacing `$tagmetavar` in `$url`
    From: $(origmatch.captures[2])
    To  : $(newmatch.captures[2])
    """
end

write_replace_commits_since(::DryRun, readme) = readme

function write_replace_commits_since(::Perform, readme)
    write(readme.path, readme.content)
    return readme
end

"""
    start_release([version]; <keyword arguments>)

Start release process.

* Checkout the release branch.
* Bump the version from vX.Y.Z-DEV to vX.Y.Z.
* Push the release branch.
* Open an issue to trigger `@JuliaRegistrator` bot.

# Arguments
- `version::Union{VersionNumber, AbstractString, Nothing}`

# Keyword Arguments
- `dry_run::Bool`
- `release_branch::String`
- `bump_version::Bool = true`
"""
start_release(
    version::Union{VersionNumber, AbstractString, Nothing} = nothing;
    dry_run::Bool = false,
    kwargs...
) =
    _start_release(
        dry_run ? DryRun() : Perform(),
        _versionnumber(version);
        kwargs...)

function _start_release(
    eff,
    version;
    release_branch = "release",
    bump_version = true,
)
    # Maybe move `project` to keyword argument.  However, all code
    # below now assumes that cwd is in the project.  This assumption
    # has to be removed first.
    project = "Project.toml"

    m = match(r"github\.com[:/](.*?)(\.git)?$",
              read(`git config --get remote.origin.url`, String))
    repo = m.captures[1]

    _run(eff, `git checkout -b $release_branch`)
    assert_clean_repo(eff)
    if bump_version
        prj = _bump_version(eff, version; commit=false, for_release=true)
        newversion = VersionNumber(prj["version"])
        _replace_commits_since(eff, newversion; git_add=true)
        _commit_bump_version(eff, newversion, limit_commit=false)
    else
        prj = TOML.parsefile(project)
        if !haskey(prj, "version")
            error("`$project` does not have `version`.")
        end
    end
    if !(haskey(prj, "compat") && haskey(prj["compat"], "julia"))
        error("""
        No Julia compatibility information.  Add the following in $project:

            [compat]
            julia = "1"
        """)
    end
    _run(eff, `git push -u origin $release_branch`)
    _github_new_issue(
        eff, repo;
        title = "Release $(prj["version"])",
        body = "@JuliaRegistrator `register(branch=$release_branch)`",
        # Avoid including this issue in the release notes.  See:
        # https://github.com/JuliaRegistries/TagBot#release-notes
        labels = "no changelog",
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
    _run(eff, `git checkout master`)
    _run(eff, `git merge $release_branch`)
    _run(eff, `git branch --delete $release_branch`)
    _run(eff, `git push origin master`)
end

escape_query_params(query) =
    join([
        string(key, "=", escape_form(value)) for (key, value) in query
    ], "&")

"""
    github_new_issue_uri(repo; query...)

For usable `query`, see:
https://help.github.com/en/articles/about-automation-for-issues-and-pull-requests-with-query-parameters
"""
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
