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
    scope_ends_at="$(find_oldest_commit_by_message "${message_re}")"

    [ -z "${scope_ends_at}" ] || break
  done

  if [ -z "${scope_ends_at}" ]; then
    scope_ends_at="HEAD"
  else
    scope_ends_at="${scope_ends_at}^"
  fi

  printf "${scope_ends_at}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

