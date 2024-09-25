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

# *** "External" environs (copied from upstream)

# This is the known Git rebase todo path.
# - SPIKE: Can we get this from `git` so it's not hardcoded?
GIT_REBASE_TODO_PATH=".git/rebase-merge/git-rebase-todo"

# This is a known git-am path.
GIT_AM_INFO_PATH=".git/rebase-apply/info"

# This is the special tag at the end of the 'exec' line that
# you must use if you git-abort to run that 'exec'.
# - USYNC: This environ is used in git-smart and tig-newtons:
GITSMART_POST_REBASE_EXECS_TAG=" #git-abort"

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

PUT_WISE_REBASE_ALL_COMMITS="${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}"

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

    exit_1
  fi

  return 0
}

must_verify_patches_repo_is_directory_if_specified () {
  [ -n "${PW_PATCHES_REPO}" ] || return 0

  if [ -e "${PW_PATCHES_REPO}" ] && [ ! -d "${PW_PATCHES_REPO}" ]; then
    >&2 echo "ERROR: The patches archive repo is not a" \
      "directory: “${PW_PATCHES_REPO}”"

    exit_1
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
    [ -n "$(command ls -A "${PW_PATCHES_REPO}")" ]; \
  then
    return 0
  fi

  if [ -e "${PW_PATCHES_REPO}" ] && [ ! -d "${PW_PATCHES_REPO}" ]; then
    >&2 echo "ERROR: Patches repo exists but not directory: “${PW_PATCHES_REPO}”"

    exit_1
  fi

  prompt_user_to_create_patches_repo "${PW_PATCHES_REPO}" || return 1

  maybe_prompt_user_to_create_parent_path

  create_patches_parents_and_repo
}

maybe_prompt_user_to_create_parent_path () {
  local parent_dir="$(dirname -- "${PW_PATCHES_REPO}")"

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

    exit_1
  fi

  local emptiness="${PW_PATCHES_REPO_HINT}"

  if [ ! -f "${emptiness}" ]; then
    # Said the Professor.
    >&2 echo "ERROR: Oh the vast emptiness! Nothing at: “${emptiness}”."

    exit_1
  fi

  # Extra-worried. (Not worried enough to `pwd -P`?)
  local cur_dir="$(pwd -L)"

  local home_relative_path
  home_relative_path="$(echo "${cur_dir}" | sed -E "s#^${HOME}(/|$)#\1#")"
  # KLUGE/2023-05-28: Vim Bash highlight bug: Backslash &/or pound  ↑ ↑")"

  if [ "${home_relative_path}" = "${cur_dir}" ]; then
    >&2 echo "ERROR: You need to specify a path under \$HOME, sorry, eh."

    exit_1
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

  # Is user hasn't setup the patches repo, there's nothing to *insist*.
  # - E.g., ~/.depoxy/patchr does not exist (yet).
  if [ ! -d "${PW_PATCHES_REPO}" ]; then

    return 0
  fi

  cd "${PW_PATCHES_REPO}"

  git_insist_git_repo_and_is_git_repo_root

  PW_PATCHES_REPO="$(git_repo_canonicalize_environ_path "PW_PATCHES_REPO")"

  git_insist_nothing_staged

  cd "${before_cd}"
}

git_insist_git_repo_and_is_git_repo_root () {
  git_insist_git_repo

  git_insist_is_git_repo_root
}

git_insist_is_git_repo_root () {
  if ! git_is_git_repo_root; then
    # This might be a GAFFE, i.e., dev mistake...
    >&2 echo "ERROR: Expected a Git repo root: ${PW_PATCHES_REPO}"

    return 1
  fi
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
  touch -- "${emptiness}"
  git add -- "${emptiness}"
  # CXREF: git_first_commit_message
  # CALSO: PW_PATCHES_REPO_MESSAGE_CHCHCHANGES="🥬"
  git commit -q -m "${PW_PATCHES_REPO_MESSAGE_INIT}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

put_wise_reset_patches_repo () {
  if [ -e "${PW_PATCHES_REPO}" ] && [ ! -d "${PW_PATCHES_REPO}" ]; then
    >&2 echo "ERROR: Patches repo path not a directory: “${PW_PATCHES_REPO}”."

    exit_1
  fi

  if [ -d "${PW_PATCHES_REPO}" ]; then
    local before_cd="$(pwd -L)"

    cd "${PW_PATCHES_REPO}"

    if [ -z "$(command ls -A "${PW_PATCHES_REPO}")" ]; then
      PW_PATCHES_REPO="$(pwd -L)"

      cd "${before_cd}"

      rmdir "${PW_PATCHES_REPO}"
    else
      # Me being paranoid.

      # Might be overcheckill.
      git_insist_git_repo_and_is_git_repo_root

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
      command rm -rf "${PW_PATCHES_REPO}"
    fi
  fi

  maybe_prompt_user_to_create_parent_path

  create_patches_parents_and_repo

  echo "A fresh patches repo is ready at: ${PW_PATCHES_REPO}"
  echo "- Hint: Now wire the remote, set the upstream, and force-push"
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

    exit_1
  fi

  cd "${PW_PROJECT_PATH}"

  if ${PW_ACTION_APPLY} || ${PW_ACTION_APPLY_ALL}; then
    git_insist_is_git_repo_root
  else
    git_insist_git_repo
  fi

  PW_PROJECT_PATH="$(git_repo_canonicalize_environ_path "PW_PROJECT_PATH")"

  cd "${PW_PROJECT_PATH}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_not_be_patches_repo () {
  project_path_same_as_patches_repo || return 0

  >&2 echo "ERROR: This command does not work on the patches repo: “${PW_PATCHES_REPO}”"

  exit_1
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

  # Is user hasn't setup the patches repo, or if they're unpacking to a
  # project path that doesn't exist yet, then the answer is *no*.
  # - E.g., ~/.depoxy/patchr does not exist (yet).
  if ! [ -d "${PW_PROJECT_PATH}" ] || ! [ -d "${PW_PATCHES_REPO}" ]; then

    return 1
  fi

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

# `put-wise --rebase-boundary` / PW_ACTION_REBASE_BOUNDARY=true

put_wise_print_rebase_boundary () {
  local branch_name=""
  local local_release=""
  local remote_release=""
  local remote_liminal=""
  local remote_protected=""
  local remote_current=""
  local remote_name=""
  local rebase_boundary=""
  local already_sorted=false
  local already_signed=false
  if ! put_wise_identify_rebase_boundary_and_remotes \
    "${_action_desc:-probe}" "${_inhibit_exit_if_unidentified:-true}" \
  ; then
    # Cound not identify rebase boundary, and commits not sorted/signed.
    rebase_boundary="<unknown!>"
  fi

  for var in \
    rebase_boundary \
    branch_name \
    local_release \
    remote_release \
    remote_liminal \
    remote_protected \
    remote_current \
    remote_name \
    already_sorted \
    already_signed \
  ; do
    echo "${var}: ${!var}"
  done
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# `put-wise --scope` / PW_ACTION_SCOPE=true

put_wise_print_scoping_boundary_sha () {
  local protected_boundary_or_HEAD
  protected_boundary_or_HEAD="$( \
    identify_scope_ends_at "^${SCOPING_PREFIX}" "^${PRIVATE_PREFIX}" \
  )"

  # identify-scope postfixes '^' parent shortcut, but this fcn derefs.

  printf "%s" "$(
    git rev-parse --verify --end-of-options "${protected_boundary_or_HEAD}"
  )"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# `put-wise --sha`
#
# CPYST:
#   . ~/.kit/git/git-put-wise/deps/sh-git-nubs/lib/git-nubs.sh
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

# ***

print_sha () {
  local key="$1"

  shorten_sha "$( \
    printf "${PW_PROJECT_PATH_SALT}--${key}" \
      | sha1sum | awk '{ print $1 }'
  )"
}

shorten_sha () {
  local string="$1"
  local maxlen="${2:-${PW_SHA1SUM_LENGTH}}"

  git_sha_shorten "${string}" "${maxlen}"
}

# ***

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
  local archive_file="$(basename -- "$1")"

  local before_cd="$(pwd -L)"

  cd "${PW_PATCHES_REPO}"

  local relative_path="$(echo "${archive_file}" | sed -E "s#^${PW_PATCHES_REPO}/##")"

  if ! print_repo_archive_list | grep --quiet -e "^${relative_path}$"; then
    >&2 echo "ERROR: Specified patches archive not committed to patches repo."

    exit_1
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

# Sorts & signs commits since rebase_boundary.
# - This fcn. is used by PW_ACTION_PUSH and PW_ACTION_ARCHIVE.
# - Exits 1 if boundary is ahead of HEAD or diverged.
# - Exits 0/11 if boundary is same as HEAD, i.e., no-op.
resort_and_sign_commits_since_boundary () {
  local rebase_boundary="$1"
  local enable_gpg_sign="${2:-false}"
  local normalize_committer="${3:-false}"

  local starting_sha_or_HEAD
  starting_sha_or_HEAD="$( \
    must_confirm_shares_history_with_head "${rebase_boundary}"
  )" || exit_1

  if [ "${starting_sha_or_HEAD}" = "HEAD" ]; then
    >&2 echo "Nothing to do: Already up-to-date with “${rebase_boundary}”"

    exit_elevenses
  fi

  # ***

  local and_sign=""
  ! ${enable_gpg_sign} || and_sign=" & sign"

  echo_announce "Scoped sort${and_sign} (${starting_sha_or_HEAD})"

  # ***

  resort_and_sign_commits_since_boundary_unless_unnecessary \
    "${starting_sha_or_HEAD}" "${enable_gpg_sign}" \
    "${normalize_committer}"
}

resort_and_sign_commits_since_boundary_unless_unnecessary () {
  local rebase_boundary="$1"
  local enable_gpg_sign="${2:-false}"
  local normalize_committer="${3:-false}"

  local retcode=0

  # Sort commits by "scope" (according to message prefixes).
  git_sort_by_scope \
    "${rebase_boundary}" \
    "${enable_gpg_sign}" \
    "${normalize_committer}" \
      || retcode=$?

  if [ ${retcode} -ne 0 ] && [ -f "${GIT_REBASE_TODO_PATH}" ]; then
    # Callee set rebase-todo 'exec' to pop WIP, and to call optional user hook,
    # GIT_POST_REBASE_EXEC. Nag user one last time before nonzero return
    # tickles errexit.
    badger_user_rebase_failed
  fi

  # Exit-errexit if sort-by-scope failed.
  return ${retcode}
}

exit_elevenses () {
  if ${PW_OPTION_FAIL_ELEVENSES:-false}; then

    exit_11
  else

    exit_0
  fi
}

# CXREF: ~/.kit/sh/sh-err-trap/lib/err-trap.sh
exit_11 () {
  clear_traps true 11

  exit ${PW_ELEVENSES:-11}
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Check if commit range rebase_boundary through until_ref is sorted,
# signed, and/or normalized.
# - Note that GPW *always* checks that scoped commits are sorted,
#   but signing and normalizing are optional.
# - If not sorted, sets already_sorted=false and returns 1 without
#   checking signed or normalized.
# - If sorted, sets already_sorted=true and checks both if signed
#   (if enabled) and if normalized (if enabled).
#   - If checks pass, returns truthy and sets already_signed=true and/or
#     already_normed=true as appropriate.
#   - Otherwise returns nonzero but still checks and sets
#     already_signed=true and/or already_normed=true as appropriate.
#
# Note that, unless signing, running the rebase anyway if only sorting
# is a fast no-op, and the final HEAD SHA remains unchanged (because
# no content changed). (If also normalizing and already normalized, the
# rebase would also recreate the same final HEAD SHA, but normalizing
# might take a few seconds, because Git runs an `exec` command for each
# commit.)
#
# - But if we skip the rebase, we can also skip the user's post-rebase
#   exec, which might not be so fast (e.g., DepoXy uses the post-rebase
#   exec to call `mr` (myrepos) to repair hard links, and `mr` takes a
#   half-second or two to load (it's a Perl app that loads dozens of
#   shell-code-containing user config files)).
#
# - So we prefer to skip the sort-by-scope rebase when possible.
#
# Returns: Zero if sorted, signed (if enabled), and normalized (if enabled).
# - Returns nonzero otherwise.
#
# Side-effect: Sets caller-scoped variables:
#   already_sorted=true|false
#   already_signed=true|false
#   already_normed=true|false

is_already_sorted_and_signed () {
  # rebase_boundary is a commit object, or magic name "ROOT".
  local rebase_boundary="$1"
  local enable_gpg_sign="$2"
  local until_ref="${3:-HEAD}"
  local normalize_committer="${4:-false}"

  # "Return" values.
  already_sorted=false
  already_signed=false
  already_normed=false

  local rev_list_commits
  rev_list_commits="$(print_git_rev_list_commits "${rebase_boundary}" "${until_ref}")"

  local n_commits
  n_commits="$(git rev-list --count ${rev_list_commits})"

  local scoped_count
  if ! scoped_count="$(is_sorted_by_scope "${rebase_boundary}" "${until_ref}")"; then

    return 1
  fi

  local retcode=0

  already_sorted=true

  local msg_prefix="Verified "
  local msg_postfix=" sorted"
  local but_not=""

  local since_commit=""
  if [ "${rebase_boundary}" != "${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}" ]; then
    since_commit="${rebase_boundary}"
  fi

  local exclude_pattern="^(${PRIVATE_PREFIX:-PRIVATE: }|${SCOPING_PREFIX:-PROTECTED: }).*\$"

  if ! ${enable_gpg_sign} \
    || git_is_gpg_signed_since_commit \
      "${since_commit}" "${until_ref}" "${exclude_pattern}" \
  ; then
    if ${enable_gpg_sign}; then
      already_signed=true

      msg_postfix=" sorted & signed"
    fi
  elif ${enable_gpg_sign}; then
    retcode=1

    but_not="but not signed"
  fi

  if ! ${normalize_committer} \
    || [ -z "$( \
      git_oldest_commit_with_committer_different_than_author \
        "${since_commit}" "${until_ref}" \
      )" ] \
  ; then
    if ${normalize_committer}; then
      already_normed=true

      msg_postfix="${msg_postfix}, & committer normalized"
    fi
  elif ${normalize_committer}; then
    retcode=1

    if [ -n "${but_not}" ]; then
      but_not="${but_not}, nor normalized"
    else
      but_not="but not normalized"
    fi
  fi

  if [ -n "${but_not}" ]; then
    msg_postfix="${msg_postfix} (${but_not})"
  fi

  print_generic_status_message "${msg_prefix}" "${msg_postfix}" \
    "${n_commits}" "${_scoped_count_arg+}"

  return ${retcode}
}

# ***

print_git_rev_list_commits () {
  local rebase_boundary="$1"
  local until_ref="${2:-HEAD}"

  local rev_list_commits="${until_ref}"

  if [ -n "${rebase_boundary}" ] \
    && [ "${rebase_boundary}" != "${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}" ] \
  ; then
    local object_name
    if object_name="$(git rev-parse ${rebase_boundary} 2> /dev/null)"; then
      rev_list_commits="${object_name}..${until_ref}"
    fi
    # else, caller passed parent-of ref, e.g., <SHA>^ which means <SHA> is
    # the root commit. So use HEAD (and then git-describe will consider all
    # commits in the branch). I.e., `$(git_first_commit)..HEAD` excludes
    # the first commit. But using just `HEAD` includes it.
  fi

  printf "%s" "${rev_list_commits}"
}

# ***

print_generic_status_message () {
  local msg_prefix="$1"
  local msg_postfix="$2"
  local n_commits="$3"
  local scoped_count="$4"

  local scoped_msg=""
  if [ -n "${scoped_count}" ]; then
    scoped_msg=" (${scoped_count} scoped)"
  fi

  echo "✓ ${msg_prefix}${n_commits}${msg_postfix}${scoped_msg}"
}

# ***

print_sorted_and_signed_message () {
  local gpg_sign="$1"
  local already_sorted="$2"
  local did_normalize="$3"
  local n_commits="$4"
  local head_sha_before_rebase="$5"

  local msg_prefix="Sorted"
  local msg_comma=""
  if [ -n "${gpg_sign}" ]; then
    if ${already_sorted}; then
      msg_prefix="Signed"
    else
      msg_prefix="${msg_prefix} & signed"
      msg_comma=","
    fi
  fi
  if ${did_normalize}; then
    msg_prefix="${msg_prefix}${msg_comma} & normalized"
  fi
  msg_prefix="${msg_prefix} "

  local n_commits_inflector=""
  [ ${n_commits} -eq 1 ] || n_commits_inflector="s"

  local msg_postfix=" commit${n_commits_inflector}"

  if [ -n "${head_sha_before_rebase}" ]; then
    local sha_len=7
    local was_sha="$(shorten_sha "${head_sha_before_rebase}" ${sha_len})"
    local now_sha="$(shorten_sha "$(git_HEAD_commit_sha)" ${sha_len})"

    msg_postfix="${msg_postfix} [${was_sha} → ${now_sha}]"
  fi

  print_generic_status_message "${msg_prefix}" "${msg_postfix}" \
    "${n_commits}" "${_scoped_count_arg+}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PW_GIT_CONFIG_SIGN_BEFORE_PUSH="put-wise.sign-before-push"

# Returns '--gpg-sign' git-rebase arg if caller requested it.
# - Also checks if signing key is expected to be present,
#   otherwise Git fails, e.g.,
#     $ git rebase --exec 'git commit --amend --no-edit -n -S' <sha>
#     ...
#     error: gpg failed to sign the data
#     ...

insist_print_gpg_sign_arg () {
  local enable_gpg_sign_if_signingkey="${1:-false}"
  local insist_signing_key="${2:-false}"

  local gpg_sign=""

  if ${enable_gpg_sign_if_signingkey} \
    && [ "$(git config ${PW_GIT_CONFIG_SIGN_BEFORE_PUSH:-put-wise.sign-before-push})" = "true" ] \
  ; then
    if [ -n "$(git config user.signingkey)" ]; then
      # E.g., `git rebase -S|--gpg-sign`
      gpg_sign="--gpg-sign"
    elif ${insist_signing_key}; then
      >&2 echo "ERROR: Cannot sign: Please specify user.signingkey in your Git config"

      return 1
    fi
  fi

  printf "%s" "${gpg_sign}"
}

# ***

print_is_gpg_sign_enabled () {
  local gpg_sign
  gpg_sign="$( \
    insist_print_gpg_sign_arg \
      ${_enable_gpg_sign_if_signingkey:-true} \
      ${_insist_signing_key:-false}
  )" || return 1

  if [ -n "${gpg_sign}" ]; then
    printf "%s" "true"
  else
    printf "%s" "false"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Verify that the rebase boundary is an ancestor of the current branch.
# CXREF: See similar fcn:
#   must_confirm_commit_at_or_behind_commit
# USERS: Called by:
# - put-wise archive, and git-wise push
#     (via resort_and_sign_commits_since_boundary)
# - git-rebase-sort-by-scope, and git-bump-version-tag
#     (via directly)
must_confirm_shares_history_with_head () {
  local rebase_boundary="$1"

  if git_is_empty_tree "${rebase_boundary}"; then
    echo "${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}"

    return 0
  fi

  if git_is_same_commit "${rebase_boundary}" "HEAD"; then
    echo "HEAD"

    return 0
  elif [ "${rebase_boundary}" = "${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}" ] \
    || git merge-base --is-ancestor "${rebase_boundary}" "HEAD" \
  ; then
    # The common ancestor is ${rebase_boundary},
    # i.e., rebase_boundary is behind HEAD.

    echo "${rebase_boundary}"

    return 0
  elif git merge-base --is-ancestor "HEAD" "${rebase_boundary}"; then
    # rebase_boundary ahead of HEAD. *How *did* we get here?*
    #
    # - The rebase_boundary might be a local or remote branch name,
    #   a tag name, or user-specified.
    # - But it's very unlikely a local branch or tag GPW uses would be ahead
    #   of the current branch, unless the user is outside the normal workflow.
    >&2 echo "ERROR: The rebase boundary is ahead of the current branch (HEAD)"
    >&2 echo "- Rebase boundary: ${rebase_boundary}"
    >&2 echo "- HINT: If the boundary is a remote branch, pull or rebase, and then try again."
    >&2 echo "  - If it's a local reference, try something different, then try again."

    return 1
  fi

  # Diverged!

  >&2 echo "ERROR: The rebase boundary does not share history with the current branch (HEAD)"
  >&2 echo "- Rebase boundary: ${rebase_boundary}"
  >&2 echo "- HINT: It's possible that you rebased and broke the ancestry"
  >&2 echo "  - Please ensure the rebase boundary is an ancestor of HEAD"

  if git_remote_branch_exists "${rebase_boundary}"; then
    if ${PW_ACTION_PUSH}; then
      # FTREQ/2024-08-30: Why isn't GPW written in a OO language? Add context:
      # - If this is 'entrust/scoping' branch, suggest user prob. wants to
      #   force-push.
      # - If this is 'publish/release', user prob. wants to rebase.
      # - Or this is 'publish/feature', and user, dunno, either-or.
      >&2 echo "- One option is to rebase local work atop the remote branch, e.g.,"
      >&2 echo "    git rebase ${rebase_boundary}"
      >&2 echo "- Another option is to sort-by-scope with a specific SHA, and to"
      >&2 echo "  force-push to overwrite the remote branch, e.g.,"
      >&2 echo "    ${PROG_NAME} push --force --starting-ref <REF>"
      >&2 echo "  Alternatively, use HEAD to skip the rebase, e.g.,"
      >&2 echo "    ${PROG_NAME} push --force --starting-ref HEAD"
    elif ${PW_ACTION_ARCHIVE}; then
      # FTREQ/2024-08-30: Support rebase past upstream branch.
      # - Currently --apply doesn't expect previously applied commits to change.
      # - We could add a commit-count as starting ref. for --apply patchkages.
      >&2 echo "- You should rebase local work atop the remote branch, e.g.,"
      >&2 echo "    git rebase ${rebase_boundary}"
      >&2 echo "  Because put-wise does not currently support re-applying old commits"
    fi
    # else, git-sort-by-scope (if user called directly with specific 'remote/branch'),
    #    or git-bump (with rebase_boundary from dep_rebase_boundary, so... rebase or
    #    force... but no concern for GPW).
  else
    # The rebase boundary is a local branch, or SHA.
    # On push: pw/in tag, local 'release' branch, or version tag.
    # On archive: pw/in tag, or user-specified.
    # On git-sort-by-scope: User-specified.
    # On git-bump-verstion-tag: Same possibilities as push.
    if git_tag_exists "${rebase_boundary}"; then
      >&2 echo "- If this is fixed tag (e.g., a version tag, or the pw/in tag),"
      >&2 echo "  you probably want to fix your work so it's not diverged, e.g.,"
      >&2 echo "    git rebase ${rebase_boundary}"
      >&2 echo "- Or, if you think it's safe, you could move the tag, e.g.,"
      >&2 echo "    git tag -f ${rebase_boundary} <REF>"
    fi
  fi

  return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# 2022-11-14: This function inspired by must_confirm_shares_history_with_head,
# but markedly different, too, especially the ancestor_sha = remote_sha check.
must_confirm_upstream_shares_history_with_head () {
  local remote_ref="$1"
  local strict_check="${2:-false}"

  local head_sha
  head_sha="$(git rev-parse HEAD)"

  if git_is_same_commit "${remote_ref}" "${head_sha}"; then
    if ${strict_check:-false}; then

      return 0
    fi

    >&2 echo "Nothing to pull: Already up-to-date with “${remote_ref}”"

    exit_elevenses
  fi

  local ancestor_sha
  ancestor_sha="$(git merge-base "${remote_ref}" "HEAD")"

  if git_is_same_commit "${ancestor_sha}" "${remote_ref}"; then
    if ${strict_check:-false}; then

      return 0
    fi

    >&2 echo "Nothing to do: “${remote_ref}” is behind HEAD"

    exit_elevenses
  elif [ "${ancestor_sha}" != "${head_sha}" ]; then
    # The common ancestor is not HEAD, which we would expect if the
    # remote publish/release was ahead of release. And since we already
    # checked that publish/release and release don't already reference
    # the same object, and that publish/release is not behind HEAD,
    # and now that publish/release is not ahead of HEAD, it seems the
    # two branches have diverged.
    # - We assume if the ancestor is at least not the first commit,
    #   that it's safe to 3-way rebase.
    #   - FIXME/2024-08-30 11:45: What's a 3-way rebase?
    #     - UTEST: So, what, set remote to *different* project, then pull??
    # FIXME/2024-08-30 11:44: What if they don't share root??
    if [ "${ancestor_sha}" = "$(git_first_commit_sha)" ]; then
      >&2 echo "ERROR: The remote “${remote_ref}” branch does not share history with HEAD"

      exit_1
    fi
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Reorder commits in prep. to diff.
git_sort_by_scope () {
  local rebase_boundary="$1"
  local enable_gpg_sign="${2:-false}"
  local normalize_committer="${3:-false}"

  # Load: prepare_progress_messaging
  _common_source_dep "bin/seq-editor-sort-by-scope-protected-private"
  # Load: git-rebase-sort-by-scope-protected-private
  _common_source_dep "bin/git-rebase-sort-by-scope-protected-private"

  # CXREF: ~/.kit/git/git-put-wise/bin/git-rebase-sort-by-scope-protected-private
  ${DRY_ECHO} git-rebase-sort-by-scope-protected-private \
    "${rebase_boundary}" \
    "${_magic_starting_ref:-false}" \
    "${enable_gpg_sign}" \
    "${_insist_signing_key:-false}" \
    "${normalize_committer}"
}

# So that you can source common_put_wise.sh without also sourcing git-put-wise
_common_source_dep () {
  local dep_path="$1"

  if [ "$(type -t source_dep)" = "function" ]; then
    # Path when git-put-wise has been sourced.
    source_dep "${dep_path}"
  elif [ -n "${BASH_SOURCE[0]}" ]; then
    # Path when this file was sourced, but not git-put-wise.
    # - This file at lib/common_put_wise.sh, so project root is parent dir.
    local project_root
    project_root="$(dirname -- "${BASH_SOURCE[0]}")/.."

    dep_path="${project_root}/${dep_path}"

    if [ ! -f "${dep_path}" ]; then
      >&2 echo "GAFFE: Incorrect dependency path resolved: ${dep_path}"

      exit_1
    fi

    . "${dep_path}"
  else
    >&2 echo "GAFFE: Please try running git-put-wise, or sourcing from Bash"

    exit_1
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# CALSO: For similar staged and unstaged WIP support, see git-bump's:
#   git_wip_staged_if_untidy
#   git_wip_commit_if_untidy
#   git_undo_staged_wip_commit_maybe
#   git_pop_wipped_wip_commit_maybe
# - CXREF: ~/.kit/git/git-bump-version-tag/bin/git-bump-version-tag

# Make a WIP commit if we must.
# - Similar to git-smart's `git wip`.
maybe_stash_changes () {
  local context="${1:-git-put-wise}"

  # E.g., "PRIVATE: WIP [git-put-wise]"
  local wip_commit_message="${PRIVATE_PREFIX:-PRIVATE: }WIP [${context}]"

  local pop_after=false

  # ALTLY/2024-09-01: We could skip the status check,
  # and *always* make 2 commits using --allow-empty.
  # - Then we wouldn't have to track pop_after, we
  #   could just always checks for 2 WIP commits.

  # Note that `git add -A` also fails if nothing changed.
  if test -n "$(git status --porcelain=v1)"; then
    pop_after=true

    # We could check git_nothing_staged, and track both is-staged and is-wipped.
    # But it's easier to *always* make and pop 2 WIP commits, then we can easily
    # support stashing either or both staged and unstaged changes.
    # - This first commit picks up anything that might be staged.
    git commit -q --no-verify --allow-empty -m "${wip_commit_message} (staged)"

    # This second commit picks up changes that were unstaged (or maybe it's
    # an empty commit).
    git add -A
    git commit -q --no-verify --allow-empty -m "${wip_commit_message} (working)"
  fi

  echo ${pop_after}
}

maybe_unstash_changes () {
  local pop_after="$1"

  if ${pop_after}; then
    if is_latest_commit_wip_commit_working; then
      # Aka `git pop1`.
      git reset --quiet --mixed @~1
    fi

    if is_latest_commit_wip_commit_staged; then
      # Aka `git undo`.
      git reset --quiet --soft @~1
    fi
  fi
}

is_latest_commit_wip_commit_staged () {
  git log -1 --format=%s | grep -q -e "^${PRIVATE_PREFIX:-PRIVATE: }WIP .*(staged)$"
}

is_latest_commit_wip_commit_working () {
  git log -1 --format=%s | grep -q -e "^${PRIVATE_PREFIX:-PRIVATE: }WIP .*(working)$"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

put_wise_rebase_continue () {
  # Pretty bland.
  git rebase --continue
}

put_wise_rebase_abort () {
  source_dep "deps/git-smart/bin/git-abort"

  # Calls our 'exec' callbacks (that were tagged " #git-abort").
  git_abort
}

# Set rebase-todo 'exec' to call optional user hook, GIT_POST_REBASE_EXEC.
git_post_rebase_exec_inject () {
  local pop_after="${1:-false}"

  must_rebase_todo_exist || return 1

  # ***

  # CXREF: See git-smart for $GITSMART_POST_REBASE_EXECS_TAG details,
  # and why we sleep-& the git-reset (tl;dr avoids failing git-rebase).
  #
  #   https://github.com/landonb/git-smart#💡

  if [ -n "${GIT_POST_REBASE_EXEC}" ]; then
    echo "exec ${GIT_POST_REBASE_EXEC} ${GITSMART_POST_REBASE_EXECS_TAG}" \
      >> "${GIT_REBASE_TODO_PATH}"
  fi

  if ${pop_after}; then
    # Make a delayed `maybe_unstash_changes` call.
    echo "exec ( sleep 0.1 ;
      git log -1 --format=%s
        | grep -q -e \"^${PRIVATE_PREFIX:-PRIVATE: }WIP \\\\[.*(working)$\"
      && git reset -q --mixed @~1 ;
      git log -1 --format=%s
        | grep -q -e \"^${PRIVATE_PREFIX:-PRIVATE: }WIP \\\\[.*(staged)$\"
      && git reset -q --soft @~1 ;
      ) & ${GITSMART_POST_REBASE_EXECS_TAG}" \
        | sed 's/^ \+/ /' \
        | tr -d '\n' \
        >> "${GIT_REBASE_TODO_PATH}"
  fi
}

git_post_rebase_exec_run () {
  local pop_after="${1:-false}"

  maybe_unstash_changes ${pop_after}

  # Run any post-rebase user hooks.
  if [ -n "${GIT_POST_REBASE_EXEC}" ]; then
    eval ${GIT_POST_REBASE_EXEC}
  fi
}

must_rebase_todo_exist () {
# Not all rebase operations leave a rebase-todo.
# - E.g., `git pull --rebase --autostash <remote> <branch>`,
#   where the remote is one commit ahead, but you've got an
#   uncommitted local file that would be replaced by the remote
#   file (just a case I happened to test), will spew an error,
#   finishing with "Aborting", and doesn't leave user mid-merge.

  if [ ! -f "${GIT_REBASE_TODO_PATH}" ]; then
    # Should be unreachable unless Git changes something.
    # - Or if put-wise is in an unknown state, or has a misperception
    #   about the state of a git op.
    >&2 error "ERROR: Expected rebase-todo at: ${GIT_REBASE_TODO_PATH}"

    # Trip errexit so user-dev can fix.
    return 1
  fi

  return 0
}

# ***

git_post_rebase_exec_inject_callback () {
  must_rebase_todo_exist || return 1

  # Must sleep so git-rebase finishes (cannot cleanup while detached
  # HEAD or mess with branch too much, lest git-rebase fault us).

  echo "exec sleep 0.1 && \"$0\" $@ & ${GITSMART_POST_REBASE_EXECS_TAG}" \
    >> "${GIT_REBASE_TODO_PATH}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# CXREF: This hook called on exit by deps/sh-err-trap/lib/err-trap.sh
# - On DepoXy at: ~/.kit/sh/sh-err-trap/lib/err-trap.sh

PW_PID_KILL_ON_ERROR=${PW_PID_KILL_ON_ERROR}

# Used by tig config to kill tig on error, so that tig stops running
# and dumps user back to console so that the user can see the error.
sh_err_trap_user_hook () {
  local normal_exit="$1"
  local return_value="$2"

  if [ -z "${PW_PID_KILL_ON_ERROR}" ] \
    || ( [ ${return_value} -eq 0 ] \
      && [ ! -f "${GIT_REBASE_TODO_PATH}" ] ) \
  ; then

    return 0
  fi

  # return_value nonzero and/or git-rebase-todo exists.

  local proc_name
  proc_name="$(ps -o comm= ${PW_PID_KILL_ON_ERROR})"

  local says_who=""
  if [ ${return_value} -ne 0 ]; then
    says_who="nonzero exit"
  fi
  if [ -f "${GIT_REBASE_TODO_PATH}" ]; then
    [ -z "${says_who}" ] || says_who="${says_who}, and "
    says_who="${GIT_REBASE_TODO_PATH}"
  fi

  >&2 echo
  >&2 echo -e "Killing \`${proc_name}\` because you got work to do\n (says ${says_who})"
  >&2 echo "  🥩 🥩 chop chop"
  >&2 echo

  kill -s 9 ${PW_PID_KILL_ON_ERROR}
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
    >&2 echo "GAFFE: Missing early_commit [must_confirm_commit_at_or_behind_commit]"

    return 1
  elif git_is_empty_tree "${early_commit}"; then
    # Aka the mother of all commits. Also a tree, so cannot merge-base, e.g.,:
    #   $ git merge-base --is-ancestor ${GIT_EMPTY_TREE} HEAD
    #   error: object 4b825dc642cb6eb9a060e54bf8d69288fbee4904 is a tree, not a commit
    #   fatal: Not a valid commit name refs/tags/pw/private/in

    return 0
  elif ! git merge-base --is-ancestor "${early_commit}" "${later_commit}"; then
    # early later than later, or diverged.

    local common_ancestor
    common_ancestor="$(git merge-base "${early_commit}" "${later_commit}")"

    debug "Common ancestor of ${early} and ${later} is $(shorten_sha "${common_ancestor}")"

    if ! git merge-base --is-ancestor "${later_commit}" "HEAD"; then
      # E.g., when comparing 'publish/release' (early) vs local 'release'
      # (later), this would mean local 'release' is diverged from the
      # local branch (which might be 'private').
      #
      # 2023-01-16: I don't think code is designed to flow through here.
      >&2 echo "GAFFE: Unexpected: later_commit (${later}) not --is-ancestor HEAD"

      return 1
    fi

    if [ "${common_ancestor}" = "$(git_commit_object_name ${later_commit})" ]; then
      # later behind early.
      local branch_name="$(git_branch_name)"

      >&2 echo "ERROR: Not expecting ${early} ahead of ${later}"
      # MAYBE/2024-03-28: Add divergent_ok CLI arg?
      >&2 echo "- Hint: If that's not a big deal to you, just move the pointer:"
      if [ "${branch_name}" != "${early}" ]; then
        >&2 echo "    git branch -f ${later_commit} ${early_commit}"
      else
        >&2 echo "    git merge --ff-only ${early_commit}"
      fi

      return 1
    fi

    # Because (later < early OR later <> early) AND (later is not common
    # ancestor), therefore later <> early (they've diverged).

    if git merge-base --is-ancestor "${early_commit}" "HEAD"; then
      >&2 echo "GAFFE: Impossible: ${early} <> ${later} but each <= HEAD ??"

      return 1
    elif ! ${divergent_ok}; then
      >&2 echo "ERROR: These objects have diverged: ${early} and ${later}"

      return 1
    fi
  fi

  return 0
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# NOTED: Per `man gitrevisions` the regex approach won't work, e.g.,
#   git --no-pager log -1 --format="%H" ":/${matchstr}"
# b/c regex "returns the youngest matching commit which is reachable
# from any ref". git-log also lists ancestor refs down to root.
#
# NOTED: Also note that --reverse doesn't work with -1, e.g.,
#   git --no-pager log --pretty=%H --grep '^PROTECTED: ' -1
# and
#   git --no-pager log --pretty=%H --grep '^PROTECTED: ' -1 --reverse
# both return the same, youngest match.

# Inhibit stderr, e.g.,
#   $ git log -1
#   fatal: your current branch 'release' does not have any commits yet

# CXREF/2022-10-27: must_find_matching_commit from git-smart:
#   ~/.kit/git/git-smart/bin/git-rebase-bubble-commit
find_oldest_commit_by_message () {
  local matchstr="$1"

  git --no-pager log --pretty=format:"%H" --grep "${matchstr}" 2> /dev/null \
    | tail -1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# COPYD: See `periodically_fetch` from git-bump-version-tag, in DepoXy at:
#   ~/.kit/git/git-bump-version-tag/bin/git-bump-version-tag
# - Though without branch_name support.

git_fetch_with_backoff () {
  local remote_name="$1"
  local branch_name="$2"

  # Set by the is-expired fcn.
  local branch_ref=""
  local cfg_section=""
  local cfg_last_fetch=""

  if is_git_fetch_backoff_expired "${remote_name}" "${branch_name}"; then
    # git-fetch prints progress to stderr, which we ignore ('-q' also works).
    if ! git fetch "${remote_name}" ${branch_ref} 2> /dev/null; then
      git config --unset ${cfg_section}.${cfg_last_fetch}

      return 1
    fi

    git config ${cfg_section}.${cfg_last_fetch} "$(date +%s)"
  fi
}

is_git_fetch_backoff_expired () {
  local remote_name="$1"
  local branch_name="$2"

  branch_ref=""
  [ -z "${branch_name}" ] || branch_ref="refs/heads/${branch_name}"

  # E.g., "tools.git-put-wise", or
  # "tools.git-rebase-sort-by-scope-protected-private".
  cfg_section="tools.${PROG_NAME}"
  cfg_last_fetch="lastfetch--${remote_name}${branch_name:+--${branch_name}}"

  local last_update="$(git config ${cfg_section}.${cfg_last_fetch})"

  local backoff_time_ago
  backoff_time_ago="$(date -d "${PW_OPTIONS_FETCH_BACKOFF:--1 hour}" +'%s')"

  [ -z "${last_update}" ] || [ ${last_update} -le ${backoff_time_ago} ]
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

commit_changes_and_counting () {
  if [ $(git_number_of_commits) -eq 1 ]; then
    # Very first --archive!
    # See also: PW_PATCHES_REPO_MESSAGE_INIT="🥨"
    ${DRY_ECHO} git commit -q -m "1${PW_PATCHES_REPO_MESSAGE_CHCHCHANGES}"
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
    ${DRY_ECHO} git commit -q ${amend} --no-verify \
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
    ! command du --version > /dev/null 2>&1 || return 0

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
      | command du -b --total --files0-from - \
      | tail -1 \
      | awk '{ print $1 }'
  }

  tree_size_bytes_exclude_git () {
    find . -path ./.git -prune -o -type f -print0 \
      | command du -b --total --files0-from - \
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

  ${DRY_ECHO} git reflog expire --expire=now --all

  ${DRY_ECHO} git gc --prune=now --quiet

  ${DRY_ECHO} du-h-d-0-I-.git-. "  " "after"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# CPYST:
#   . ~/.kit/git/git-put-wise/deps/sh-git-nubs/lib/git-nubs.sh
#   . ~/.kit/git/git-put-wise/lib/common_put_wise.sh
#   decrypt_asset "path" | tar xvJ

encrypt_asset () {
  local crypt_path="$1"
  local cleartext_name="$2"

  >&2 debug "Encrypt ${cleartext_name:-stdin} → ${crypt_path}"

  if [ -n "${cleartext_name}" ]; then
    if [ -n "${PW_OPTION_PASS_NAME}" ]; then
      # Warm the GPG cache.
      pass "${PW_OPTION_PASS_NAME}" > /dev/null

      # Note that --passphrase-fd ignored unless --batch.
      pass "${PW_OPTION_PASS_NAME}" | head -1 |
        gpg --batch --passphrase-fd 0 -o "${crypt_path}" --cipher-algo AES256 -c "${cleartext_name}"
    else
      gpg -o "${crypt_path}" --cipher-algo AES256 -c "${cleartext_name}"
    fi
  else
    # Assume on stdin. Only used when PW_OPTION_PASS_NAME unset, e.g.,
    #   echo "Encrypt this data" | PW_OPTION_PASS_NAME="" encrypt_asset encrypted.out
    # because the PW_OPTION_PASS_NAME path above uses stdin to pipe the passphrase.
    if [ -n "${PW_OPTION_PASS_NAME}" ]; then
      >&2 echo "ERROR: Please specify encrypt_asset input file, or unset PW_OPTION_PASS_NAME"

      return 1
    fi

    if [ -n "${crypt_path}" ]; then
      gpg -o "${crypt_path}" --cipher-algo AES256 -c
    else
      # To stdout.
      gpg --cipher-algo AES256 -c
    fi
  fi
}

decrypt_asset () {
  local crypt_path="$1"

  if [ -n "${crypt_path}" ]; then
    if [ -n "${PW_OPTION_PASS_NAME}" ]; then
      # Warm the GPG cache.
      pass "${PW_OPTION_PASS_NAME}" > /dev/null

      pass "${PW_OPTION_PASS_NAME}" | head -1 |
        gpg --batch --passphrase-fd 0 \
          -q -d "${crypt_path}"
    else
      gpg -q -d "${crypt_path}"
    fi
  else
    # Assume on stdin.
    if [ -n "${PW_OPTION_PASS_NAME}" ]; then
      >&2 echo "ERROR: Please specify decrypt_asset input file, or unset PW_OPTION_PASS_NAME"

      return 1
    fi

    gpg -q -d
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

    exit_1
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

      exit_1
    fi

    prompt_user_and_change_branch_if_working_branch_different_retrcpt \
      "${patch_branch}" "${ret_rec_plain_path}" "${gpg_rr}"
  fi

  local failed=0

  for host_nrev_line in "${host_nrev_lines}"; do
    if ! echo "${host_nrev_line}" | grep -q \
      -e "^[[:digit:]]\+ [[:xdigit:]]\+ [^[:space:]]\+ [[:xdigit:]]\+ [[:xdigit:]]\+$"; \
    then
      >&2 echo "ERROR: Unexpected return receipt line: “${host_nrev_line}”"
      >&2 echo "- From plaintext “${ret_rec_plain_path}”"
      >&2 echo "- From crypttext “${gpg_rr}”"

      exit_1
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

  cd "${before_cd}"

  ${DRY_ECHO} command rm -f "${ret_rec_plain_path}"

  [ ${failed} -eq 0 ] || exit_1

  debug "git rm -q \"${gpg_rr}\""
  ${DRY_ECHO} git rm -q "${gpg_rr}"

  commit_changes_and_counting
}

# ***

must_find_path_starting_with_prefix_dash_dash () {
  local gpgf="$1"

  local file_guess
  file_guess="$(command ls -A1d "${gpgf}"--*)"

  if [ $(printf "${file_guess}" | wc -l) -gt 0 ]; then
    >&2 warn "Found more than one match for “${gpgf}” (and using first one found)."
    >&2 warn "- Found the following files:\n${file_guess}"

    file_guess="$(echo "${file_guess}" | head -1)"
  fi

  # If nothing found, smells like a DEV issue. Or requires user to return
  # put-wise patchr repo to a known/expected state.
  if [ -z "${file_guess}" ]; then
    >&2 echo "ERROR: Unexpectedly found nothing unpacked for “${gpgf}--*”."

    exit_1
  fi

  printf "${file_guess}"
}

# ***

split_on_double_dash () {
  local text="$1"
  local count="$2"

  python3 -c \
    "import re ; print(
      re.sub(
        '--',
        ' ',
        '${text}',
        count=${count}
  ))"
}

check_dep_python3 () {
  hint_install_deb () { >&2 echo "  sudo apt-get install python3"; }
  hint_install_brew () { >&2 echo "  brew install python@3.12"; }

  check_dep_with_hint 'python3' || exit_1
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
    >&2 echo "    git rm $(basename -- "${gpg_rr}")"
    >&2 echo "    git commit --amend --no-edit --allow-empty"

    return 1
  fi

  # MAYBE/2023-02-25: If pw/in diverged from HEAD, we may need to improve
  # the code, or add UX messaging to help user recover from the situation.
  # - Use case: User rebased past pw/in, so remote commit-count meaningless,
  #             and we cannot proceed with the --apply.
  local divergent_ok=false
  must_confirm_commit_at_or_behind_commit \
    "refs/tags/${pw_tag_applied}" "${patch_branch}" \
    ${divergent_ok} \
    "pick-from" "this branch" \
    || exit_1

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

    local commit_hash=$( \
      git --no-pager log --format=%H --skip=${skip_commits} --max-count=1 "${patch_branch}"
    )

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
    ${DRY_ECHO} git tag -f "${pw_tag_applied}" "${commit_hash}" > /dev/null
  else
    echo "Disregarding count:"
    echo "  local count ${previous_cnt} [${pw_tag_applied}] >= receipt count ${remote_rev_tot}"
  fi

  return 0
}

# ***

prompt_user_and_change_branch_if_working_branch_different_retrcpt () {
  local patch_branch="$1"
  local ret_rec_plain_path="$2"
  local gpg_rr="$3"

  local project_path="$(pwd -L)"

  if ! git_branch_exists "${patch_branch}"; then
    >&2 echo
    >&2 echo "ERROR: The patches branch does not exist."
    >&2 echo "- The return receipt branch: ${patch_branch}"
    >&2 echo "  in the project located at: ${project_path}"
    >&2 echo "  per the return receipt at: ${ret_rec_plain_path}"
    >&2 echo "- You can use the -b|--branch arg (or PW_OPTION_BRANCH var)"
    >&2 echo "  to specify a specific branch for the receipt."
    >&2 echo "- Or you can just delete the receipt."
    >&2 echo
    >&2 echo "Please either specify the branch, remove the receipt,"
    >&2 echo "or create the missing branch:"
    >&2 echo
    >&2 echo "    # Specify a different branch."
    >&2 echo "    $(ps -ocommand= -p ${PPID}) -b <branch>"
    >&2 echo
    >&2 echo "    # Or remove the receipt."
    >&2 echo "    cd ${PW_PATCHES_REPO}"
    >&2 echo "    git rm $(basename -- "${gpg_rr}")"
    >&2 echo "    git commit --amend --no-edit --allow-empty"
    >&2 echo
    >&2 echo "    # Or you do you, maybe create the branch."

    return 1
  fi
}

# ***

checkout_branch_quietly () {
  local branch_name="$1"

  [ -n "${branch_name}" ] || return 0

  ${DRY_ECHO} git checkout -q "${branch_name}"
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

badger_user_rebase_failed () {
  >&2 echo "============================================"
  >&2 echo
  >&2 echo "Uffda! You got work to do ☝ ☝ ☝."
  >&2 echo
  # Note that `git put-wise --continue` just calls `git rebase --continue`.
  # - But `git rebase --abort` calls `git abort`, to run `exec` callbacks.  #git-abort
  >&2 echo "  🚨 $(echo_alert "ALERT") 🚨"
  >&2 echo "  Resolve conflicts and call \`git put-wise --continue\`"
  >&2 echo "   — or call \`git put-wise --abort\` to revert changes."
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

echo_announce () {
  echo $2 "$(fg_lightblue)$(bg_myrtle)${1}$(attr_reset)"
}

echo_alert () {
  echo $2 "$(attr_bold)$(fg_black)$(bg_lightorange)${1}$(attr_reset)"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PROG_NAME="$(basename -- "$0")"

insist_sourced_in_bash () {
  # Alert if not being sourced in Bash, or if being executed.
  if [ -z "${BASH_SOURCE}" ] || [ "$0" = "${BASH_SOURCE[0]}" ]; then
    >&2 echo "ERROR: Source this script with Bash [${PROG_NAME}]"

    return 1
  fi
}

insist_sourced_in_bash

