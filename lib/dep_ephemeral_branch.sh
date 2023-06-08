#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

prepare_ephemeral_branch_if_commit_scoping () {
  local ephemeral_branch="$1"
  local patch_base="$2"

  [ -n "${patch_base}" ] || return 0

  # If patch_base is HEAD, don't need ephemeral branch...
  # - Although maybe it's useful in case there are conflicts.
  #  [ "$(git_commit_object_name "${patch_base}")" \
  #    != "$(git_commit_object_name)" ] || return 0

  # If current branch not 'private' or 'release', maybe don't
  # enforce these conventions. But doing so for now, because
  # I don't have a compelling use case not to enforce these.

  # Verify that the oldest commit with private scoping is *after* any of
  # 'release', 'publish/release', or 'entrust/scoping'.
  # - If you stick to using put-wise, this scenario shouldn't happen.
  #   If it did happen, it would be the user going off-script.
  local divergent_ok=true
  if git_remote_branch_exists "${REMOTE_BRANCH_SCOPING}"; then
    must_confirm_commit_at_or_behind_commit \
      "refs/remotes/${REMOTE_BRANCH_SCOPING}" "${patch_base}" ${divergent_ok}
  fi
  if [ "$(git_branch_name)" != "${LOCAL_BRANCH_RELEASE}" ]; then
    if git_branch_exists "${LOCAL_BRANCH_RELEASE}"; then
      must_confirm_commit_at_or_behind_commit \
        "refs/heads/${LOCAL_BRANCH_RELEASE}" "${patch_base}"
    fi
  fi
  if git_remote_branch_exists "${REMOTE_BRANCH_RELEASE}"; then
    must_confirm_commit_at_or_behind_commit \
      "refs/remotes/${REMOTE_BRANCH_RELEASE}" "${patch_base}"
  fi

  # E.g., git co -b pw-patches-<branch_name> abcd1234
  >&2 echo "git checkout -b \"${ephemeral_branch}\" \"${patch_base}\" --no-track"
  ${DRY_RUN} git checkout -b "${ephemeral_branch}" "${patch_base}" --no-track

  echo "${ephemeral_branch}"
}

# ***

cleanup_ephemeral_branch () {
  local ephemeral_branch="$1"

  [ -n "${ephemeral_branch}" ] || return 0

  ${DRY_RUN} git branch -q -d "${ephemeral_branch}"
}

# ***

must_prompt_user_and_await_resolved_uffda () {
  echo "============================================"
  echo
  echo "Uffda! You got work to do ☝ ☝ ☝."
  echo
  echo "Come back here when y'all are ready, 👍"
  echo
  printf "Answer “y” to continue when you're ready, or die [Y/n] "

  # exit's 1 on anything but 'y' or 'Y'
  must_await_user_resolve_conflicts_read_input
}

# ***

must_insist_ephemeral_branch_does_not_exist () {
  # E.g., pw-patches-<branch_name>
  local ephemeral_branch="$1"

  $(git_branch_exists "${ephemeral_branch}") || return 0

  echo "ERROR: Please delete the “${ephemeral_branch}” branch."
  echo
  echo "- Obviously, do what you want to it first."
  echo "  But we delete that branch when we're done with it, so its"
  echo "  mere presence is scary to us. We might have crashed and"
  echo "  left it there, sorry, but clean up that mess thanks"

  return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE}" ]; then
  >&2 echo "😶"
fi

