#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2024 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# RELATED: identify_scope_ends_at
determine_scoping_boundary () {
  local patch_branch="$1"

  local scoping_starts_at=""

  local private_scope_starts_at
  private_scope_starts_at="$(find_oldest_commit_by_message "^${PRIVATE_PREFIX}")"

  local protected_scope_starts_at
  protected_scope_starts_at="$(find_oldest_commit_by_message "^${SCOPING_PREFIX}")"

  # Warn user if PRIVATE precedes (older) than PROTECTED.
  if ! verify_scope_boundary_not_older_than \
    "${private_scope_starts_at}" \
    "${protected_scope_starts_at}" \
  ; then
    # Until fixed, don't let PRIVATE commits bleed out.
    protected_scope_starts_at="${private_scope_starts_at}"
  fi

  # If patches from 'release' but there's only 'private' locally, then
  # also exclude earlier protected-prefix commits from git-am, to avoid
  # conflicts, and because the remote will not have included these.
  if [ "${patch_branch}" != "${LOCAL_BRANCH_PRIVATE}" ]; then
    scoping_starts_at="${protected_scope_starts_at}"
  fi

  if [ -z "${scoping_starts_at}" ]; then
    scoping_starts_at="${private_scope_starts_at}"
  fi

  if [ -z "${scoping_starts_at}" ]; then
    scoping_starts_at="HEAD"
  fi

  printf "${scoping_starts_at}"
}

# ***

# RELATED: determine_scoping_boundary
#
# CPYST:
#   . ~/.kit/git/git-put-wise/deps/sh-git-nubs/lib/git-nubs.sh
#   . ~/.kit/git/git-put-wise/lib/common_put_wise.sh
#   . ~/.kit/git/git-put-wise/lib/dep_apply_confirm_patch_base.sh
#   . ~/.kit/git/git-put-wise/lib/put_wise_push_remotes.sh
#   identify_scope_ends_at "^${PRIVATE_PREFIX}"
#   identify_scope_ends_at "^${SCOPING_PREFIX}" "^${PRIVATE_PREFIX}"
identify_scope_ends_at () {
  local scope_ends_at=""

  for message_re in "$@"; do
    local current_boundary=""
    current_boundary="$(find_oldest_commit_by_message "${message_re}")"

    [ -n "${current_boundary}" ] || continue

    if [ -z "${scope_ends_at}" ] \
      || ! verify_scope_boundary_not_older_than "${current_boundary}" "${scope_ends_at}" \
    ; then
      # If scope_ends_at unset, pick first match.
      # If scope_ends_at set and current_boundary was older, pick older.
      scope_ends_at="${current_boundary}"
    fi
  done

  if [ -z "${scope_ends_at}" ]; then
    scope_ends_at="HEAD"
  else
    scope_ends_at="${scope_ends_at}^"
  fi

  printf "${scope_ends_at}"
}

# ***

verify_scope_boundary_not_older_than () {
  local private_scope_starts_at="$1"
  local protected_scope_starts_at="$2"

  if true \
    && [ -n "${private_scope_starts_at}" ] \
    && [ -n "${protected_scope_starts_at}" ] \
    && ! git_is_same_commit \
      "${private_scope_starts_at}" \
      "${protected_scope_starts_at}" \
    && git merge-base --is-ancestor \
      "${private_scope_starts_at}" \
      "${protected_scope_starts_at}" \
  ; then
    >&2 echo "BWARE: A private commit exists earlier than the first protected commit"
    >&2 echo "- You'll see a “${PRIVATE_PREFIX}” commit" \
      "older than the last “${SCOPING_PREFIX}” commit"
    >&2 echo "- This problem usually solves itself, probably don't sweat it"

    return 1
  fi

  return 0
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

