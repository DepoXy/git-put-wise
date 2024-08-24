#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2024 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# - git-commit options used below:
#     -n : --no-verify (skip hooks)
#     -S : --gpg-sign [${gpg_sign}]
#     --amend : redo current commit
#     --no-edit : use same commit message
#     -q : be quiet, else prints, e.g.,
#          "[detached HEAD 76fc9f4] <message>"
#
# - git-rebase itself prints each exec, e.g.,
#     Executing: git commit --amend --no-edit -n -S
#   which we'll dispose of and replace with our own countdown.
#
# - Note the `declare -f` Bashism, which lets us avoid needing
#   to tediously escape the exec, e.g., avoids this:
#     git rebase --exec " \
#       foo () { \
#         local cur_count=\"$(cat \"${countdown_f}\")\"; \
#         printf \"\b\b\b\b%s...\" \"${cur_count}\"; \
#         git commit --amend --no-edit -n -S -q; \
#         printf \"%s\" \"$((${cur_count} - 1))\" > \"${countdown_f}\" \
#       }; foo" ${starting_ref}
#
# - As an alternative to git-rebase, we could use the old `git filter-branch`.
#   - But not the newer `git filter-repo`, which does not support GPG signing
#     (tho someday?): https://github.com/newren/git-filter-repo/issues/67
#   - And `git filter-branch` has its drawbacks:
#     - In the author's completely unscientific and didn't-use-that-many-
#       commits and-it-was-just-one-test test, to resign 9 commits took
#       git-rebase 2s, and it took git filter-branch 3s.
#     - git filter-branch also prints a warning:
#         WARNING: git-filter-branch has a glut of gotchas generating mangled history
#            rewrites.  Hit Ctrl-C before proceeding to abort, then use an
#            alternative filtering tool such as 'git filter-repo'
#            (https://github.com/newren/git-filter-repo/) instead.  See the
#            filter-branch manual page for more details; to squelch this warning,
#            set FILTER_BRANCH_SQUELCH_WARNING=1.
#         Proceeding with filter-branch...
#       - And then proceeds anyway before you have time to read the whole message,
#         ha.
#     - In any case, for resigning, the author *guesses* it's "safe" to use
#       filter-branch, which you could try, e.g.,
#         FILTER_BRANCH_SQUELCH_WARNING=1 \
#           git filter-branch --commit-filter 'git commit-tree -S "$@";' ${starting_ref}..HEAD
#       but, as noted, it's not likely to be any faster.
#       Also then we can't use our own countdown progress display.
#
# REFER/THANX: https://superuser.com/questions/397149/can-you-gpg-sign-old-commits
#   https://stackoverflow.com/questions/66843980/resign-previous-git-commits-with-a-new-gpg-key

force_rebase_and_resign_maybe () {
  local gpg_sign="$1"
  local head_sha_before_rebase="$2"
  local starting_ref="$3"

  if [ -z "${gpg_sign}" ]; then

    return 0
  fi

  if [ -z "$(git config user.signingKey)" ]; then
    echo "Skipped commit signing: no user.signingKey"

    return 0
  fi

  if [ -n "${head_sha_before_rebase}" ]; then
    local head_sha_after_rebase
    head_sha_after_rebase="$(git rev-parse HEAD)"

    if [ "${head_sha_after_rebase}" != "${head_sha_before_rebase}" ]; then
      # The rebase that just ran signed the commits.

      return 0
    fi
  fi

  # Else, the git-rebase that was previously called didn't change anything,
  # so we can use `git rebase --exec` to force it.
  #
  # But first check if the commits are already signed.

  local n_commits
  n_commits="$(git rev-list --count ${starting_ref}..HEAD)"

  # Check if already signed.
  # - %G? : "G" for good/valid sig, "B" for bad, "U" for good w/ unknown validity,
  #         "X" for good but expired, "Y" for good made by expired key,
  #         "R" for good made by revoked key, "E" if sig cannot be checked
  #         (e.g. missing key) and "N" for no signature
  if ! git log --format="%G?" ${starting_ref}..HEAD | grep -q -e 'N'; then
    echo "✓ Verified ${n_commits} signed commit(s)"

    return 0
  fi

  rebase_and_resign "${starting_ref}" "${n_commits}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# USYNC: Keep this environ path and the one embedded in the exec below synced.
# - Also note you can `export PW_REBASE_CACHE_COUNTDOWN=...` from your shell
#   and it will work in the exec.
PW_REBASE_CACHE_COUNTDOWN="${PW_REBASE_CACHE_COUNTDOWN:-.git/put-wise-countdown}"

rebase_and_resign () {
  local starting_ref="$1"
  local n_commits="$2"

  local countdown_f="${PW_REBASE_CACHE_COUNTDOWN}"

  printf "%s" "${n_commits}" > "${countdown_f}"

  # USYNC: Keep this prog_prefix and one below synced.
  local prog_prefix="Signing commits: "

  local orig_progress="${prog_prefix}${n_commits}..."
  printf "%s" "${orig_progress}"

  resign_ci () {
    # Run from git --exec callback, so errexit no longer enabled.
    set -e

    local countdown_f="${PW_REBASE_CACHE_COUNTDOWN:-.git/put-wise-countdown}"

    local cur_count="$(cat ${countdown_f})"
    local prog_prefix="Signing commits: "
    printf "\r%s%s..." "${prog_prefix}" "${cur_count}"

    git commit --amend --no-edit --allow-empty --no-verify -S -q

    printf "%s" "$((${cur_count} - 1))" > "${countdown_f}"
  }

  # The --exec option forbids newlines, the author likes to condense
  # whitespace for readability when debugging, and --exec expects a
  # final semicolon before the closing brace, which `declare -f` does
  # not print.
  local exec_cmd="$( \
    declare -f resign_ci \
    | tr -d '\n' \
    | sed \
      -e 's/ \+/ /g' \
      -e 's/}$/;}/' \
  )"

  local ret_code=0
  local errs
  # Capture stderr and let stdout spew.
  # - Note git-rebase emits '\r' to clear its progress,
  #   or at least there's \r in the output.
  errs="$( \
    git rebase -q --exec "${exec_cmd}; resign_ci" ${starting_ref} 3>&1 >&2 2>&3 3>&- \
    | tr -d '\r' \
    | sed '/Executing: resign_ci () { /d'
  )" || ret_code="$?"

  if [ -n "${errs}" ] || [ ${ret_code} != 0 ]; then
    >&2 echo
    >&2 echo "ERROR: \`git rebase --exec\` failed (${ret_code}):"
    >&2 echo
    >&2 echo "  $ git rebase --exec \"${exec_cmd}; resign_ci\" ${starting_ref}"
    >&2 echo
    echo "${errs}" | >&2 sed 's/^/  /'

    return 1
  else
    printf "\r%s" "$(echo "${orig_progress}" | sed 's/./ /g')"
    printf "\r%s\n" "Signed ${n_commits} commit(s)"
  fi

  command rm -- "${countdown_f}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

