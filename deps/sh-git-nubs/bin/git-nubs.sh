#!/bin/sh
# vim:tw=0:ts=2:sw=2:et:norl:ft=sh
# Project: https://github.com/landonb/sh-git-nubs#🌰
# License: MIT

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

git_branch_exists () {
  local branch_name="$1"

  # Hrmm, you'd think this would not print:
  #   git rev-parse --verify --quiet HEAD
  # This works, but technically we should use rev-parse:
  #  git show-ref --verify --quiet refs/heads/${branch_name}
  git rev-parse --verify refs/heads/${branch_name} > /dev/null 2>&1
}

git_branch_name () {
  local project_root
  project_root="$(git_project_root)"
  [ $? -eq 0 ] || return

  # Note that $(git rev-parse HEAD) returns the hash, not the name,
  # so we add the option, --abbrev-ref.
  # - But first! check there's actually a branch, i.e., if `git init`
  #   but no `git commit`, rev-parse prints error.
  # - Note that `test ""` returns false; `test "foo"` returns true.
  if [ ! "$(command ls -A "${project_root}/.git/refs/heads")" ]; then
    echo "<?!>"

    return
  fi

  # 2020-09-21: (lb): Adding `=loose`:
  # - For whatever reason, I'm seeing this behavior:
  #   - On Linux, `git rev-parse --abbrev-ref` returns simply, e.g., "my_branch".
  #   - But on macOS, rev-parse returns a more qualified name, "heads/my_branch".
  # - I think that's because, on macOS (for whatever reason), there are two
  #   remote refs: .git/refs/remotes/release/HEAD
  #           and: .git/refs/remotes/release/release
  # - Use `loose` option to remove the "heads/" prefix, e.g.,
  #      $ git rev-parse --abbrev-ref=loose   # Prints, e.g., "my_branch"
  #      $ git rev-parse --abbrev-ref=strict  # Prints, e.g., "heads/my_branch"
  # - See also:
  #      $ git symbolic-ref --short HEAD
  local branch_name=$(git rev-parse --abbrev-ref=loose HEAD)

  printf %s "${branch_name}"
}

git_branch_name_full () {
  git rev-parse --symbolic-full-name HEAD
}

git_check_branch_name () {
  git check-ref-format --branch "$1"
}

# ***

# Prints the tracking aka upstream branch.
git_tracking_branch () {
  git rev-parse --abbrev-ref --symbolic-full-name @{u} 2> /dev/null
}

git_upstream () {
  git_tracking_branch
}

git_tracking_branch_safe () {
  # Because errexit, fallback on empty string.
  git_tracking_branch || echo ''
}

# ***

# BWARE: If the arg. is a valid SHA format, git-rev-parse echoes
# it without checking if object actually exists.
git_commit_object_name () {
  local gitref="${1:-HEAD}"
  local opts="$2"

  git rev-parse ${opts} "${gitref}"
}

git_is_same_commit () {
  local lhs="$1"
  local rhs="$2"

  [ "$(git_commit_object_name "${lhs}")" = "$(git_commit_object_name "${rhs}")" ]
}

# There are a few ways to find the object name (SHA) for a tag:
#
#   git rev-parse refs/tags/sometag
#   git rev-parse --tags=*some/tag
#   git show-ref --tags
#
# Per `man git-rev-parse` --tags appends "/*" if search doesn't include glob
# character (*?[), making it a prefix match -- and also making it *not* match
# what you're trying to search, which seems like a weird interface choice.
# - E.g., searching for some/tag:
#     git rev-parse --tags=some/tag
#   won't actually match some/tag. It will match some/tag/name.
#   - To match some/tag, you have to glob it explicitly, e.g.,
#       git rev-parse --tags=*some/tag
#       git rev-parse --tags=some/tag*
#       git rev-parse --tags=[s]ome/tag
#   - But there's no way to make an exact tag name match using --tags.
#     - Which I guess is Git nudging you to use refs/tags/.
# Note the UX differences between using refs/tags/ vs. --tags:
# - If not found, refs/tags reprints argument, "ambiguous argument" message,
#   and exits nonzero. --tags prints nothing and exits zero.
#   - Here we mimic --tags.
git_tag_object_name () {
  local gitref="$1"
  local opts="$2"

  [ -n "${gitref}" ] || return 0

  local says_git=""
  says_git="$(git rev-parse ${opts} refs/tags/${gitref} 2> /dev/null)"
  [ $? -ne 0 ] || echo "${says_git}"
}

git_tag_exists () {
  local tag_name="$1"

  git rev-parse --verify refs/tags/${tag_name} > /dev/null 2>&1
}

# ***

git_HEAD_commit_sha () {
  git rev-parse HEAD
}

# Use --first-parent to stick to commits in the branch you're on, and
# not to consider a feature branch you merged that maybe (a rare case)
# derived from a parentless commit, in which case rev-list would output
# more than one commit object. (Oddly, my landonb/homefries.git project
# has such a case early in its history.)
git_first_commit_sha () {  # aka git_root_commit_sha, perhaps
  git rev-list --max-parents=0 --first-parent HEAD
}

git_first_commit_message () {
  git --no-pager log --format=%s --max-parents=0 --first-parent HEAD
}

git_latest_commit_message () {
  git --no-pager log --format=%s -1 "${1:-HEAD}"
}

git_child_of () {
  git --no-pager log --reverse --ancestry-path --format='%H' ${1}..HEAD \
    | head -1
}

# Some obvious and non-obvious ways to get the parent to a commit:
#   git rev-parse $1^
#   git --no-pager log --pretty=%P -n 1 $1
#   git cat-file -p $1 | grep -e "^parent " | awk '{ print $2 }'
# - If given first commit (or first-commit^):
#   - git-rev-parse echos query and prints message to stderr.
#   - git-log prints nothing.
#   - git-cat-file prints commit meta without parent line,
#     so awk prints nothing.
#   Note that git-rev-parse is the least best choice, if you want to
#   just not print anything if no parent -- it not only prints a long
#   error message, but it echoes the query back to stdout, so you'd have
#   to store the query, test $?, then print the query if not an error.
#   - Of the other two, git-log's error message when the commit object is
#     unknown is 3 lines long and super not helpful: it spends 2 lines
#     telling you to use '--' to separate paths, and the first line leads
#     with the confusing "fatal: ambiguous argument". Or at least it's
#     confusing to me, like, "What's 'ambiguous'? Oh, it's the object ref.
#     that's not a real object." Which is why I like cat-file's error the
#     best: "fatal: Not a valid object name 'foo'".
git_parent_of () {
  git cat-file -p $1 | grep -e "^parent " | awk '{ print $2 }'
}

# See also git-extra's git-count, which counts to HEAD, and with --all
# print counts per author.
git_number_of_commits () {
  local gitref="${1:-HEAD}"

  git rev-list --count "${gitref}"
}

# ***

git_remote_exists () {
  local remote="$1"

  git remote get-url ${remote} &> /dev/null
}

git_remote_branch_exists () {
  local remote_branch="$(_git_print_remote_branch_unambiguous "${1}" "${2}")"

  # SHOWS: [branchname] <most recent commit message>
  git show-branch "${remote_branch}" &> /dev/null
}

git_remote_branch_object_name () {
  local remote_branch="$(_git_print_remote_branch_unambiguous "${1}" "${2}")"

  # Prints SHA1.
  git rev-parse "${remote_branch}" 2> /dev/null
}

# Prints refs/remotes/<remote>/<branch>.
_git_print_remote_branch_unambiguous () {
  local remote="$1"
  local branch="$2"

  local remote_branch=""

  if [ -z "${branch}" ]; then
    # Assume caller passed in remote/branch.
    remote_branch="${remote}"
  else
    remote_branch="${remote}/${branch}"
  fi

  printf "refs/remotes/$(echo "${remote_branch}" | sed 's#^refs/remotes/##')"
}

git_remote_default_branch () {
  local remote="$1"

  git remote show ${remote} | grep 'HEAD branch' | cut -d' ' -f5
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# MEH/2022-12-16: This seems like a problem that's likely been solved
# many times before: Given a remote branch name, how to parse out the
# remote name and parse out the branch name. But I don't know of any
# solutions, and a quick search didn't enlighten me, so I baked my own.

# The `dirname` or upstream branch references (aka rootname).
git_upstream_parse_remote_name () {
  # echo "$1" | sed 's/\/.*$//'
  # echo "$1" | sed -E 's#^(refs/remotes/)?([^/]+)/.*$#\2#'
  # echo "$1" | sed 's#^refs/remotes/##' | sed 's/\/.*$//'
  git_upstream_parse_names true false "$@"
}

# The `basename` or upstream branch references (aka rootless).
git_upstream_parse_branch_name () {
  # echo "$1" | sed 's/^[^\/]*\///'
  # echo "$1" | sed -E 's#^(refs/remotes/)?[^/]+/##'
  # echo "$1" | sed 's#^refs/remotes/##' | sed 's/^[^\/]*\///'
  git_upstream_parse_names false true "$@"
}

git_upstream_parse_names () {
  local print_remote="${1:-false}"
  local print_branch="${2:-false}"
  local upstream_ref="$3"

  local deprefixed="$(echo "${upstream_ref}" | sed 's#^refs/remotes/##')"
  local remote_name="$(_git_parse_path_rootname "${deprefixed}")"
  local branch_name="$(_git_parse_path_rootless "${deprefixed}")"

  # ***

  if [ "${remote_name}" = "refs" ]; then
    >&2 echo "ERROR: Cannot parse non-remotes refs/ upstream reference: ${upstream_ref}"

    return 1
  fi

  # If one, then both, so say we all.
  # - These tests cover inputs like "foo" and "bar/".
  if false\
    || [ -z "${remote_name}" ] \
    || [ -z "${branch_name}" ] \
    || [ "${remote_name}" = "${deprefixed}" ] \
    || [ "${branch_name}" = "${deprefixed}" ]; \
  then
    return 0
  fi

  # ***

  ! ${print_remote} || printf "${remote_name}"
  ! ${print_branch} || printf "${branch_name}"
}

# The other opposite of `dirname`, `rootname`.
_git_parse_path_rootname () {
  echo "$1" | sed 's#/.*$##'
}

# The other opposite of `basename`, something progenitor? `progname`?
_git_parse_path_rootless () {
  echo "$1" | sed 's#^[^/]*/##'
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Note that Git resolves symlinks, e.g., what cd'ing to project root
# and running `realpath .`, `readlink -f .`, or `pwd -P` would show.
git_project_root () {
  git_project_root_absolute
}

git_project_root_absolute () {
  # Same output as git-extras's `git root`.
  git rev-parse --show-toplevel
}

git_project_root_relative () {
  (cd "./$(git rev-parse --show-cdup)" && pwd -L)
}

# Print empty string if at project root;
# print '../'-concatenated path to project root;
# or git prints to stderr if not a Git project.
print_parent_path_to_project_root () {
  local depth_path="$(git root -r)"
  # SPIKE/2022-12-11: Confirm this is what I see:
  # - ✓ `git root -r` returns empty string @linux.
  # - ? On @macOS, does it return '.'?
  ( [ "${depth_path}" = "." ] || [ "${depth_path}" = "" ] ) \
    && return 0 || true

  printf $"{depth_path}" | sed "s#\([^/]\+\)#..#g"
}

# Check that the current directory exists in a Git repo.
git_insist_git_repo () {
  # A naive approach is to check for the .git/ directory.
  # Another approach is to check --show-toplevel, e.g.,
  #   git rev-parse --show-toplevel &> /dev/null
  # Except both those approaches are truthy before `git init`.
  # A better naive approach might check if there are any refs:
  #   command ls -A ".git/refs/heads"
  # And the better porcelain command checks for HEAD.
  git rev-parse --abbrev-ref HEAD &> /dev/null && return 0

  local projpath="${1:-$(pwd)}"

  local errmsg
  if git rev-parse --show-toplevel &> /dev/null; then
    errmsg="Specified Git project has no commits"
  else
    errmsg="Specified directory not a Git project"
  fi

  >&2 echo "ERROR: ${errmsg}: ${projpath}"

  return 1
}

git_insist_pristine () {
  ! test -n "$(git status --porcelain)" && return 0

  local projpath="${1:-$(pwd)}"

  >&2 echo
  >&2 echo "ERROR: Working directory not tidy."
  >&2 echo "- HINT: Try:"
  >&2 echo
  >&2 echo "   cd \"${projpath}\" && git status"
  >&2 echo

  return 1
}

git_nothing_staged () {
  git diff --cached --quiet
}

git_insist_nothing_staged () {
  ! git_nothing_staged || return 0

  local projpath="${1:-$(pwd)}"

  >&2 echo
  >&2 echo "ERROR: Working directory has staged changes."
  >&2 echo "- HINT: Try:"
  >&2 echo
  >&2 echo "   cd \"${projpath}\" && git status"
  >&2 echo

  return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# A few ideas to check for valid SHA1 object.
#
#   # Check that reference resolves to a commit.
#   test "$(git cat-file -t "${ref_name}")" == commit
#
#   # Check that a reference is valid, printing on error only, e.g.,
#   #   fatal: Not a valid object name {}
#   git cat-file -e "${ref_name}^{commit}" > /dev/null
#
#   # Check valid ref, printing on success only (the resolved SHA1).
#   [ -z "$(git rev-parse -q --verify "${ref_name}^{commit}")" ]
#
# https://stackoverflow.com/questions/18515488/
#   how-to-check-if-the-commit-exists-in-a-git-repository-by-its-sha-1
#
# This is similar to checking a ref name by type of object, e.g.,
#
#   git show-ref --verify --quiet refs/heads/${ref_name}
#   git show-ref --verify --quiet refs/remotes/${ref_name}
#   git show-ref --verify --quiet refs/tags/${ref_name}
#
# except that it works on a SHA1, and this check won't tell us the
# object type. It only validates if the object name is valid or not.

git_is_valid_ref () {
  local gitref="$1"

  [ -n "$(git rev-parse --verify --quiet "${gitref}^{commit}")" ]
}

git_object_is_commit () {
  [ "$(git cat-file -t "$1" 2> /dev/null)" = "commit" ]
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

git_versions_tagged_for_commit () {
  local hash="$1"

  if [ -z "${hash}" ]; then
    hash="$(git_HEAD_commit_sha)"
  fi

  # Without -d/--dereference, hash shown is tag object, not commit.
  # With -d, prints 2 lines per tag, e.g., suppose 2 tags on one commit:
  #   $ git show-ref --tags -d
  #   af6ec9a9ae01592d36d06917e47b8ee9822178a7 refs/tags/v1.2.3
  #   7ca83ee766d31181b34e6aafb340f537e2cc0d6f refs/tags/v1.2.3^{}
  #   2aadd869b4ff4acc945b073a70be7e6573341ebc refs/tags/v1.2.3a3
  #   7ca83ee766d31181b34e6aafb340f537e2cc0d6f refs/tags/v1.2.3a3^{}
  # (Note that the pattern matches looser than semantic versioning spec,
  #  e.g., "v1.2.3a3" is not valid SemVer, but "1.2.3-a3" is.)
  # Where:
  #   $ git cat-file -t af6ec9a9ae01592d36d06917e47b8ee9822178a7
  #   tag
  #   $ git cat-file -t 7ca83ee766d31181b34e6aafb340f537e2cc0d6f
  #   commit
  # So search on the known commit hash, which returns refs/tags/<tag>^{},
  # then isolate just the tag -- and match only tags with a leading digit
  # (assuming that indicates a version tag, to exclude non-version tags).
  git show-ref --tags -d \
    | grep "^${hash}.* refs/tags/v\?[0-9]" \
    | command sed \
      -e 's#.* refs/tags/v\?##' \
      -e 's/\^{}//'
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Return the latest version tag (per Semantic Versioning rules).

# Note that git-tag only accepts a glob(7), and not a regular expression,
# so we'll filter with grep to pick out the latest version tag. (Meaning,
# the glob is unnecessary, because grep does all the work, but whatever.)

# Use git-tag's simple glob to first filter on tags starting with 'v' or 0-9.
GITSMART_GLOB_VERSION_TAG='[v0-9]*'
# DEV: Copy-paste test snippet:
#   git --no-pager tag -l "${GITSMART_GLOB_VERSION_TAG}"

# Match groups: \1: major
#               \2: minor
#               \3: \4\5\6
#               \4: patch
#               \5: separator (non-digit)
#               \6: pre-release and/or build, aka the rest.
# Note that this is not strictly Semantic Versioning compliant:
# - It allows a leading 'v', which is a convention some people use
#   (and that the author used to use but has since stopped using);
# - It allows for a pre-release/build part that includes characters
#   that SemVer does not allow, which is limited to [-a-zA-Z0-9].
GITSMART_RE_VERSPARTS='^v?([0-9]+)\.([0-9]+)(\.([0-9]+)([^0-9]*)(.*))?'

git_latest_version_basetag () {
  git tag -l "${GITSMART_GLOB_VERSION_TAG}" |
    grep -E -e "${GITSMART_RE_VERSPARTS}" |
    /usr/bin/env sed -E "s/${GITSMART_RE_VERSPARTS}/\1.\2.\4/" |
    sort -r --version-sort |
    head -n1
}

latest_version_fulltag () {
  local basevers="$1"

  git tag -l "${basevers}*" -l "v${basevers}*" |
    /usr/bin/env sed -E "s/${GITSMART_RE_VERSPARTS}/\6,\1.\2.\4\5\6/" |
    sort -r -n |
    head -n1 |
    /usr/bin/env sed -E "s/^[^,]*,//"
}

git_latest_version_tag () {
  local basevers="$(git_latest_version_basetag)"

  # See if basevers really tagged or if gleaned from alpha.
  if git show-ref --tags -- "${basevers}" > /dev/null; then
    fullvers="${basevers}"
  else
    # Assemble alpha-number-prefixed versions to sort and grab largest alpha.
    fullvers="$(latest_version_fulltag "${basevers}")"
  fi

  [ -z "${fullvers}" ] || echo "${fullvers}"
}

# ***

git_latest_version_basetag_safe () {
  git_latest_version_basetag || printf '0.0.0-✗-g0000000'
}

git_since_most_recent_commit_epoch_ts () {
  git --no-pager log -1 --format=%at HEAD 2> /dev/null
}

git_since_latest_version_tag_epoch_ts () {
  # Note that the "described" tag output (e.g., 0.12.0-828-g0266e06) is a
  # valid revision (per `man 7 gitrevisions`), which can be fed to git-log.
  # - And to compute a time delta from then to now, get seconds since epoch:
  #   git help log:
  #     %at: author date, UNIX timestamp
  git --no-pager \
    log -1 \
    --format=%at \
    "$(git_latest_version_basetag_safe)" \
    2> /dev/null
}

git_since_git_init_commit_epoch_ts () {
  # Note that the "described" tag output (e.g., 0.12.0-828-g0266e06) is a
  # valid revision (per `man 7 gitrevisions`), which can be fed to git-log.
  # - And to compute a time delta from then to now, get seconds since epoch:
  #   git help log:
  #     %at: author date, UNIX timestamp
  # NOTE: rev-list outputs in reverse chronological order, so oldest commit
  #       is last; use tail to grab it.
  git --no-pager \
    log -1 \
    --format=%at \
    "$(git_first_commit_sha)" \
    2> /dev/null
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

github_purge_release_and_tags_of_same_name () {
  # (lb): I pulled this function from landonb/release-ghub-pypi,
  #       but its environs still assumed:
  # Mandatory:
  #   R2G2P_REMOTE
  #   RELEASE_VERSION
  #   R2G2P_COMMIT
  # Optional:
  #   R2G2P_GHUB_CLOBBER_CERTIFIED    defaults false
  #   SKIP_PROMPTS                    defaults false
  #
  # Side-effects:
  #   R2G2P_DO_PUSH_TAG               set to false|true.

  # Reentrant support: If previously tagged and released, remove the
  # GitHub release if user wants, and remove tag from remote if points
  # to different commit and user approves.

  # See also, for a list of all tags on a remote, e.g., the one named 'release':
  #   git ls-remote --tags release
  # Note that we can restrict to tags with a fuller path, or with an --option.
  #   git ls-remote ${R2G2P_REMOTE} refs/tags/${RELEASE_VERSION}
  #   git ls-remote ${R2G2P_REMOTE} --tags ${RELEASE_VERSION}
  #   git ls-remote ${R2G2P_REMOTE} --tags refs/tags/${RELEASE_VERSION}
  # NOTE: This call takes a moment. (lb): Must be contacting the remote?
  # NOTE: Use default `cut` delimiter, TAB.
  local remote_tag_hash
  remote_tag_hash="$(git ls-remote --tags ${R2G2P_REMOTE} ${RELEASE_VERSION} | cut -f1)"

  printf '%s' \
    "Send remote request: ‘git ls-remote --tags ${R2G2P_REMOTE} ${RELEASE_VERSION}’..."
  printf '%s\n' " ${remote_tag_hash}"

  local tag_commit_hash
  R2G2P_DO_PUSH_TAG=false
  if [ -z "${remote_tag_hash}" ]; then
    R2G2P_DO_PUSH_TAG=true
  else
    tag_commit_hash="$(git rev-list -n 1 ${remote_tag_hash})"
    if [ "${tag_commit_hash}" = "${R2G2P_COMMIT}" ]; then
      # The remote tag has the same commit hash as the current release.
      # No need to send tag again, unless clobbering GitHub release,
      # in which case remove the tag, which removes the lightweight (non-annotated)
      # release from https://github.com/user/repo/releases that's automatically
      # generated according to tags ((lb): or whatever; I'm not quite sure how
      # it works, just that deleting the tag clears the entry).
      ${R2G2P_GHUB_CLOBBER_CERTIFIED:-false} && R2G2P_DO_PUSH_TAG=true
    else
      echo
      echo "🚨 ATTENTION 🚨: The tag on ‘${R2G2P_REMOTE}’ refers to a different commit."
      echo
      echo "    release tag ref.  ${R2G2P_COMMIT}"
      echo "    remote tag ref..  ${tag_commit_hash}"
      echo

      printf %s "Would you like to delete the old remote tag? [y/N] "

      ${SKIP_PROMPTS:-false} && the_choice='n' || read -e the_choice

      if [ "${the_choice}" = "y" ] || [ "${the_choice}" = "Y" ]; then
        R2G2P_DO_PUSH_TAG=true
      else
        >&2 echo
        >&2 echo "ERROR: Tag ‘${RELEASE_VERSION}’ mismatch on ‘${R2G2P_REMOTE}’."
        >&2 echo

        return 1
      fi
    fi
  fi

  if ${R2G2P_DO_PUSH_TAG} && [ -n "${tag_commit_hash}" ]; then
    # (lb): I realize there's a less obtuse syntax to delete tags, e.g.,
    #           git push --delete ${R2G2P_REMOTE} ${RELEASE_VERSION}
    #       But that syntax might also delete a branch of the same name.
    #       So be :obtuse, and be specific about what's being deleted.
    local gpr_args="${R2G2P_REMOTE} :refs/tags/${RELEASE_VERSION}"

    echo "Deleting Remote Tag: ‘${gpr_args}’"

    # Uncomment to debug:
    #   set -x  # xtrace_beg
    git push ${gpr_args}
    #   set +x  # xtrace_end
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

