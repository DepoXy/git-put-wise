#!/usr/bin/env bash
# vim:rdt=19999:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2024 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Determines rebase ref. commit, and identifies one or more push remotes.
#
# - The rebase ref. is the youngest published commit, i.e., we can rebase
#   commits since this ref. and not worry about rewriting public history.
# - In the most basic use case where there's a single remote, the rebase
#   ref. is the remote HEAD.
#   - If you have a local 'release' (or 'private') branch, and the remote
#     branch REMOTE_BRANCH_RELEASE exists (e.g., 'publish/release'), sets
#       rebase_boundary='publish/release'
#   - For a feature branch (any branch not named 'release' or 'private'),
#     uses the remote name from the tracking branch, or from the --remote
#     CLI arg, paired with the feature branch name, e.g.,
#       rebase_boundary='<remote>/<branch>'
# - For a 'private' branch with no remote, uses the pw/private/in tag if
#   set, which is used by the put-wise-apply command and marks the latest
#   commit from the patches archive (which lets you move changes between
#   hosts using an encrypted patch archive, useful when you cannot use SSH
#   to git-fetch and still you want your data E2E encrypted between hosts).
# - May also baulk if a version or other tag is identified amongst the
#   rebase commits.
#
# - Also used by put-wise-push to suss other remote and branch vars.

# SORRY:
# - I don't generally like to "abuse" `local` like this. It seems
#   like a weird side-effect to have a fcn. set its caller's vars.
#   - But this is shell script, and passing data is not always so
#     simple or elegant.
#
# REFER:
# - This fcn. sets the following vars (its "return" values):
#     local_release=""
#     remote_release=""
#     remote_protected=""
#     remote_current=""
#     remote_name=""
#     branch_name=""
#     rebase_boundary=""
# - Other side effects:
#   - Calls `git fetch` as appropriate to ensure remote branch
#     ref is accurate/up to date.
#   - Fails if bad state detected (e.g., diverged branches), or if
#     the rebase boundary (rebase_boundary) cannot be identified or
#     verified.
#
# BWARE:
# - This fcn. does not verify rebase_boundary is reachable from HEAD.
#   - See resort_and_sign_commits_before_push, which will `exit 1` if
#     rebase_boundary diverges,

put_wise_identify_rebase_boundary_and_remotes () {
  local action_desc="$1"
  # This fcn. will exit if the boundary cannot be identified and the
  # commits are not sorted & signed, or will return nonzero instead
  # if this option is enabled.
  # - Note that put-wise doesn't use this option, but another project
  #   does: git-bump-version-tag.
  local inhibit_exit_if_unidentified="${2:-false}"

  # Caller vars set below:
  branch_name="$(git_branch_name)"
  local_release=""
  remote_release=""
  remote_protected=""
  remote_current=""
  remote_name=""
  # The `git rebase` gitref, prev. called sort_from_commit.
  rebase_boundary=""
  # These are only set if no rebase_boundary identified, and
  # *all* commits scanned as fallback.
  already_sorted=false
  already_signed=false

  local sortless_msg=""

  local applied_tag="$(format_pw_tag_applied "${branch_name}")"

  local is_hyper_branch=false
  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ] \
    || [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ] \
  ; then
    is_hyper_branch=true
  fi

  local remote_ref=""

  # ***

  # The pw/in tag signifies the final patch from the latest --apply command.
  # It's the remote's HEAD, essentially (minus PRIVATE commits). This is the
  # fallback sort-from, in case there's no remote branch or local 'release'
  # branch. Note that this will move PRIVATE commits toward HEAD, but it'll
  # leave behind PROTECTED commits that may precede pw/work. (The pw/work tag
  # is the merge-base from the latest --apply command. It's what the patches
  # were based from, and it signifies what this host pushed before that the
  # remote added work to. I.e., when this host pushed pw/work, it had just
  # resorted, and PROTECTED commits were bubbled toward pw/work. So if we
  # wanted to move those commits forward now, we'd have to set sort-from to a
  # commit preceding pw/work. Fortunately, we can use the 'release' branch,
  # which precedes these PROTECTED commits, as the sort-from base. Using this
  # tag is just a fallback, but note that it means we won't move earlier
  # PROTECTED commits forward. Which we can say is a feature of not having a
  # 'release' branch.
  if git_tag_exists "${applied_tag}"; then
    rebase_boundary="${applied_tag}"
  fi

  # ***

  # Unless the 'pw/private/in' tag is set as the rebase_boundary default
  # (see above), use the protected remote (e.g., 'entrust/scoping') as the
  # default starting point for the sort-and-sign rebase (rebase_boundary).
  # - We'll pick a different starting point below if there's a remote
  #   release branch (e.g., 'publish/release') or if there's a local
  #   release branch (e.g., 'release'), which is the "normal" use case:
  #   - UCASE: Keep scoped (PROTECTED/PRIVATE) commits *ahead* of the
  #     'release' branches (so that you never publish scoped commits).
  #     - This is actually a core concept in put-wise: locally you have
  #       scoped commits that you never publish to the release remote.
  #       - PRIVATE commits are never pushed/pulled by put-wise (though
  #         you might sync them between personal hosts using SSH remotes
  #         and git-fetch).
  #       - PROTECTED commits are only shared via --archive or via
  #         --push to a protected remote (e.g., a private GH repo).
  # - Here we use the protected remote ('entrust/scoping') as the
  #   default in case there's no 'release' branch (local or remote).
  # - Note if this is the only rebase boundary identified, the scoped
  #   sort will not include PROTECTED commits that were previously
  #   pushed to the protected remote. Which is fine. User can manually
  #   sort-by-scope to bubble them up, if they care (and note that the
  #   protected remote does not guarantee linear history, and user may
  #   need to force-push if they bubble up previously pushed PROTECTED
  #   commits).

  # If hyper branch, use conventional name, e.g., 'entrust/scoping'
  local scoping_branch="${SCOPING_REMOTE_BRANCH}"
  # If feature branch, use current branch name, e.g., 'entrust/<feature>'
  ${is_hyper_branch} || scoping_branch="${branch_name}"

  if remote_ref="$( \
    fetch_and_check_branch_exists_or_remote_online \
      "${SCOPING_REMOTE_NAME}" \
      "${scoping_branch}" \
  )"; then
    remote_protected="${SCOPING_REMOTE_NAME}/${scoping_branch}"
    # Prefer pw/in over scoping boundary
    # - Ref is empty string if remote exists but not branch (before first push).
    if [ -z "${rebase_boundary}" ] && [ -n "${remote_ref}" ]; then
      rebase_boundary="${remote_ref}"
    fi
  fi

  # ***

  # Prefer sorting from local or remote 'release' branch.
  # - Skip for feature branch unless local 'release' exists, to not waste
  #   time pinging it (or showing progress messages), because feature
  #   branch won't use it unless local 'release' branch exists.
  if ${is_hyper_branch} || git_branch_exists "${LOCAL_BRANCH_RELEASE}"; then
    if remote_ref="$( \
      fetch_and_check_branch_exists_or_remote_online \
        "${RELEASE_REMOTE_NAME}" \
        "${RELEASE_REMOTE_BRANCH}" \
    )"; then
      remote_release="${REMOTE_BRANCH_RELEASE}"
      # May be empty string if remote exists and remote branch absent (first push).
      # - Note this unsets rebase_boundary if remote release branch is absent.
      #   Otherwise the boundary is pw/private/in or entrust/scoping, meaning
      #   we might not bubble-up protected commits if they're not all sorted.
      #   So better error on side of caution and check all commits (or we'll
      #   set to local 'release' next if we find a local 'release' branch).
      if ${is_hyper_branch}; then
        rebase_boundary="${remote_ref}"
      fi
    fi
  fi

  if [ "${branch_name}" != "${LOCAL_BRANCH_RELEASE}" ]; then
    if git_branch_exists "${LOCAL_BRANCH_RELEASE}"; then
      local_release="${LOCAL_BRANCH_RELEASE}"
      rebase_boundary="${LOCAL_BRANCH_RELEASE}"
    fi
  elif [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ]; then
    local_release="${LOCAL_BRANCH_RELEASE}"
    if git_branch_exists "${LOCAL_BRANCH_PRIVATE}"; then
      warn "ALERT: Working from branch '${LOCAL_BRANCH_RELEASE}'," \
        "but '${LOCAL_BRANCH_PRIVATE}' branch also exists"
    fi
  fi

  if [ -n "${remote_release}" ] && [ -n "${local_release}" ]; then
    # Verify 'release/release' is at or behind 'release'.
    local divergent_ok=false

    # Exits on error.
    must_confirm_commit_at_or_behind_commit \
      "${remote_release}" "${local_release}" ${divergent_ok} \
      "remote-release" "local-release"

    if [ "${branch_name}" != "${local_release}" ]; then
      if git merge-base --is-ancestor "${local_release}" "${branch_name}"; then
        # Rebase starting from 'release', which is guaranteed at or further
        # along than 'publish/release'.
        rebase_boundary="${local_release}"
      elif ${is_hyper_branch}; then
        warn "ALERT: '${local_release}' not ancestor of '${branch_name}'"
      else
        # This is a feature branch, and there's no rule about 'release'
        # being an ancestor. It's merely a courteousy/convenience that
        # we support it.
        local_release=""
        remote_release=""
      fi
    fi
  elif ! ${is_hyper_branch}; then
    # On push feature branch, 'release' only pushed to remote 'release',
    # so if both don't exist nothing to do.
    local_release=""
    remote_release=""
  fi

  # On force-push branch, don't include remote 'release' branch.
  # ALTLY: We could allow force-push from 'private' branch, e.g.,
  #   if ${PW_OPTION_FORCE_PUSH:-false} && ! ${is_hyper_branch}; ...
  # - But this should be a rare event, so require user to use
  #   local 'release' branch to force-push to remote 'release'.
  if ${PW_OPTION_FORCE_PUSH:-false} \
    && [ "${branch_name}" != "${LOCAL_BRANCH_RELEASE}" ] \
  ; then
    local_release=""
    remote_release=""
  fi

  # NOTE: If rebase_boundary is 'release' or 'publish/release', it might
  #       mean user needs to `push --force` 'entrust/scoping', and then
  #       on another host, they'll need to rebase on pull. Just how it
  #       works when working with scoped commits.

  # ***

  if ! ${is_hyper_branch}; then
    # ${branch_name} not 'release' or 'private'.
    # - Note that push.default defaults to 'simple', which pushes to upstream
    #   tracking branch when pushing to that remote. This code works like
    #   push.default 'current', which uses same name for pushing.
    #   - For feature branches, I like to track the trunk, so git-pull
    #     rebases appropriately. But I like push.default 'current', so
    #     that push uses the same feature branch name that I use locally.
    # - The following effectively mimics 'current'.
    local tracking_branch
    tracking_branch="$(git_tracking_branch)" \
      || true

    # Honor PW_OPTION_REMOTE, but not PW_OPTION_BRANCH (use branch_name).
    remote_name="${PW_OPTION_REMOTE}"

    if [ -z "${remote_name}" ] && [ -n "${tracking_branch}" ]; then
      remote_name="$(git_upstream_parse_remote_name "${tracking_branch}")"
    fi

    if [ -z "${remote_name}" ]; then
      remote_name="${RELEASE_REMOTE_NAME}"
    fi

    # For feature branch, rebase boundary may have been set above:
    # - ✓ Defaults pw/<branch>/in tag, if exists
    # - ✓ Changes to 'entrust/<branch>' if found
    # - ✗ Ignores 'publish/release' for feature branches
    # - ✓ Finally prefers local 'release' branch if found
    # Here we override with tracking branch or same-named counterpart.

    # Prefer tracking branch rebase boundary to any previous choice.
    # - Use case: Create a new feature branch and set its upstream
    #   tracking branch to the mainline, but haven't created/pushed
    #   to remote feature branch yet.
    if [ -n "${tracking_branch}" ]; then
      rebase_boundary="${tracking_branch}"
    fi

    if remote_ref="$( \
      fetch_and_check_branch_exists_or_remote_online \
        "${remote_name}" \
        "${branch_name}" \
    )"; then
      # Note we don't use PW_OPTION_BRANCH here, but the current branch.
      remote_current="${remote_name}/${branch_name}"
      # Might be empty string if remove exists but not branch.
      rebase_boundary="${remote_ref}"
    fi
  fi

  # ***

  # Fallback latest version tag.
  if [ -z "${rebase_boundary}" ]; then
    rebase_boundary="$(git_most_recent_version_tag)"
  fi

  # ***

  if ${PUT_WISE_SKIP_REBASE:-false}; then
    rebase_boundary=""
  else
    if [ -n "${PW_OPTION_STARTING_REF}" ]; then
      if [ -z "${rebase_boundary}" ]; then
        rebase_boundary="(none identified)"
      fi
      >&2 echo "ALERT: Setting rebase boundary from command line value."
      >&2 echo "- Ignoring identified boundary: ${rebase_boundary}"
      >&2 echo "- Overriding with user cmd arg: ${PW_OPTION_STARTING_REF}"

      rebase_boundary="${PW_OPTION_STARTING_REF}"
    fi

    # If no rebase boundary was identified, check if *all* commits already
    # sorted & signed. If not, while we *could* rebase all commits, it's
    # also a ripe opportunity to print an instructive "error" message that
    # tells user how to proceed (with easiest option being to use ROOT ref).
    if ! verify_rebase_boundary_exists "${rebase_boundary}"; then
      # Use empty rebase_boundary so already-sorted checks all commits.
      rebase_boundary=""
      local enable_gpg_sign="$(print_is_gpg_sign_enabled)"
      # Side-effect: Fcn. sets already_sorted=true|false, already_signed=true|false
      if is_already_sorted_and_signed "${rebase_boundary}" "${enable_gpg_sign}" > /dev/null; then
        # Tells caller all commits are sorted and signed, and that
        # no rebase boundary was identified.
        rebase_boundary=""
      else
        # For third-party apps: Non-exit falsey return without alert message.
        ! ${inhibit_exit_if_unidentified:-false} || return 1

        alert_cannot_identify_rebase_boundary \
          "${branch_name}" \
          "${remote_name}" \
          "${rebase_boundary}"

        exit 1
      fi
    fi

    if ! insist_nothing_tagged_after "${rebase_boundary}"; then

      exit 1
    fi

    debug_alert_if_ref_tags_after_rebase_boundary \
      "${branch_name}" "${rebase_boundary}" "${applied_tag}"
  fi
}

# ***

# Overzealous UX reporting if diverging from tags, not sure why I care
# to alert user.

debug_alert_if_ref_tags_after_rebase_boundary () {
  local branch_name="$1"
  local rebase_boundary="$2"
  local applied_tag="$3"

  if [ -z "${rebase_boundary}" ]; then

    return 0
  fi

  local work_tag="$(format_pw_tag_starting "${branch_name}")"

  for tag_name in \
    "${applied_tag}" \
    "$(format_pw_tag_archived "${branch_name}")" \
    "${work_tag}" \
  ; do
    if $(must_confirm_shares_history_with_head "${tag_name}" > /dev/null 2>&1); then
      local divergent_ok=false

      if ! $( \
        must_confirm_commit_at_or_behind_commit \
          "${tag_name}" "${rebase_boundary}" ${divergent_ok} \
          "tag-name" "sort-from" \
            > /dev/null 2>&1 \
      ); then
        >&2 debug "FYI: '${tag_name}' tag moving to headless sequence" \
          "until reused by future put-wise"
      fi
    fi
  done
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

fetch_and_check_branch_exists_or_remote_online () {
  local remote_name="$1"
  local branch_name="$2"

  local upstream="${remote_name}/${branch_name}"

  if ! git_remote_exists "${remote_name}"; then

    return 1
  fi

  # Always fetch the remote, so that our ref is current,
  # because this function also does a lot of state validating.
  >&2 echo_announce "Fetch from ‘${remote_name}’" -n

  # git-fetch prints progress to stderr, which we ignore ('-q' also works).
  if ! git fetch "${remote_name}" \
    refs/heads/${branch_name} 2> /dev/null \
  ; then
    >&2 echo " ...failed!"
    if git ls-remote ${remote_name} -q 2> /dev/null; then
      >&2 echo "- Remote exists but not the branch: ‘${upstream}’"
      # If case remote branch was deleted, remove local ref.
      git fetch --prune "${remote_name}"

      return 0
    else
      >&2 echo "- Remote unreachable"
      # We'll still check the branch to see if previously fetched.
    fi
  else
    >&2 echo
    # Fetched the branch specifically (so final check is a formality).
  fi

  if git_remote_branch_exists "${upstream}"; then
    printf "%s" "${upstream}"

    return 0
  else

    return 1
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PW_OPTION_FORCE_ORPHAN_TAGS="${PW_OPTION_FORCE_ORPHAN_TAGS:-false}"

insist_nothing_tagged_after () {
  local rebase_boundary="$1"

  if [ -z "${rebase_boundary}" ]; then

    return 0
  fi

  local rev_list_commits
  rev_list_commits="$(print_git_rev_list_commits "${rebase_boundary}")"

  local child_of_rebase_boundary="$( \
    git rev-list ${rev_list_commits} | tail -n 1
  )"

  local version_tag
  version_tag="$(git_most_recent_version_tag "${child_of_rebase_boundary}")"

  local other_tag
  other_tag="$(git_most_recent_tag "${child_of_rebase_boundary}")"

  if [ -n "${version_tag}" ] \
    || [ -n "${other_tag}" ] \
  ; then
    local msg_fiver="ERROR"
    if ${PW_OPTION_FORCE_ORPHAN_TAGS:-false}; then
      msg_fiver="ALERT"
    fi

    >&2 echo "${msg_fiver}: Tag(s) found after sort-from reference"
    >&2 echo "- Ver. tag: ${version_tag}"
    >&2 echo "- Oth. tag: ${other_tag}"
    >&2 echo "- Target rebase ref: ${rebase_boundary}"

    if ${PW_OPTION_FORCE_ORPHAN_TAGS:-false}; then
      >&2 echo "- USAGE: Set PW_OPTION_FORCE_ORPHAN_TAGS=false to fail on this check"
    else
      >&2 echo "- USAGE: Set PW_OPTION_FORCE_ORPHAN_TAGS=true to disable this check"

      exit 1
    fi
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

verify_rebase_boundary_exists () {
  local rebase_boundary="$1"

  if [ -z "${rebase_boundary}" ]; then

    return 1
  fi

  if [ "${rebase_boundary}" = "${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}" ]; then

    return 0
  fi

  git_commit_object_name ${rebase_boundary} > /dev/null
}

# ***

alert_cannot_identify_rebase_boundary () {
  local branch_name="$1"
  local tracking_remote_name="$2"
  local rebase_boundary="$3"

  local is_gpw_itself=false
  if [ "$(basename -- "$0")" = "git-put-wise" ]; then
    is_gpw_itself=true
  fi

  local prog_name="$(basename -- "$0")"

  >&2 echo "ERROR: Could not identify the rebase boundary"
  >&2 echo
  >&2 echo "- A rebase boundary must be identified as the"
  >&2 echo "  starting point for the sort and sign rebase"
  >&2 echo
  >&2 echo "POSSIBLE SOLUTIONS:"
  >&2 echo
  >&2 echo "- OPTION 1: If you want to sign and sort all"
  >&2 echo "  commits, use the special \"ROOT\" ref, e.g.:"
  >&2 echo
  >&2 echo "    git put-wise push -S ROOT"
  >&2 echo
  >&2 echo "- OPTION 2: If you want to specify a one-time"
  >&2 echo "  rebase boundary:"
  >&2 echo "  - Use the environ option:"
  >&2 echo "      PW_OPTION_STARTING_REF=\"<ref>\""
  >&2 echo "    E.g.,"
  >&2 echo "      PW_OPTION_STARTING_REF=<REF> ${prog_name} ..."
  if ${is_gpw_itself}; then
    >&2 echo "  - Or use the command line option:"
    >&2 echo "      -S|--starting-ref <REF>"
    >&2 echo "    E.g.,"
    >&2 echo "      git put-wise --starting-ref <REF> ..."
  fi
  >&2 echo
  >&2 echo "- OPTION 3: If you want to skip the sort-and-sign"
  >&2 echo "  rebase altogether, set the environ:"
  >&2 echo "    PUT_WISE_SKIP_REBASE=true ${prog_name} ..."
  >&2 echo
  >&2 echo "- OPTION 4: If you want the rebase boundary identified"
  >&2 echo "  automatically, create one of the missing references:"
  >&2 echo "  - Use a version tag to mark the rebase boundary, e.g.,"
  >&2 echo "      git tag <version> <REF>"
  if [ "${branch_name}" != "${LOCAL_BRANCH_RELEASE}" ]; then
    >&2 echo "  - Create a local branch named '${LOCAL_BRANCH_RELEASE}',"
    >&2 echo "    e.g.,"
    >&2 echo "      git checkout -b ${LOCAL_BRANCH_RELEASE} <REF>"
  fi
  >&2 echo "  - Push to one of the known remote branches, e.g.,"
  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ] \
    || [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ] \
  ; then
    >&2 echo "      git push ${RELEASE_REMOTE_NAME} <REF>:refs/heads/${RELEASE_REMOTE_BRANCH}"
    >&2 echo "      git push ${SCOPING_REMOTE_NAME} <REF>:refs/heads/${SCOPING_REMOTE_BRANCH}"
  else
    >&2 echo "      git push ${tracking_remote_name} <REF>:refs/heads/${branch_name}"
    >&2 echo "    - The remote name is determined from the tracking branch, e.g.,"
    >&2 echo "        git branch -u <remote>/<branch>"
    if ${is_gpw_itself}; then
      >&2 echo "      Which you can override using the --remote CLI option,"
      >&2 echo "      or using the PW_OPTION_REMOTE environ."
    else
      >&2 echo "      Which you can override using the PW_OPTION_REMOTE environ."
    fi
  fi
  >&2 echo "  - Set a tag named '${applied_tag}'"
  >&2 echo "    - This tag is set by the git-put-wise-apply"
  >&2 echo "      command, but you can set it manually for"
  >&2 echo "      this purpose, e.g.,"
  >&2 echo "        git tag ${applied_tag} <REF>"
  >&2 echo "  Then please try your command again."
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
  >&2 echo "😶"
fi

