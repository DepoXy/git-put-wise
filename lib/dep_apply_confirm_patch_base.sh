#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# REFER: These emoji all show up in tig @linux: 🚩🏁🔀🖖
PW_TAG_APPLY_INSERT_HERE_TAG="pw-🖖-INSERT-HERE"

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

choose_patch_base_or_ask_user () {
  local starting_sha="$1"
  local pw_io_tag_name="$2"
  local pw_ontime_tag_name="$3"
  local patch_branch="$4"

  patch_base=""

  local describe_patch=""
  local do_confirm=false

  # MAYBE/2022-12-15: Support --starting-sha option.

  # E.g., 'pw-apply-here' on --apply, 'pw-start-here' on --archive.
  if git_tag_exists "${pw_ontime_tag_name}"; then
    info "Found explicit user starting tag ‘${pw_ontime_tag_name}’,"
    patch_base="$(git_commit_object_name "${pw_ontime_tag_name}")"
    describe_patch="We found your ‘${pw_ontime_tag_name}’ tag"
    do_confirm=true
  # The starting SHA from the GPG filename.
  elif git_is_commit "${starting_sha}"; then
    info "Confirmed starting ref (${starting_sha}) is a known object."
    patch_base="${starting_sha}"
    describe_patch="The given starting ref (${starting_sha}) is valid"
    do_confirm=false
  # The most recent --apply pw/<branch>/in tag for --archive,
  #          or the --archive pw/<branch>/out tag for --apply.
  elif git_tag_exists "${pw_io_tag_name}"; then
    info "Found a put-wise-managed ‘${pw_io_tag_name}’."
    patch_base="$(git_tag_object_name "${pw_io_tag_name}")"
    describe_patch="We found a ‘${pw_io_tag_name}’ tag from a previous put-wise"
    do_confirm=true
  # If nothing else, put-wise likely never used on project before.
  else
    # Because put-wise maintains the pw/branch/out tag perennially, this
    # case only happens once, the first time a project is put-under-wise.
    # But if the pw/branch/out tag is removed, it'll happen again.
    local num_commits=$(git_number_of_commits)
    if [ ${num_commits} -eq 1 ]; then
      info "Only one commit; no choice but HEAD"
      patch_base="HEAD"
      describe_patch="There's only 1 commit we can apply to"
      do_confirm=false
    else
      # Means pw/branch/out was removed by the user.
      warn "No tags, and starting ID unknown; will try furthest along upstream"
    fi
  fi

  local scoping_starts_at=""
  scoping_starts_at="$(determine_scoping_boundary "${patch_branch}")"

  # Ensure we don't rebase past published work. Compare the desired patch_base
  # against the upstream scoping remote branch, as well as the release remote
  # and local release branches, should it happen that the user pushlished locally
  # but didn't apply the remote changes before --archiving. Because the world
  # moves fast sometimes, we get it, but don't make things unnecessarily
  # complicated for yourself. Stick to the plan.
  local furthest_along
  suss_which_known_branch_is_furthest_along "${patch_base}"

  if [ -z "${patch_base}" ]; then
    # Happens when neither tag nor starting-sha, and more than 1 commit.
    # Essentially means we have zero information about where to start.
    if [ -n "${furthest_along}" ]; then
      patch_base="${furthest_along}"
      describe_patch="This is the furthest along upstream branch"
    else
      # No upstream branches, local nor remote.
      patch_base="${scoping_starts_at}"
      furthest_along="${patch_base}"
      describe_patch="This is the scoping boundary or HEAD" \
        "(because no upstreams, no tags, unknown starting)"
    fi

    prompt_user_to_verify_patching_sha_fallback "${patch_base}" \
      "${pw_io_tag_name}" "${pw_ontime_tag_name}"
  fi

  if [ "${furthest_along}" != "${patch_base}" ]; then
    info "- Cannot start from there, that commit is behind one or more upstream branches."

    patch_base="${furthest_along}"
    describe_patch="This is the furthest along published ref"
    do_confirm=true
  fi

  # DEVs
  local DEV_prompt_patch_base=false
  DEV_prompt_patch_base=true

  if ${do_confirm} || ${DEV_prompt_patch_base}; then
    git tag -f "${PW_TAG_APPLY_INSERT_HERE_TAG}" "${patch_base}" > /dev/null

    local coach_said_not_to=true

    prompt_user_to_verify_patching_sha_extrazealous \
      "${describe_patch}" "${patch_base}" "${pw_ontime_tag_name}" \
      || coach_said_not_to=false

    git tag -d "${PW_TAG_APPLY_INSERT_HERE_TAG}" > /dev/null 2>&1 || true

    ${coach_said_not_to} || exit 1
  fi

  # ***

  local verified=true  # Benefit of the Doubt.

  # Because HEAD and scoping are in same branch, we only need to check
  # that the patch_base is at or precedes before the scoping boundary,
  # then we can deduce that patch_base is also visible from HEAD.
  # - This condition will have been violated if the user rebased past
  #   patch_base (whether it's starting_sha, pw/branch/out tag, etc.).
  #   There's nothing we can do in this case; the user must fix the
  #   divergence, or find a different starting commit to use.
  #   - User's best option to restore the universe is to rebase their
  #     recent changes on top of the patch_base.
  #   - If they want to force-push instead and deal with the rebase on
  #     the remote, that's their decision, they do they, but this script
  #     won't be involved. This particular sitation also seems like a
  #     rare occurrence, especially if the user only uses put-wise to
  #     manage pushing/archiving and pulling/applying changes.
  if [ -n "${patch_base}" ]; then
    echo "Verifying start commit precedes scoping boundary and HEAD..."
    (must_confirm_commit_at_or_behind_commit "${patch_base}" "${scoping_starts_at}") ||
      verified=false
  fi

  if ! ${verified}; then
    >&2 echo
    >&2 echo "Uh oh. That's bad news."
    >&2 echo
    if [ "${patch_base}" = "${starting_sha}" ]; then
      >&2 echo "The remote knows about a local commit that's no longer"
      >&2 echo "in this branch's history (it's not visible from head)."
    else
      >&2 echo "We chose this as the starting commit because:"
      >&2 echo "  ${describe_patch}"
    fi
    >&2 echo
    if ${PW_ACTION_APPLY} || ${PW_ACTION_APPLY_ALL}; then
      >&2 echo "The best way out of this mess is to rebase that reference"
      >&2 echo "back into view (or delete or move it if you're confident):"
      >&2 echo
      >&2 echo "  ${patch_base}"
    else
      # AWAIT/2022-12-15: When this hits (you'll know why this hits and
      # you can) devise a better message.
      >&2 echo "DEV: Replace this message: Add hint on how to recover."
    fi

    exit 1
  fi

  return 0
}

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

suss_which_known_branch_is_furthest_along () {
  local patch_base="$1"

  # MAYBE/2022-12-11: Would we ever not want to do this?
  # - Because offline, or because these are "slow"?
  if git_remote_branch_exists "${REMOTE_BRANCH_SCOPING}"; then
    # MAYBE/2023-01-18: GIT_FETCH: Use -q?
    git fetch "${SCOPING_REMOTE_NAME}" 2> /dev/null
  fi
  if git_remote_branch_exists "${REMOTE_BRANCH_RELEASE}"; then
    # MAYBE/2023-01-18: GIT_FETCH: Use -q?
    git fetch "${RELEASE_REMOTE_NAME}" 2> /dev/null
  fi

  # ***

  local local_release=""
  if [ "$(git_branch_name)" != "${LOCAL_BRANCH_RELEASE}" ]; then
    local_release="${LOCAL_BRANCH_RELEASE}"
  fi

  # ***

  local tracking_branch=""
  tracking_branch="$(git_tracking_branch_safe)"
  local upstream_remote
  upstream_remote="$(git_upstream_parse_remote_name "${tracking_branch}")"
  if [ -n "${upstream_remote}" ]; then
    # MAYBE/2023-01-18: GIT_FETCH: Use -q?
    git fetch "${upstream_remote}" 2> /dev/null
  fi

  # ***

  local branch_counts
  # ORDER: Keep patch_base first, and use sort -s stable sort option,
  # in case patch_base ties for furthest along with an upstream branch,
  # we want to print the patch_base SHA.
  branch_counts="$(for gitref in \
    "${patch_base}" \
    "${REMOTE_BRANCH_SCOPING}" \
    "${local_release}" \
    "${REMOTE_BRANCH_RELEASE}" \
    "${tracking_branch}" \
  ; do
    [ -n "${gitref}" ] || continue

    num_commits="$(git_number_of_commits "${gitref}" 2> /dev/null)"
    [ -n "${num_commits}" ] || continue

    echo "${num_commits} ${gitref}"
  done | sort -n -s -r)"

  debug "- Branch counts:\n$(echo "${branch_counts}" | sed 's/^/  /')"

  furthest_along="$(echo "${branch_counts}" | head -1 | awk '{ print $2 }')"
}

prompt_user_to_verify_patching_sha_fallback () {
  local patch_base="$1"
  local pw_io_tag_name="$2"
  local pw_ontime_tag_name="$3"

  echo
  echo "You need to verify the SHA on which to git-am apply patches."
  echo
  echo "- Ideally, this script prefers the starting SHA, however:"
  echo
  echo "  - The archive starting SHA is not an object in our repo"
  echo "      (so this project is private on both ends)"
  echo
  echo "  - There's no ${pw_io_tag_name} tag"
  echo "      (so this project is new, or that tag was deleted)"
  echo
  echo "Unless you want to specify the commit yourself, we'll apply"
  echo "patches to the furthest along upstream branch, or to the"
  echo "scoping boundary (if there is one), or to HEAD."
  echo
  print_prompt_user_explainer_using_starting_sha_tag "${pw_ontime_tag_name}"
  echo "Otherwise, answer yes to apply patches after your work,"
  echo "starting at:"
  echo
  echo "    ${patch_base}"
  echo
  printf "Would you like to apply patches after your work? [y/N] "

  # MEH: Offer tig-prompt review. But this case rare/obscure, so not pressing.

  local key_pressed
  local opt_chosen
  prompt_read_single_keypress "n" "y"

  [ "${opt_chosen}" != "y" ] || return 0

  >&2 echo "${PW_USER_CANCELED_GOODBYE}"

  exit 1
}

print_prompt_user_explainer_using_starting_sha_tag () {
  local pw_ontime_tag_name="$1"

  echo "- If you want to specify a different revision,"
  echo "  cancel this prompt (Ctrl-c), and set a tag:"
  echo
  echo "    git tag ${pw_ontime_tag_name} <gitref>"
  echo
}

prompt_user_to_verify_patching_sha_extrazealous () {
  local describe_patch="$1"
  local patch_base="$2"
  local pw_ontime_tag_name="$3"

  echo
  echo "*** Please verify the patch commit — we'll insert patches here"
  echo
  echo "${describe_patch}:"
  echo
  echo "    ${patch_base}"
  echo
  print_prompt_user_explainer_using_starting_sha_tag "${pw_ontime_tag_name}"

  local opt_chosen="y"
  if ${PW_OPTION_QUICK_TIG:-false}; then
    print_tig_review_instructions_apply "${patch_base}"

    prompt_user_to_review_action_plan_using_tig \
      || opt_chosen="n"
  else
    printf "Insert patches starting at commit ‘$(shorten_sha ${patch_base})’? [y/N] "

    # Sets opt_chosen.
    local key_pressed
    prompt_read_single_keypress "n" "y"
  fi

  [ "${opt_chosen}" != "y" ] || return 0

  >&2 echo "${PW_USER_CANCELED_GOODBYE}"

  return 1
}

print_tig_review_instructions_apply () {
  local patch_base="$1"

  # COPYD: See similar `print_tig_review_instructions` function(s) elsewhere.
  print_tig_review_instructions () {
    echo "Please review and confirm the *patch plan*"
    echo
    echo "We'll run tig, and you can look for this tag in the revision history:"
    echo
    echo "  <${PW_TAG_APPLY_INSERT_HERE_TAG}> — Insert patches starting" \
      "at this revision (‘$(shorten_sha ${patch_base})’)"
    echo
    echo "Then press 'w' to confirm the plan and apply patches"
    echo "- Or press 'q' to quit tig and cancel everything"

    # The other `print_tig_review_instructions` prompts before running tig,
    # but it also doesn't print any of these instructions if user has set
    # PW_OPTION_QUICK_TIG. But here we're doing sorta the opposite:
    # only print these instructions if user has PW_OPTION_QUICK_TIG,
    # idea being to print usage to terminal for user to see *after*
    # running tig, so they at least have it in their history (otherwise
    # we don't explain the PW_TAG_APPLY_INSERT_HERE_TAG tag).
    # - MAYBE: Make the behavior consistent: Either:
    #   - Option 1) Print tig instructions, including using PW_OPTION_QUICK_TIG,
    #               and prompt before running tig.
    #               - If PW_OPTION_QUICK_TIG=true, skip pre-tig prompt.
    #   - Option 2) Don't print tig instructions or use tig prompt unless
    #               PW_OPTION_QUICK_TIG=true... but then it's not very
    #               discoverable...
    #   - Note that pw-push always uses tig, so Option 2) wouldn't work
    #     universally...
    #     - MAYBE: So maybe pw-apply needs to always use tig? And to prompt-
    #       wait before running tig unless PW_OPTION_QUICK_TIG=true.
  }
  print_tig_review_instructions
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE}" ]; then
  >&2 echo "😶"
fi

