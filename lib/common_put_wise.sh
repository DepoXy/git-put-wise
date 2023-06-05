#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PW_ARCHIVE_MANIFEST=".manifest.pw"

# echo "too-salty-send-it-back--.return-receipt" | sha1sum
PW_RETURN_RECEIPT_CRYPT=".4c1e6f1"
PW_RETURN_RECEIPT_PLAIN=".return-receipt"

PW_PATCHES_REPO_HINT=".gpw"

PW_PATCHES_REPO_MESSAGE_INIT="🥨"
# `tig` won't display some emoji characters.
# - `tig` shoots blanks for these chars: 🥬, 🫑
# - `tig` is compliant with these chars: 🥨, 🌽
PW_PATCHES_REPO_MESSAGE_CHCHCHANGES="🌽"

PW_PROJECT_PATH_SALT="too-salty-send-it-back"

# We'd probably be fine with shorter SHA, like 7 character, but 11 or 12
# should mean no two should ever overlap.
# - "Linux kernel [w/ 450k+ commits, 3.6m+ objects has no two
#    SHA-1s that overlap more than the first 11 characters]
#   https://stackoverflow.com/questions/34764195/
#     how-does-git-create-unique-commit-hashes-mainly-the-first-few-characters
PW_SHA1SUM_LENGTH=12

PW_ELEVENSES=11

PW_USER_CANCELED_GOODBYE="Be seeing you"

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# The prefixes used by sort-by-scope to identify scoped and private commits.
# - Used by seq-editor-sort-by-scope-protected-private.
export SCOPING_PREFIX="${SCOPING_PREFIX:-PROTECTED: }"
export PRIVATE_PREFIX="${PRIVATE_PREFIX:-PRIVATE: }"

# *** Customizable branch names

# E.g., 'private'.
export LOCAL_BRANCH_PRIVATE="${LOCAL_BRANCH_PRIVATE:-private}"

# E.g., 'entrust/scoping'.
export REMOTE_BRANCH_SCOPING="${REMOTE_BRANCH_SCOPING:-entrust/scoping}"

# E.g., 'release'.
export LOCAL_BRANCH_RELEASE="${LOCAL_BRANCH_RELEASE:-release}"
# E.g., 'publish/release'.
export REMOTE_BRANCH_RELEASE="${REMOTE_BRANCH_RELEASE:-publish/${LOCAL_BRANCH_RELEASE}}"

# *** Separated remote names and remote branches (generated)

# E.g., 'entrust'.
export SCOPING_REMOTE_NAME="$(git_upstream_parse_remote_name "${REMOTE_BRANCH_SCOPING}")"
# E.g., 'scoping'.
export SCOPING_REMOTE_BRANCH="$(git_upstream_parse_branch_name "${REMOTE_BRANCH_SCOPING}")"

# E.g., 'publish'.
export RELEASE_REMOTE_NAME="$(git_upstream_parse_remote_name "${REMOTE_BRANCH_RELEASE}")"
# E.g., 'release'.
export RELEASE_REMOTE_BRANCH="$(git_upstream_parse_branch_name "${REMOTE_BRANCH_RELEASE}")"

# *** Patches repo branch name

# The named used for the PW_PATCHES_REPO branch (it really doesn't matter,
# but patches may contain scoping commits, so we'll name it that).
export PATCHES_REPO_BRANCH="${PATCHES_REPO_BRANCH:-scoping}"

# *** Tag names

export PW_TAG_APPLIED_FORMAT="${PW_TAG_APPLIED_FORMAT:-pw/%s/in}"
export PW_TAG_ARCHIVED_FORMAT="${PW_TAG_ARCHIVED_FORMAT:-pw/%s/out}"
export PW_TAG_STARTING_FORMAT="${PW_TAG_STARTING_FORMAT:-pw/%s/work}"
export PW_TAG_TMP_APPLY_FORMAT="${PW_TAG_TMP_APPLY_FORMAT:-pw/%s/apply}"
export PW_TAG_TMP_PULL_FORMAT="${PW_TAG_TMP_PULL_FORMAT:-pw/%s/pull}"

export PW_TAG_ONTIME_APPLY="${PW_TAG_ONTIME_APPLY:-pw-apply-here}"

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

__DRYRUN () { >&2 echo "$@"; }

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

maybe_create_patches_repo_and_canonicalize_path () {
  local insist_repo=${1:false}

  ! ${insist_repo} || must_verify_patches_repo_specified

  must_verify_patches_repo_is_directory_if_specified

  ! ${insist_repo} || must_ensure_patches_repo_exists

  must_canonicalize_path_and_verify_nothing_staged
}

must_verify_patches_repo_specified () {
  if [ -z "${PW_PATCHES_REPO}" ]; then
    >&2 echo "ERROR: Please specify the patches archive repo" \
      "using -T/--patches-repo or the PW_PATCHES_REPO environ."

    exit 1
  fi

  return 0
}

must_verify_patches_repo_is_directory_if_specified () {
  [ -n "${PW_PATCHES_REPO}" ] || return 0

  if [ -e "${PW_PATCHES_REPO}" ] && [ ! -d "${PW_PATCHES_REPO}" ]; then
    >&2 echo "ERROR: The patches archive repo is not a" \
      "directory: “${PW_PATCHES_REPO}”"

    exit 1
  fi

  return 0
}

must_ensure_patches_repo_exists () {
  maybe_prompt_user_and_prepare_patches_repo

  local before_cd="$(pwd -L)"

  cd "${PW_PATCHES_REPO}"

  must_verify_looks_like_our_repo

  cd "${before_cd}"
}

maybe_prompt_user_and_prepare_patches_repo () {
  if [ -d "${PW_PATCHES_REPO}" ] && \
    [ -n "$(/bin/ls -A "${PW_PATCHES_REPO}")" ]; \
  then
    return 0
  fi

  if [ -e "${PW_PATCHES_REPO}" ] && [ ! -d "${PW_PATCHES_REPO}" ]; then
    >&2 echo "ERROR: Patches repo exists but not directory: “${PW_PATCHES_REPO}”"

    exit 1
  fi

  prompt_user_to_create_patches_repo "${PW_PATCHES_REPO}" || return 1

  maybe_prompt_user_to_create_parent_path

  create_patches_parents_and_repo
}

maybe_prompt_user_to_create_parent_path () {
  local parent_dir="$(dirname "${PW_PATCHES_REPO}")"

  if [ ! -d "${parent_dir}" ]; then
    prompt_user_to_create_parent_path "${parent_dir}" || return 1
  fi

  return 0
}

create_patches_parents_and_repo () {
  mkdir -p "${PW_PATCHES_REPO}"

  local before_cd="$(pwd -L)"

  cd "${PW_PATCHES_REPO}"

  git_init_patches_repo

  cd "${before_cd}"
}

must_verify_looks_like_our_repo () {
  local first_message=""

  first_message="$(git_first_commit_message)"

  # Two ruthless checks to confirm that repo
  # was created by git_init_patches_repo.

  # 🥨
  if [ "${first_message}" != "${PW_PATCHES_REPO_MESSAGE_INIT}" ]; then
    >&2 echo "ERROR: Patches repo's first commit message not ours: “${first_message}”"
    >&2 echo "- Expecting: “${PW_PATCHES_REPO_MESSAGE_INIT}”"

    exit 1
  fi

  local emptiness="${PW_PATCHES_REPO_HINT}"

  if [ ! -f "${emptiness}" ]; then
    # Said the Professor.
    >&2 echo "ERROR: Oh the vast emptiness! Nothing at: “${emptiness}”."

    exit 1
  fi

  # Extra-worried. (Not worried enough to `pwd -P`?)
  local cur_dir="$(pwd -L)"

  local home_relative_path
  home_relative_path="$(echo "${cur_dir}" | sed -E "s#^${HOME}(/|$)#\1#")"
  # KLUGE/2023-05-28: Vim Bash highlight bug: Backslash &/or pound  ↑ ↑")"

  if [ "${home_relative_path}" = "${cur_dir}" ]; then
    >&2 echo "ERROR: You need to specify a path under \$HOME, sorry, eh."

    exit 1
  fi

  return 0
}

must_canonicalize_path_and_verify_nothing_staged () {
  # Both --archive and --apply* commit to the patches repo.
  # - On --archive, the new archive will be added.
  # - On --apply*, the processed archive(s) will be removed,
  #     and a return receipt will be added for the put-wise
  #     "remote".
  local before_cd="$(pwd -L)"

  cd "${PW_PATCHES_REPO}"

  git_insist_git_repo

  PW_PATCHES_REPO="$(git_repo_canonicalize_environ_path "PW_PATCHES_REPO")"

  git_insist_nothing_staged

  cd "${before_cd}"
}

prompt_user_to_create_patches_repo () {
  local patches_path="$1"

  echo "The patches repo has not been created yet."
  echo "- There's nothing at: ${patches_path}"
  printf "Would you like to create the project? [Y/n] "

  local key_pressed
  local opt_chosen
  prompt_read_single_keypress "y" "n"
  [ "${opt_chosen}" = "y" ] && return 0 || return 1
}

prompt_user_to_create_parent_path () {
  local parent_dir="$1"

  echo
  echo "The parent path has not been created yet."
  echo "- There's nothing at: ${parent_dir}"
  printf "Would you like to create the directory path? [Y/n] "

  local key_pressed
  local opt_chosen
  prompt_read_single_keypress "y" "n"
  [ "${opt_chosen}" = "y" ] && return 0 || return 1
}

git_init_patches_repo () {
  local emptiness="${PW_PATCHES_REPO_HINT}"

  git -c init.defaultBranch="${PATCHES_REPO_BRANCH}" init .
  touch "${emptiness}"
  git add "${emptiness}"
  # CXREF: git_first_commit_message
  # CALSO: PW_PATCHES_REPO_MESSAGE_CHCHCHANGES="🥬"
  git commit -q -m "${PW_PATCHES_REPO_MESSAGE_INIT}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

put_wise_reset_patches_repo () {
  if [ -e "${PW_PATCHES_REPO}" ] && [ ! -d "${PW_PATCHES_REPO}" ]; then
    >&2 echo "ERROR: Patches repo path not a directory: “${PW_PATCHES_REPO}”."

    exit 1
  fi

  if [ -d "${PW_PATCHES_REPO}" ]; then
    local before_cd="$(pwd -L)"

    cd "${PW_PATCHES_REPO}"

    if [ -z "$(/bin/ls -A "${PW_PATCHES_REPO}")" ]; then
      PW_PATCHES_REPO="$(pwd -L)"

      cd "${before_cd}"

      rmdir "${PW_PATCHES_REPO}"
    else
      # Me being paranoid.

      # Might be overcheckill.
      git_insist_git_repo

      PW_PATCHES_REPO="$(git_repo_canonicalize_environ_path "PW_PATCHES_REPO")"

      # Really being strict here, too.
      git_insist_nothing_staged

      # This is really what we care about.
      must_verify_looks_like_our_repo

      prompt_user_to_recreate_patches_repo "${PW_PATCHES_REPO}" || return 1

      cd "${before_cd}"

      # We've verified this path under ${HOME}, contains file `.gpw`,
      # and user okayed its destruction.
      # - Note that running this command from the patches repo results
      #   in user's terminal no longer being in a directory (until they
      #   `cd` somewhere else), but that's beyond our control.
      /bin/rm -rf "${PW_PATCHES_REPO}"
    fi
  fi

  maybe_prompt_user_to_create_parent_path

  create_patches_parents_and_repo
}

prompt_user_to_recreate_patches_repo () {
  local patches_repo="$1"

  echo
  echo "The patches repo directory exists and is non-empty."
  echo "- There's something(s) under: ${patches_repo}"
  printf "Still okay to remove and recreate the patches repo? [Y/n] "

  local key_pressed
  local opt_chosen
  prompt_read_single_keypress "y" "n"
  [ "${opt_chosen}" = "y" ] && return 0 || return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

git_repo_canonicalize_environ_path () {
  local envvar="$1"

  local before_cd="$(pwd -L)"

  # Note the git-root resolves symlinks in the path, but we want
  # user to be able to use symlinks, so they can use separate paths
  # on separate hosts.
  #  # cd "$(git_project_root)"
  local path_up_to_root="$(print_parent_path_to_project_root)"

  if [ -n "${path_up_to_root}" ]; then
    cd "${path_up_to_root}"
  fi

  # Sorta canonicalized. We don't `pwd -P`, so user can use symlinks.
  # But we want to work with full paths.
  local canonicalized_root="$(pwd -L)"

  cd "${before_cd}"

  if [ "${!envvar}" != "${canonicalized_root}" ]; then
    >&2 debug "Canonicalizing ${envvar} → “${!envvar}” ⇒ “${canonicalized_root}”"
  else
    >&2 debug "✓ed Canonical: ${envvar} ⇒ “${!envvar}”"
  fi

  printf "${canonicalized_root}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Every action calls this function.
# - --apply calls this function if user specified project repo,
#   and --apply always calls its own insist-git and not-protected.
# - --archive, --push, and --pull each call this function immediately.
must_cd_project_path_and_verify_repo () {
  PW_PROJECT_PATH="${PW_PROJECT_PATH:-.}"

  if [ ! -d "${PW_PROJECT_PATH}" ]; then
    >&2 echo "ERROR: Not a directory: ${PW_PROJECT_PATH}"

    exit 1
  fi

  cd "${PW_PROJECT_PATH}"

  git_insist_git_repo

  PW_PROJECT_PATH="$(git_repo_canonicalize_environ_path "PW_PROJECT_PATH")"

  cd "${PW_PROJECT_PATH}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_not_be_patches_repo () {
  project_path_same_as_patches_repo || return 0

  >&2 echo "ERROR: This command does not work on the patches repo: “${PW_PATCHES_REPO}”"

  exit 1
}

project_path_same_as_patches_repo () {
  # Assumes both current directory and patches repo at git_project_root,
  # otherwise you could trick git-put-wise into running git-format-patch
  # or git-am on the patches repo.
  # - PW_PROJECT_PATH sorta canonicalized in must_cd_project_path_and_verify_repo.
  # - PW_PATCHES_REPO sorta canonicalized in git_repo_canonicalize_environ_path.
  # But neither resolves symlinks.
  local project_path_abs
  local patches_repo_abs

  # "The extra echo . takes care of the rare case where one of the targets has
  #  a file name ending with a newline: if the newline was the last character
  #  of the command substitution, it would be stripped, so the snippet would
  #  incorrectly report that foo␤ is the same as foo."
  # - REFER/2022-11-19: https://unix.stackexchange.com/questions/206973/
  #     how-to-find-out-whether-two-directories-point-to-the-same-location
  #   - One could mount same dir at two sep paths to fool this check,
  #     among other shortfalls, but it's good enough for us, even the
  #     echo-dot protects against the most unlikeliest of scenarios.
  project_path_abs="$(cd -- "${PW_PROJECT_PATH}" && pwd -P; echo .)"
  patches_repo_abs="$(cd -- "${PW_PATCHES_REPO}" && pwd -P; echo .)"

  [ "${project_path_abs}" = "${patches_repo_abs}" ] \
    && return 0 \
    || return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# `put-wise --sha`
#
# CPYST:
#   . ~/.kit/git/git-put-wise/deps/sh-git-nubs/bin/git-nubs.sh
#   . ~/.kit/git/git-put-wise/lib/common_put_wise.sh
#   print_project_path_ref

# Aka `pw sha`.
put_wise_print_sha_or_sha () {
  local path="$(git_project_root_relative)"

  if [ -n "${PW_PROJECT_PATH}" ]; then
    # Hrmm, `realpath -s .` doesn't preserve parent name if symlink,
    # so `cd` and `pwd` instead.
    path="$(cd "${PW_PROJECT_PATH}" && pwd -L)"
  fi

  printf "%s %s\n" \
    "$(print_project_path_normalized "${path}")" \
    "$(print_project_path_ref "${path}")"
}

print_project_path_ref () {
  local path="${1:-$(git_project_root_relative)}"

  print_sha "$(print_project_path_normalized "${path}")"
}

print_project_path_normalized () {
  local path="$1"

  local project_path

  project_path="$(echo ${path} | sed -E "s#^${HOME}(/|$)#\\\$HOME\1#")"
  # KLUGE/2023-05-28: Vim Bash highlight bug: \ &/or #           ↑ ↑")"

  printf "%s" "${project_path}"
}

print_sha () {
  local key="$1"

  shorten_sha "$( \
    printf "${PW_PROJECT_PATH_SALT}--${key}" \
      | sha1sum | awk '{ print $1 }'
  )"
}

shorten_sha () {
  printf "$1" | sed -E 's/^(.{'${PW_SHA1SUM_LENGTH}'}).*/\1/g'
}

substitute_home_tilde () {
  echo "$1" | sed -E "s#^${HOME}(/|$)#~\1#"
  # KLUGE/2023-05-28: Vim high issue:  ↑ ↑"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# I'm not sure if I care this much... but it also lets later code make
# assumptions we guarantee here, such as the archive being unpacked is
# committed to the patches repo. This lets put-wise git-rm the archive
# after applying it, without first checking if working in patches repo.
must_verify_patches_repo_archive () {
  local archive_file="$(basename "$1")"

  local before_cd="$(pwd -L)"

  cd "${PW_PATCHES_REPO}"

  local relative_path="$(echo "${archive_file}" | sed -E "s#^${PW_PATCHES_REPO}/##")"

  if ! print_repo_archive_list | grep --quiet -e "^${relative_path}$"; then
    >&2 echo "ERROR: Specified patches archive not committed to patches repo."

    exit 1
  fi

  cd "${before_cd}"
}

print_repo_archive_list () {
  local option="$1"
  [ $# -eq 0 ] || shift

  git ls-files ${option} -- \
    ":!:README.rst" \
    ":!:${PW_PATCHES_REPO_HINT}" \
    ":!:*${PW_RETURN_RECEIPT_CRYPT}" \
    ":!:*${PW_RETURN_RECEIPT_PLAIN}" \
    "$@"
}

print_repo_return_receipts () {
  local option="$1"
  [ $# -eq 0 ] || shift

  git ls-files ${option} -- \
    ":!:README.rst" \
    ":!:${PW_PATCHES_REPO_HINT}" \
    "*${PW_RETURN_RECEIPT_CRYPT}" \
    ":!:*${PW_RETURN_RECEIPT_PLAIN}" \
    "$@"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

format_pw_tag_applied () {
  local patch_branch="$1"

  # E.g., 'pw/private/in'
  printf "${PW_TAG_APPLIED_FORMAT}" "${patch_branch}"
}

format_pw_tag_archived () {
  local patch_branch="$1"

  # E.g., 'pw/private/out'
  printf "${PW_TAG_ARCHIVED_FORMAT}" "${patch_branch}"
}

format_pw_tag_starting () {
  local patch_branch="$1"

  # E.g., 'pw/private/work'
  printf "${PW_TAG_STARTING_FORMAT}" "${patch_branch}"
}

format_pw_tag_ephemeral_apply () {
  local patch_branch="$1"

  # E.g., 'pw/private/apply'
  printf "${PW_TAG_TMP_APPLY_FORMAT}" "${patch_branch}"
}

format_pw_tag_ephemeral_pull () {
  local patch_branch="$1"

  # E.g., 'pw/private/pull'
  printf "${PW_TAG_TMP_PULL_FORMAT}" "${patch_branch}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

confirm_state_and_resort_to_prepare_branch () {
  local starting_ref="$1"

  # Query the upstream SHA and verify its in the
  # current branch history, and not the first commit.
  local starting_sha="$(git rev-parse "${starting_ref}")"

  if [ -z "${starting_sha}" ]; then
    >&2 echo "ERROR: Unexpected: No SHA found for gitref “${starting_ref}”"

    exit 1
  fi

  # The callee will emit "HEAD" if starting_sha diverged from HEAD and --force.
  local starting_sha_or_HEAD
  starting_sha_or_HEAD="$(must_confirm_shares_history_with_head "${starting_sha}")"

  # "Stash" (WIP-commit) untidy changes, marked as PRIVATE, so rebase will
  # leave as most recent commit (and won't resort below other commits).
  local pop_after
  pop_after=$(maybe_stash_changes)

  # Sort commits by "scope" (according to message prefixes).
  git_sort_by_scope "${starting_sha_or_HEAD}"

  maybe_unstash_changes ${pop_after}
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Check that the current branch and its upstream share a common history
# (i.e., you haven't rebased work you previously pushed, otherwise user
#  needs to sort-by-scope manually, and then pass us a starting gitref).
# CXREF: must_confirm_commit_at_or_behind_commit
must_confirm_shares_history_with_head () {
  local ref_sha="$1"
  local ref_name="$2"

  # Note the name won't include the refs/ prefix.
  #   $ git name-rev 9912e198f7bb52e746cb9cbd93a57379e5553eca
  #   9912e198f7bb52e746cb9cbd93a57379e5553eca remotes/publish/foo/bar
  [ -n "${ref_name}" ] || ref_name=$(git name-rev "${ref_sha}" | awk '{ print $2 }')

  # I don't think this would ever happen. Just being double-checky.
  if [ -z "${ref_name}" ]; then
    >&2 echo "ERROR: Unexpected: No name found from SHA “${ref_sha}”"

    exit 1
  fi

  local head_sha
  head_sha="$(git rev-parse HEAD)"

  # Check if starting-from also at HEAD.
  if [ "${ref_sha}" = "${head_sha}" ]; then
    >&2 echo "Nothing to do: Already up-to-date with “${ref_name}”"

    # This function is called when pulling changes for a single project,
    # or when pushing changes or archiving patches for a single project.
    # This function is not called to work on more than one project, so
    # returning here is fine (albeit a little short-circuity, I admit).
    ${PW_OPTION_FAIL_ELEVENSES:-false} && exit ${PW_ELEVENSES} || exit 0
  fi

  local ancestor_sha
  ancestor_sha="$(git merge-base "${ref_sha}" "HEAD")"

  # If the common ancestor is at HEAD, the starting-from ref must be ahead.
  # - But since common ancestor is HEAD, there must not be
  #   any new commits, hence no patches to output.
  if [ "${ancestor_sha}" = "${head_sha}" ]; then
    >&2 echo "Nothing to do: The reference commit (“${ref_name}”) is ahead of the " \
      "current branch (“$(git_branch_name)”), but there's nothing new locally"

    ${PW_OPTION_FAIL_ELEVENSES:-false} && exit ${PW_ELEVENSES} || exit 0
  fi

  # We expect that the common ancestor is the upstream's HEAD,
  # otherwise something's amiss.
  if [ "${ancestor_sha}" != "${ref_sha}" ]; then
    # Check if revision shares history with HEAD.
    local first_commit_sha
    first_commit_sha="$(git_first_commit_sha)"

    local is_ancestor=true
    if [ "${ancestor_sha}" = "${first_commit_sha}" ]; then
      is_ancestor=false
    fi

    # 2023-01-16: Did I not know about --is-ancestor when I developed this code?
    # - Contract-by-design: Let's check that both approaches work.
    if ! git merge-base --is-ancestor "${ref_sha}" "HEAD"; then
      if ${is_ancestor} && ! ${PW_OPTION_FORCE_PUSH}; then
        # This is a DEV error (if this path is reachable).
        >&2 echo "ERROR: DEV: Unexpected: --is-ancestor signaled false, but merge-base compare was true"
      fi
      is_ancestor=false
    elif ! ${is_ancestor}; then
      # This is a DEV error (if this path is reachable).
      >&2 echo "ERROR: DEV: Unexpected: --is-ancestor signaled true, but merge-base compare was false"
    fi

    if ! ${is_ancestor}; then
      if ! ${PW_OPTION_FORCE_PUSH}; then
        >&2 echo "ERROR: The “${ref_name}” branch does not share history with HEAD."
        >&2 echo "- HINT: You probably rebased one of them."
        >&2 echo "  - You may need to call sort-by-scope with a specific SHA."
        >&2 echo "  - Then you probably need to force-push changes."
        >&2 echo "    ... unless you want to try rebasing atop upstream,"
        >&2 echo "    and then you could try running this command again."

        exit 1
      else
        >&2 info "FORCE: The divergent “${ref_name}” branch is being reset to HEAD"

        ref_sha="HEAD"
      fi
    else
      >&2 echo "ERROR: The upstream “${ref_name}” branch is ahead of the current branch."
      >&2 echo "- HINT: Pull or rebase upstream changes, and then try again."

      exit 1
    fi
  fi

  printf "%s" "${ref_sha}"

  return 0
}

# Reorder commits in prep. to diff.
git_sort_by_scope () {
  local sort_from_commit="$1"

  local head_sha_before_rebase
  head_sha_before_rebase="$(git rev-parse HEAD)"

  local rev_count_0
  rev_count_0="$(git_number_of_commits)"

  ${DRY_RUN} git sort-by-scope "${sort_from_commit}"

  local rev_count_1
  rev_count_1="$(git_number_of_commits)"

  if [ -n "$(git diff ${head_sha_before_rebase}..HEAD)" ] \
    || [ ${rev_count_0} -ne ${rev_count_1} ] \
  ; then
    # The sort-by-scope also prints warnings for these conditions, so
    # don't re-warn, but give the user the option to stop processing.
    # - 2023-01-18: Last place this prompt is called (used to be 3 places):
    prompt_user_to_continue_processing
  fi
}

prompt_user_to_continue_processing () {
  printf "Would you like to continue processing? [y/N] "

  local key_pressed
  local opt_chosen
  prompt_read_single_keypress "n" "y"
  [ "${opt_chosen}" = "y" ] && return 0 || return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

maybe_stash_changes () {
  # Make a WIP commit if we must.
  local wip_commit_message="${PRIVATE_PREFIX}WIP [git-put-wise]"

  local pop_after=false

  git_status_porcelain () { git status --porcelain=v1; }
  if [ -n "$(git_status_porcelain)" ]; then
    pop_after=true
    # See also `git wip`
    git add -A
    git commit -q --no-verify -m "${wip_commit_message}"
  fi

  echo ${pop_after}
}

maybe_unstash_changes () {
  local pop_after="$1"

  if ${pop_after}; then
    # Aka `git pop1`.
    git reset --quiet --mixed @~1
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_confirm_commit_at_or_behind_commit () {
  local early_commit="$1"
  local later_commit="${2:-HEAD}"
  local divergent_ok=${3:-false}
  local early_commit_name="$4"
  local later_commit_name="$5"

  make_friendly () {
    local sha="$1"
    local name="$2"

    local short="${sha}"
    if echo "${sha}" | grep -q -e "^[[:xdigit:]]\+$"; then
      short="$(shorten_sha "${sha}")"
    fi

    [ -z "${name}" ] && printf "${short}" || printf "“${name}” (${short})"
  }
  local early="$(make_friendly "${early_commit}" "${early_commit_name}")"
  local later="$(make_friendly "${later_commit}" "${later_commit_name}")"

  if [ -z "${early_commit}" ]; then
    # Somewhat overzealous check, because callers also check.
    >&2 echo "ERROR: Missing early_commit [DEV error]"

    exit 1
  elif ! git merge-base --is-ancestor "${early_commit}" "${later_commit}"; then
    local common_ancestor
    common_ancestor="$(git merge-base "${early_commit}" "${later_commit}")"

    debug "Common ancestor of ${early} and ${later} is $(shorten_sha "${common_ancestor}")"

    if [ "${common_ancestor}" = "$(git_commit_object_name ${early_commit})" ]; then
      # early_commit is at or behind later_commit.
      # 2023-01-16: Seems unlikely now that we're using --is-ancestor
      >&2 echo "ERROR: Unexpected: not --is-ancestor, but early_commit (${early}) is common_ancestor?"

      exit 1
    fi

    if ! git merge-base --is-ancestor "${later_commit}" "HEAD"; then
      # 2023-01-16: I don't think code is designed otherwise.
      >&2 echo "ERROR?: later_commit (${later}) not --is-ancestor HEAD"

      exit 1
    fi

    if git merge-base --is-ancestor "${early_commit}" "HEAD"; then
      # See following comments: I don't think this if-block is reachable.
      >&2 echo "ERROR: Not expecting early (${early}) --is-ancestor HEAD"

      if [ "${common_ancestor}" = "$(git_commit_object_name ${later_commit})" ]; then
        # later_commit behind early_commit?
        # 2023-01-16: With --is-ancestor check, this should *now* be unreachable
        # (or quite odd).
        >&2 echo "ERROR: Not expecting ${early} ahead of ${later}"

        exit 1
      else
        # This code should be unreachable: First --is-ancestor says
        # this is not true: early_commit <= later_commit. Next we
        # learned that later_commit <= HEAD. Now we know that
        # early_commit <= HEAD. So both early and later ancestors
        # of head, but early is after later. Which means the first
        # part of this if-block, which checks that later is the
        # common_ancestor, should run, not this else. So it would
        # really twist my mind if this else code ran (so I'd be
        # suprised if the out if-block:
        #   git merge-base --is-ancestor "${early_commit}" "HEAD"
        # was ever true.
        >&2 echo "ERROR: Not expecting ${early} ahead of ${later}"

        exit 1
      fi
    elif ! ${divergent_ok}; then
      >&2 echo "ERROR: These objects have diverged: ${early} and ${later}"

      exit 1
    fi
  fi

  return 0
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# CXREF/2022-10-27: must_find_matching_commit from git-smart:
#   ~/.kit/git/git-smart/bin/git-rebase-bubble-commit
find_oldest_commit_by_message () {
  local matchstr="$1"

  git --no-pager log --pretty=format:"%H" --grep "${matchstr}" | tail -1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

commit_changes_and_counting () {
  if [ $(git_number_of_commits) -eq 1 ]; then
    # Very first --archive!
    # See also: PW_PATCHES_REPO_MESSAGE_INIT="🥨"
    ${DRY_RUN} git commit -q -m "1${PW_PATCHES_REPO_MESSAGE_CHCHCHANGES}"
  else
    local amend=""

    local latest_cnt
    latest_cnt="$(patches_repo_commit_count)"

    if ! echo "${latest_cnt}" | grep -q -e "^[[:digit:]]*$"; then
      >&2 warn "Latest commit message does not contain a count."
      latest_cnt="FIXME:UNKNOWN_COUNT"
    else
      let 'latest_cnt += 1'
      # DEV: You can disable --amend'ing, to make it easier to debug.
      # And then you can use putwisely to squash (fixup).
      # - Note that putwisely is a wrapper, so we cannot not --amend here
      #   without implementing an alternative. Most likely, git-put-wise
      #   would need to implement '--push' on the patches repo, and it
      #   would need to perform the squash (fixup).
      #   - On that note, putwisely also calls git_gc_expire_all_prune_now
      #     before `git push`, which seems like maybe something git-put-wise
      #     should also be handling -- because managing the remote and
      #     managing the objects in the repo is sorta put-wise's concern.
      # - --allow-empty for special case: 1) `pw out -U`, 2) make changes to
      #   project, and 3) `pw out` again; where deleting archive and amending
      #   means first `pw out -U` commit would be empty. Allow this, because
      #   command will commit again with new archive.
      local amend="--amend --allow-empty"
      ! ${PW_OPTION_SKIP_SQUASH:-false} || amend=""
      # DEV: Uncomment (or use -U) to not fixup:
      #  amend=""
    fi

    # We're brutal like this. Fix-up. There can be only 1 post-first commit.
    ${DRY_RUN} git commit -q ${amend} --no-verify \
      -m "${latest_cnt}${PW_PATCHES_REPO_MESSAGE_CHCHCHANGES}"

    # Note that garbage collection won't really do any good until you
    # force-push squahes, because the remote objects will exist until
    # then.
    #   git_gc_expire_all_prune_now
  fi
}

patches_repo_commit_count () {
  git_latest_commit_message "$@" | sed "s/${PW_PATCHES_REPO_MESSAGE_CHCHCHANGES}//"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Git Reflog Expire Expire Now All and Garbage Collect Prune Now Quietly.
git_gc_expire_all_prune_now () {
  local complained_du=false

  verify_du () {
    ! ${complained_du} || return 1

    # At least a few BSD commands don't have --version option.
    # - This guess-test checks if this is GNU coreutils' du.
    ! du --version > /dev/null 2>&1 || return 0

    >&2 echo "ALERT: No \`du\` output because not coreutils \`du\`."

    complained_du=true

    return 1
  }

  # Note that `du` counts directories as 4k (their block size), but we
  # only care about file bits. So send `du` specific files to tabulate.
  # - Here are the directory-inclusive variants:
  #     printf "%9d bytes\n" "$(du -d 0 -b --exclude .git . | awk '{ print $1 }')"
  #     printf "%9d bytes\n" "$(du -d 0 -b . | awk '{ print $1 }')"

  tree_size_bytes_include_git () {
    find . -type f -print0 \
      | du -b --total --files0-from - \
      | tail -1 \
      | awk '{ print $1 }'
  }

  tree_size_bytes_exclude_git () {
    find . -path ./.git -prune -o -type f -print0 \
      | du -b --total --files0-from - \
      | tail -1 \
      | awk '{ print $1 }'
  }

  du-h-d-0-I-.git-. () {
    prefix="$1"
    prepos="$2"

    verify_du || return 0

    printf "%s: %9d bytes (incl. .git/)  %9d bytes (excl. .git/)\n" \
      "${prefix}Tree size ${prepos}" \
      "$(tree_size_bytes_include_git)" \
      "$(tree_size_bytes_exclude_git)"
  }

  # echo "Clean: git reflog expire --expire=now --all"
  # echo "       git gc --prune=now --quiet"
  echo "- git reflog expire --expire=now --all && git gc --prune=now --quiet"

  du-h-d-0-I-.git-. "  " "prior"

  ${DRY_RUN} git reflog expire --expire=now --all

  ${DRY_RUN} git gc --prune=now --quiet

  ${DRY_RUN} du-h-d-0-I-.git-. "  " "after"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# CPYST:
#   . ~/.kit/git/git-put-wise/deps/sh-git-nubs/bin/git-nubs.sh
#   . ~/.kit/git/git-put-wise/lib/common_put_wise.sh
#   decrypt_asset "path" | tar xvJ

encrypt_asset () {
  local crypt_path="$1"
  local cleartext_name="$2"

  >&2 debug "Encrypt ${cleartext_name} → ${crypt_path}"

  if [ -n "${PW_OPTION_PASS_NAME}" ]; then
    # Warm the GPG cache.
    pass "${PW_OPTION_PASS_NAME}" > /dev/null

    # Note that --passphrase-fd ignored unless --batch.
    pass "${PW_OPTION_PASS_NAME}" | head -1 |
      gpg --batch --passphrase-fd 0 -o "${crypt_path}" --cipher-algo AES256 -c "${cleartext_name}"
  else
    gpg -o "${crypt_path}" --cipher-algo AES256 -c "${cleartext_name}"
  fi
}

decrypt_asset () {
  local crypt_path="$1"

  if [ -n "${PW_OPTION_PASS_NAME}" ]; then
    # Warm the GPG cache.
    pass "${PW_OPTION_PASS_NAME}" > /dev/null

    pass "${PW_OPTION_PASS_NAME}" | head -1 |
      gpg --batch --passphrase-fd 0 \
        -q -d "${crypt_path}"
  else
    gpg -q -d "${crypt_path}"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

process_return_receipts () {
  local projpath_sha="$1"

  # Same as PW_PROJECT_PATH, I suppose.
  local project_path="$(pwd -L)"

  local localhost_sha="$(print_sha "$(hostname)")"

  cd "${PW_PATCHES_REPO}"

  local project_receipts
  project_receipts="^${localhost_sha}[[:xdigit:]]*--${projpath_sha}[[:xdigit:]]*--[[:xdigit:]]*--[[:xdigit:]]*--[0-9_hms]*${PW_RETURN_RECEIPT_CRYPT}\$"

  debug "grep -z -e \"${project_receipts}\""

  while IFS= read -r -d $'\0' gpg_rr; do
    debug "Unpacking receipt:\n  ${gpg_rr}"

    process_return_receipts_read_count_and_destroy "${gpg_rr}" "${project_path}"
  done < <(print_repo_return_receipts "-z" | grep -z -e "${project_receipts}")

  cd "${project_path}"
}

process_return_receipts_read_count_and_destroy () {
  local gpg_rr="$1"
  local project_path="$2"

  # tar prints the unpacked path (which should match ret_rec_plain_path).
  local tar_paths
  tar_paths="$(decrypt_asset "${gpg_rr}" | tar xvJ 2>&1)"
  # Remove "x " prefix that some tar use when printing lines for each
  # directory and file unpacked (for the author, on @macOS, not @linux).
  tar_paths="$(echo "${tar_paths}" | sed 's/^x //')"

  local gpg_rr_base
  gpg_rr_base="$(echo "${gpg_rr}" | sed "s#${PW_RETURN_RECEIPT_CRYPT}\$#${PW_RETURN_RECEIPT_PLAIN}#")"

  local ret_rec_plain_path
  ret_rec_plain_path="$(must_find_path_starting_with_prefix_dash_dash "${gpg_rr_base}")"

  echo -e "\nDisposing receipt:\n  ${ret_rec_plain_path}"

  if [ "${tar_paths}" != "${ret_rec_plain_path}" ]; then
    # Dev error catch.
    >&2 echo "  ┣━━ WARN: Unexpected: receipt-found-path ⤴  is different from receipt-tar-path ⤵  ━━┫"
    >&2 echo "  ${tar_paths}"
  fi

  if [ ! -f "${ret_rec_plain_path}" ]; then
    >&2 echo "ERROR: Unexpected: No plain return-receipt file found."
    >&2 echo "- Unpacked archive: ${gpg_rr}"
    >&2 echo "- Expected to find: ${ret_rec_plain_path}"

    exit 1
  fi

  # E.g., "${host_sha}--${proj_sha}--${beg_sha}--${end_sha}--${time}--${branch}--${proj_name}"
  set -- $(split_on_double_dash "${ret_rec_plain_path}" 6)
  local hostname_sha="$1"  # KNOWN: localhost
  local projpath_sha="$2"  # KNOWN: project_path's sha
  local starting_sha="$3"  # Don't care
  local endingat_sha="$4"  # Don't care
  local time_stamped="$5"  # Don't care
  local patch_branch_encoded="$6"  # What we care about
  local project_name="$7"  # Don't care

  local patch_branch="$(branch_name_path_decode "${patch_branch_encoded}")"

  local host_nrev_lines="$(cat "${ret_rec_plain_path}")"

  local before_cd="$(pwd -L)"

  cd "${project_path}"

  local previous_branch="$(git_branch_name)"

  # Currently (and possibly forever), return receipts only apply to the
  # 'private' branch. We could support arbitrary branches, but there's
  # no use case, and it complicates matters: we would need to know what
  # remoteish tracking branch to use (because currently, per convention,
  # we use the 'protected' branch to track how up-to-date are non-remote
  # remote hosts with the 'private' branch).
  # - Note that you don't need a return receipt if you can pull.
  #   - It's only when you can only archive/apply, which only applies
  #     to the 'private' branch.
  if [ ! -n "${host_nrev_lines}" ]; then
    >&2 echo "WARNING: Empty return receipt: "${gpg_rr}""
  else
    if ! git_branch_exists "${patch_branch}"; then
      >&2 echo "ERROR: Cannot consume return receipt because missing branch: “${patch_branch}”"
      >&2 echo "- From plaintext “${ret_rec_plain_path}”"
      >&2 echo "- From crypttext “${gpg_rr}”"

      exit 1
    fi

    prompt_user_and_change_branch_if_working_branch_different_retrcpt \
      "${patch_branch}" "${ret_rec_plain_path}"
  fi

  local failed=0

  for host_nrev_line in "${host_nrev_lines}"; do
    if ! echo "${host_nrev_line}" | grep -q \
      -e "^[[:digit:]]\+ [[:xdigit:]]\+ [^[:space:]]\+ [[:xdigit:]]\+ [[:xdigit:]]\+$"; \
    then
      >&2 echo "ERROR: Unexpected return receipt line: “${host_nrev_line}”"
      >&2 echo "- From plaintext “${ret_rec_plain_path}”"
      >&2 echo "- From crypttext “${gpg_rr}”"

      exit 1
    fi

    set -- ${host_nrev_line}

    local remote_rev_tot="$1"
    # The remaining are ignored. Maybe someday we'll do more than print them.
    local remote_hostsha="$2"
    local remote_patch_branch="$3"
    local remote_starting_sha="$4"
    local remote_last_patch="$5"

    debug "${ret_rec_plain_path} parsed:"
    debug "- remote_rev_tot: ${remote_rev_tot}"
    debug "- remote_hostsha: ${remote_hostsha}"
    debug "- remote_patch_branch: ${remote_patch_branch}"
    debug "- remote_starting_sha: ${remote_starting_sha}"
    debug "- remote_last_patch: ${remote_last_patch}"

    process_return_receipt_move_remoteish_tracking_branch \
      "${patch_branch}" "${remote_rev_tot}" "${gpg_rr}" "${before_cd}" \
      || failed=$?

    [ ${failed} -eq 0 ] || break
  done

  checkout_branch_quietly "${previous_branch}"

  cd "${before_cd}"

  ${DRY_RUN} /bin/rm -f "${ret_rec_plain_path}"

  [ ${failed} -eq 0 ] || exit ${failed}

  debug "git rm -q \"${gpg_rr}\""
  ${DRY_RUN} git rm -q "${gpg_rr}"

  commit_changes_and_counting
}

# ***

must_find_path_starting_with_prefix_dash_dash () {
  local gpgf="$1"

  local file_guess
  file_guess="$(/bin/ls -A1d "${gpgf}"--*)"

  if [ $(printf "${file_guess}" | wc -l) -gt 0 ]; then
    >&2 warn "Found more than one match for “${gpgf}” (and using first one found)."
    >&2 warn "- Found the following files:\n${file_guess}"

    file_guess="$(echo "${file_guess}" | head -1)"
  fi

  # If nothing found, smells like a DEV issue. Or requires user to return
  # put-wise patchr repo to a known/expected state.
  if [ -z "${file_guess}" ]; then
    >&2 echo "ERROR: Unexpectedly found nothing unpacked for “${gpgf}--*”."

    exit 1
  fi

  printf "${file_guess}"
}

# ***

split_on_double_dash () {
  local text="$1"
  local count="$2"

  python -c \
    "import re ; print(
      re.sub(
        '\-\-',
        ' ',
        '${text}',
        count=${count}
  ))"
}

# ***

# Change to branch indicated, which is original branch that was patched out.
# Then move branch named after remote host to the count specified, after
# validating that both branches share history, and that new count is greater
# than or equal to what it is currently.
process_return_receipt_move_remoteish_tracking_branch () {
  local patch_branch="$1"
  local remote_rev_tot="$2"
  local gpg_rr="$3"
  local before_cd="$4"

  # pw/in tag.
  local pw_tag_applied="$(format_pw_tag_applied "${patch_branch}")"

  # TRACK/2023-01-04: This could happen if you rebase against publish/release
  # before processing the return receipt. Or at least that's what I assume
  # just happened to me, otherwise I'd fixme the situation; but I think it's
  # user error (or bad habits, i.e., not always using `pw pull`) that leads
  # to this divergence (and it most cases it's okay to just delete the
  # return receipt, unless this is a private-private repo, then something
  # would really be smelly).
  if ! git_tag_exists "${pw_tag_applied}"; then
    >&2 echo
    >&2 echo "ERROR: Cannot apply return receipt without \"${pw_tag_applied}\" tag."
    >&2 echo
    >&2 echo "- Please either add the tag, or remove the receipt."
    >&2 echo
    >&2 echo "    # Add the tag."
    >&2 echo "    git tag ${pw_tag_applied} <some-commit>"
    >&2 echo
    >&2 echo "    # Or remove the receipt."
    >&2 echo "    cd ${before_cd}"
    >&2 echo "    git rm $(basename "${gpg_rr}")"
    >&2 echo "    git commit --amend --no-edit"

    return 1
  fi

  # MAYBE/2023-02-25: If pw/in diverged from HEAD, we may need to improve
  # the code, or add UX messaging to help user recover from the situation.
  # - Use case: User rebased past pw/in, so remote commit-count meaningless,
  #             and we cannot proceed with the --apply.
  local divergent_ok=false
  must_confirm_commit_at_or_behind_commit \
    "refs/tags/${pw_tag_applied}" "HEAD" \
    ${divergent_ok} \
    "pick-from" "this branch"

  local previous_cnt="$(git_number_of_commits "refs/tags/${pw_tag_applied}")"

  if [ ${remote_rev_tot} -gt ${previous_cnt} ]; then
    local n_total_commits=$(git_number_of_commits "HEAD")

    if [ ${remote_rev_tot} -gt ${n_total_commits} ]; then
      >&2 echo "ERROR: \${remote_rev_tot} > \${n_total_commits}: ${remote_rev_tot} > ${n_total_commits}"

      return 1
    fi

    local skip_commits
    # If (n_total_commits - remote_rev_tot) is 0, `set -e` bails, so || true.
    let "skip_commits = ${n_total_commits} - ${remote_rev_tot}" || true

    local commit_hash=$(git --no-pager log --format=%H --skip=${skip_commits} --max-count=1)

    local prev_tag_sha
    prev_tag_sha="$(shorten_sha "$(git rev-parse --verify -q refs/tags/${pw_tag_applied})")"
    if [ -n "${prev_tag_sha}" ]; then
      prev_tag_sha="  # was: ${prev_tag_sha}"
    fi
    # Follows "Disposing receipt:\n <filename>"
    local new_commits
    let "new_commits = ${remote_rev_tot} - ${previous_cnt}" || true
    echo "Advancing count ${new_commits} rev(s):"
    echo "  git tag -f ${pw_tag_applied} $(shorten_sha ${commit_hash})${prev_tag_sha}"
    ${DRY_RUN} git tag -f "${pw_tag_applied}" "${commit_hash}" > /dev/null
  else
    echo "Disregarding count:"
    echo "  local count ${previous_cnt} [${pw_tag_applied}] >= receipt count ${remote_rev_tot}"
  fi

  return 0
}

# ***

# USYNC: prompt_user_and_change_branch_if_working_branch_different_patches
prompt_user_and_change_branch_if_working_branch_different_retrcpt () {
  local desired_branch="$1"
  local ret_rec_plain_path="$2"

  local project_path="$(pwd -L)"

  local branch_name
  branch_name="$(git_branch_name)"

  if [ "${branch_name}" != "${desired_branch}" ]; then
    if git_branch_exists "${desired_branch}"; then
      echo "ALERT: The return receipt applies to a different branch."
      echo "- Would you like us to checkout the appropriate branch?"
      echo "- Okay to switch from “${branch_name}”"
      echo "                   to “${desired_branch}”"
      echo "  in project found at “${project_path}”"
      echo "  from ret receipt at “${ret_rec_plain_path}”?"
      echo "             [Y/n]"
      printf "               "

      local key_pressed
      local opt_chosen
      prompt_read_single_keypress "y" "n"
      [ "${opt_chosen}" = "y" ] || return 1

      git checkout -q "${desired_branch}"
    else
      >&2 echo
      >&2 echo "ERROR: These patches were not generated from the same-named"
      >&2 echo "branch as the current branch and there's no local branch of"
      >&2 echo "the same name."
      >&2 echo "- The return receipt branch “${desired_branch}”"
      >&2 echo "  in the project located at “${project_path}”"
      >&2 echo "  from the returned receipt “${ret_rec_plain_path}”"
      >&2 echo "- Please address this issue and then try this receipt again."
      >&2 echo

      return 1
    fi
  fi
}

# ***

checkout_branch_quietly () {
  local branch_name="$1"

  [ -n "${branch_name}" ] || return 0

  ${DRY_RUN} git checkout -q "${branch_name}"
}

# ***

# CXREF: For list of valid branch name characters, see:
#   man git-check-ref-format
# https://git-scm.com/docs/git-check-ref-format

branch_name_path_encode () {
  local patch_branch="$1"

  local encoded_branch="$(echo "${patch_branch}" | sed 's#/#@@@#g')"

  printf "${encoded_branch}"
}

branch_name_path_decode () {
  local encoded_branch="$1"

  local patch_branch="$(echo "${encoded_branch}" | sed 's#@@@#/#g')"

  git check-ref-format --branch "${patch_branch}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_await_user_resolve_conflicts () {
  >&2 echo "============================================"
  >&2 echo
  >&2 echo "Ope! You got conflicts. Resolve them. We'll wait for you..."
  >&2 echo
  >&2 echo "Return here where you're ready, and (y)es us. Or (n)ot"
  >&2 echo
  >&2 printf "Ready? [Y/n] "

  # MAYBE/2022-11-18: If not "y", maybe print instructions on how to cleanup.
  must_await_user_resolve_conflicts_read_input

  # Note the Git rebase won't always remove .git/REBASE_HEAD, not sure
  # why, so use todo as signal instead.
  while [ -f ".git/rebase-merge/git-rebase-todo" ]; do
    # This is just a curiosity:
    [ -f ".git/REBASE_HEAD" ] \
      || >&2 echo "UNEXPECTED: Not found: .git/REBASE_HEAD"

    >&2 echo "============================================"
    >&2 echo
    >&2 echo "Really ready? Git says there's a rebase afoot."
    >&2 echo
    >&2 printf "Let me know when you're actually really [Y/n] "

    must_await_user_resolve_conflicts_read_input
  done

  [ ! -f ".git/rebase-merge/git-rebase-todo" ] \
    || >&2 echo "UNEXPECTED: Not not found: .git/rebase-merge/git-rebase-todo"
}

must_await_user_resolve_conflicts_read_input () {
  read input

  local opt_chosen
  pick_which_option_based_on_key_pressed "y" "n" "${input}"

  # We'll default 'y' and only exit on explicit no, because all
  # callers will recheck condition and re-prompt if necessary.
  [ "${opt_chosen}" != "n" ] || exit 1

  >&2 echo "============================================"
  >&2 echo
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

prompt_read_single_keypress () {
  local convenient_option="$1"
  local dissenting_option="$2"
  local print_newline=${3:-true}

  # Because Bash variable assignment strips trailing newlines, don't, e.g.,
  # `key_pressed="$(read_single_keypress)", but rather rely on `local`.
  read_single_keypress

  ! ${print_newline} || [ "${key_pressed}" = $'\n' ] || printf '\n'

  pick_which_option_based_on_key_pressed \
    "${convenient_option}" "${dissenting_option}" "${key_pressed}"
}

# ***

READ_N_SUPPORTED=""

# SAVVY: Bash v4+ supports `read -N`, which doesn't strip IFS,
# like `read -n`. This is useful to capture key_pressed="\n".
# - CXREF: To view Homebrew's Bash v5 manpage:
#     man /opt/homebrew/share/man/man1/bash.1
read_single_keypress () {
  if [ -z "${READ_N_SUPPORTED}" ]; then
    READ_N_SUPPORTED=true
    # When -N is supported, `read -N 0` doesn't return immediately, but
    # waits for EOF. So send a character to `read` to test if -N supported.
    echo 'X' | read -N 1 key_pressed 2> /dev/null || READ_N_SUPPORTED=false
  fi

  ${READ_N_SUPPORTED} &&
    read -N 1 key_pressed ||
    read -n 1 key_pressed
}

# ***

pick_which_option_based_on_key_pressed () {
  local convenient_option="$1"
  local dissenting_option="$2"
  local key_pressed="$3"

  normalize_case () {
    echo "$1" | tr '[:upper:]' '[:lower:]'
  }

  opt_chosen=""

  if \
    [ "${key_pressed}" = "" ] ||
    [ "${key_pressed}" = " " ] ||
    [ "${key_pressed}" = $'\n' ] ||
    [ "$(normalize_case "${key_pressed}")" = "$(normalize_case "${convenient_option}")" ] \
  ; then
    opt_chosen="${convenient_option}"
  fi

  if \
    [ "$(normalize_case "${key_pressed}")" = "$(normalize_case "${dissenting_option}")" ] \
  ; then
    opt_chosen="${dissenting_option}"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Complain if executed.
if [ "$0" = "${BASH_SOURCE}" ]; then
  >&2 echo "😶"
fi

