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

  local patch_base_raw=""
  local describe_patch=""
  local do_confirm=false

  # MAYBE/2022-12-15: Support --starting-sha option.

  # See below: We'll verify: merge-base --is-ancestor ${patch_base} HEAD.

  # E.g., 'pw-apply-here' on --apply, 'pw-start-here' on --archive.
  if git_tag_exists "${pw_ontime_tag_name}"; then
    info "Found explicit user starting tag (${pw_ontime_tag_name})"
    patch_base="$(git_commit_object_name "${pw_ontime_tag_name}")"
    patch_base_raw="${pw_ontime_tag_name}"
    describe_patch="We found your ‘${pw_ontime_tag_name}’ tag"
    do_confirm=true
  # The starting SHA from the GPG filename.
  elif git_is_commit "${starting_sha}" \
    || git_is_empty_tree "${starting_sha}" \
  ; then
    info "Package starting ref is a known object (${starting_sha})"
    patch_base="${starting_sha}"
    patch_base_raw="${starting_sha}"
    describe_patch="The given starting ref (${starting_sha}) is valid"
    do_confirm=false
  # The most recent --apply pw/<branch>/in tag for --archive,
  #          or the --archive pw/<branch>/out tag for --apply.
  elif git_tag_exists "${pw_io_tag_name}"; then
    info "Found a put-wise-managed tag (${pw_io_tag_name})"
    patch_base="$(git_tag_object_name "${pw_io_tag_name}")"
    patch_base_raw="${pw_io_tag_name}"
    describe_patch="We found a ‘${pw_io_tag_name}’ tag from a previous put-wise"
    do_confirm=true
  # If nothing else, put-wise likely never used on project before (well, it's
  # that, or user deleted our tags).
  elif [ $(git_number_of_commits) -eq 0 ]; then
    # New branch/repo.
    info "No known starting ref (${pw_ontime_tag_name}, ${starting_sha}, or ${pw_io_tag_name})"
    patch_base="${GIT_EMPTY_TREE}"
    patch_base_raw="${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}"
    describe_patch="This is an empty/new (orphan) branch"
    do_confirm=false
  else
    # No reference found.
    local scoping_starts_at=""
    scoping_starts_at="$(determine_scoping_boundary "${patch_branch}")"
    info "No known starting ref (${pw_ontime_tag_name}, ${starting_sha}, or ${pw_io_tag_name})"
    patch_base="${scoping_starts_at}"
    patch_base_raw="HEAD"
    describe_patch="This is the scoping boundary or HEAD (b/c no other ref. found)"
    do_confirm=true
  fi

  # Ensure we don't rebase past published work. Compare the desired patch_base
  # against the upstream scoping remote branch, as well as the release remote
  # and local release branches, should it happen that the user pushlished locally
  # but didn't apply the remote changes before --archiving. Because the world
  # moves fast sometimes, we get it, but don't make things unnecessarily
  # complicated for yourself. Stick to the plan.
  local furthest_along
  suss_which_known_branch_is_furthest_along "${patch_base}"

  if [ -n "${furthest_along}" ] && [ "${furthest_along}" != "${patch_base}" ]; then
    info "- Ope, cannot start from there (${patch_base_raw}):"
    info "  - That commit is behind one or more upstream branches"

    patch_base="${furthest_along}"
    describe_patch="This is the furthest along published ref"
    do_confirm=true
  fi

  if [ -z "${patch_base}" ]; then
    >&2 echo "GAFFE: Unexpected: patch_base unsussed (choose_patch_base_or_ask_user)"

    exit_1
  fi

  if git_is_empty_tree "${patch_base}"; then
    patch_base_raw="${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}"
  fi

  local DEV_prompt_patch_base=false
  # USAGE: Set true to always prompt re: patch_base.
  #  DEV_prompt_patch_base=true

  if git_branch_name > /dev/null && ( ${do_confirm} || ${DEV_prompt_patch_base} ); then
    git tag -f "${PW_TAG_APPLY_INSERT_HERE_TAG}" "${patch_base}" > /dev/null

    local coach_said_not_to=true

    prompt_user_to_verify_patching_sha_extrazealous \
      "${describe_patch}" "${patch_base}" "${patch_base_raw}" "${pw_ontime_tag_name}" \
      || coach_said_not_to=false

    git tag -d "${PW_TAG_APPLY_INSERT_HERE_TAG}" > /dev/null 2>&1 || true

    ${coach_said_not_to} || exit_1
  else
    info "Auto-verified the patch commit — we'll insert patches here:"
    info "- Patch starting: ${patch_base_raw} (${patch_base})"
    info "- Chosen because: ${describe_patch}"
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
    echo "Verifying start ref at or before scoped HEAD..."
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
    if ${PW_ACTION_APPLY:-false} || ${PW_ACTION_APPLY_ALL:-false}; then
      >&2 echo "The best way out of this mess is to rebase that reference"
      >&2 echo "back into view (or delete or move it if you're confident):"
      >&2 echo
      >&2 echo "  # Aka ${patch_base_raw}"
      >&2 echo "  ${patch_base}"
    else
      # AFAIK/2024-09-25: Should be unreachable [now] (fcn. only called on apply).
      >&2 echo "GAFFE: Unreachable path (choose_patch_base_or_ask_user)"
    fi

    exit_1
  fi

  return 0
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

suss_which_known_branch_is_furthest_along () {
  local patch_base="$1"

  # MAYBE/2022-12-11: Would we ever not want to do this?
  # - Because offline, or because these are "slow"?
  if git_remote_branch_exists "${REMOTE_BRANCH_SCOPING}"; then
    git_fetch_with_backoff "${SCOPING_REMOTE_NAME}"
  fi
  if git_remote_branch_exists "${REMOTE_BRANCH_RELEASE}"; then
    git_fetch_with_backoff "${RELEASE_REMOTE_NAME}"
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
    git_fetch_with_backoff "${upstream_remote}"
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

    ! git_is_empty_tree "${gitref}" || continue

    num_commits="$(git_number_of_commits "${gitref}" 2> /dev/null)"

    if [ -z "${num_commits}" ] || [ ${num_commits} -eq 0 ]; then

      continue
    fi

    echo "${num_commits} ${gitref}"
  done | sort -n -s -r)"

  if [ -n "${branch_counts}" ]; then
    debug "- Branch counts:\n$(echo "${branch_counts}" | sed 's/^/  /')"
  else
    debug "- No known branches found"
  fi

  furthest_along="$(echo "${branch_counts}" | head -1 | awk '{ print $2 }')"
}

print_prompt_user_explainer_using_starting_sha_tag () {
  local pw_ontime_tag_name="$1"
  local patch_base="$2"

  if git_is_empty_tree "${patch_base}"; then

    return 0
  fi

  echo "- If you want to specify a different revision,"
  echo "  cancel this prompt (Ctrl-c), and set a tag:"
  echo
  echo "    cd \"$(pwd -L)\""
  echo "    git tag ${pw_ontime_tag_name} <gitref>"
  echo
}

prompt_user_to_verify_patching_sha_extrazealous () {
  local describe_patch="$1"
  local patch_base="$2"
  local patch_base_raw="$3"
  local pw_ontime_tag_name="$4"

  echo
  echo "*** Please verify the patch commit — we'll insert patches here"
  echo
  echo "${describe_patch}:"
  echo
  echo "    ${patch_base} (${patch_base_raw})"
  echo
  print_prompt_user_explainer_using_starting_sha_tag \
    "${pw_ontime_tag_name}" "${patch_base}"

  local opt_chosen="y"
  if ${PW_OPTION_QUICK_TIG:-false} && ! git_is_empty_tree "${patch_base}"; then
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

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
  >&2 echo "😶"
fi

