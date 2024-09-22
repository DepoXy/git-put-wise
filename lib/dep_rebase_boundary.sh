#!/usr/bin/env bash
# vim:rdt=19999:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2024 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Determines rebase ref. commit, and identifies one or more push remotes.
#
# The rebase ref. (née sort-from-commit; also called the "rebase boundary"):
# - The rebase ref. is the youngest published commit, i.e., we can rebase
#   commits since this ref. and not worry about rewriting public history.
# - In the most basic use case where there's a single remote, the rebase
#   ref. is the remote HEAD.
#   - If you have a local 'release' (or 'private') branch, and the remote
#     branch REMOTE_BRANCH_RELEASE exists (e.g., 'publish/release'), uses
#       rebase_boundary='publish/release'
#   - For a feature branch (any branch not named 'release' or 'private'),
#     uses the remote name from the tracking branch, or from the --remote
#     CLI arg, paired with the feature branch name, e.g.,
#       rebase_boundary='<remote>/<branch>'
# - If there's no remote release or feature branch, uses the remote scoping
#   branch if it exists (which is where git put-wise push pushes protected
#   commits). The remote scoping branch varies:
#   - For a local 'release' or 'private' branch, uses REMOTE_BRANCH_SCOPING
#     (e.g., 'entrust/scoping').
#   - For a local feature branch, uses SCOPING_REMOTE_NAME/<branch>
#     (e.g., 'entrust/feature').
# - If no remote branch found at all, uses the pw/<branch>/in tag if set
#   (e.g., 'pw/private/in', 'pw/feature/in', etc.). This tag is used by the
#   put-wise-apply command and marks the latest commit from the patches
#   archive (which lets you move changes between hosts using an encrypted
#   patch archive, useful when you cannot use SSH to git-fetch and still
#   you want your data E2E encrypted between hosts).
#   - Note this is somewhat off-label usage for the pw/in tag, but w/e.
# - If still no reference found, falls back to latest version tag, if
#   found.
#
# Be aware the suss fails if a version or other tag is amongst the rebase commits.
# - LATER/2024-08-30: Tho subject to change, after we see how it works in practice.
#
# In addition to the rebase boundary, the function also identifies the
# push remotes.
# - These are the remotes described above that are probed when determining
#   the rebase boundary, e.g.,:
#     'publish/release' or 'publish/feature' (remote release or feature branch)
#     'entrust/scoping' or 'entrust/feature' (remote scoping branch)
# - If a remote branch exists, it'll be included.
# - If a remote is reachable, but the remote branch cannot be fetched,
#   it'll be included — this lets the user use `put-wise push` to make
#   their first push.
#   - If the remote branch cannot be fetched, the remote is pruned,
#     in case the branch was recently deleted, so that any obsolete
#     local ref is discarded.
# - If a remote is not defined, or if it cannot be reached and there's
#   no local ref to the remote branch, the remote branch is excluded.
#
# If no rebase boundary is identified, the function checks to see if
# *all* commits are already sorted & signed (sorted so that 'protected'
# and 'private' commits are bubbled-up, and signed if signing enabled).
# - If commits are not sorted or signed as expected, it'll print an
#   exhaustive list of actions the user can take to make the command
#   work (and there are lots of options!).
# - Otherwise the function returns truthy with rebase_boundary set
#   to the empty string, which tells the caller exactly what we told
#   you here.

# USER CONTROLS:
# - Set PW_OPTION_SKIP_REBASE=true (--skip-rebase) to probe the remote
#   branches, and to ignore rebase_boundary (sets it to empty string).
# - Set PW_OPTION_STARTING_REF=<REF> (-S | --starting-ref) to pick
#   your own rebase boundary.
#   - Use special ref named "ROOT" to rebase all commits.
# - Set other environs to change the convention branch and remote names:
#     LOCAL_BRANCH_PRIVATE
#     LOCAL_BRANCH_RELEASE
#     SCOPING_REMOTE_NAME, SCOPING_REMOTE_BRANCH
#     RELEASE_REMOTE_NAME, RELEASE_REMOTE_BRANCH
#   - Set PW_OPTION_REMOTE=<REMOTE> (-r | --remote) to specify the feature
#     branch remote.
# - If PW_OPTION_FORCE_PUSH=true (-f | --force, tells put-wise to
#   force-push), sets local_release="" and remote_release="" so that
#   the caller will ignore the release branches (and not force-push
#   to remote release branch).
# - Set PW_OPTION_ORPHAN_TAGS=true (--orphan-tags) to not exit nonzero
#   if tags found within the rebase area.
# - Use PW_ACTION_REBASE_BOUNDARY=true (--rebase-boundary) to call
#   this function from the command line, and to print its results.

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
#     verified and not all commits are sorted & signed.
#
# BWARE:
# - This fcn. does not verify rebase_boundary is reachable from HEAD.
#   - The caller is expected to call resort_and_sign_commits_since_boundary,
#     or to call must_confirm_shares_history_with_head directly, which
#     will `exit 1` (exit_1) if rebase_boundary ahead or divergent.

put_wise_identify_rebase_boundary_and_remotes () {
  local action_desc="$1"
  # This fcn. will exit if the boundary cannot be identified and the
  # commits are not sorted & signed, or will return nonzero instead
  # if this option is enabled.
  # - Note that put-wise doesn't use this option, but another project
  #   does: git-bump-version-tag.
  local inhibit_exit_if_unidentified="${2:-false}"
  local skip_integrity_checks="${3:-false}"
  local normalize_committer="${4:-false}"

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
  already_normed=false

  local sortless_msg=""

  # E.g., pw/release/in
  local applied_tag="$(format_pw_tag_applied "${branch_name}")"

  # true if branch_name is 'release' or 'private'.
  local is_hyper_branch
  is_hyper_branch="$(print_is_hyper_branch "${branch_name}")"

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

  local scoping_remote_ref

  if scoping_remote_ref="$( \
    fetch_and_check_branch_exists_or_remote_online \
      "${SCOPING_REMOTE_NAME}" \
      "${scoping_branch}" \
  )"; then
    remote_protected="${SCOPING_REMOTE_NAME}/${scoping_branch}"
    # Prefer pw/in over scoping boundary
    # - Ref is empty string if remote exists but not branch (before first push).
    if [ -z "${rebase_boundary}" ] && [ -n "${remote_ref}" ]; then
      rebase_boundary="${scoping_remote_ref}"
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

    if git_remote_branch_exists "${remote_release}"; then
      # Fail now if remote 'release' not at or behind local 'release'.
      if ! must_confirm_commit_at_or_behind_commit \
        "${remote_release}" "${local_release}" ${divergent_ok} \
        "remote-release" "local-release" \
      ; then
        if ! ${PW_OPTION_FORCE_PUSH:-false}; then

          return 1
        elif [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ]; then
          # Force-pushing, so don't use publish/release as boundary
          # (because if user force-pushing, likely diverged).
          if [ -n "${scoping_remote_ref}" ] \
            && git merge-base --is-ancestor "${scoping_remote_ref}" "${branch_name}" \
          ; then
            rebase_boundary="${scoping_remote_ref}"
          elif git_tag_exists "${applied_tag}"; then
            rebase_boundary="${applied_tag}"
          else
            # Fallback latest version tag (see below).
            rebase_boundary=""
          fi
        fi
      fi
    fi

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

  # On force-push branch, don't include remote 'release' branch when
  # pushing from 'private'; and don't include 'scoping' when pushing
  # from 'release'. This is so user only force-pushes one remote at a
  # time.
  if ${PW_OPTION_FORCE_PUSH:-false}; then
    if [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ]; then
      remote_protected=""
    else
      # When force-pushing scoping or feature branch, ignore 'release'.
      local_release=""
      remote_release=""

      if [ "${branch_name}" != "${LOCAL_BRANCH_PRIVATE}" ]; then
        # When force-pushing feature branch, ignore 'scoping'.
        remote_protected=""
      fi
    fi
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
    # Note that `git branch -u foo/bar` sets two config values:
    #   [branch "feature"]
    #     remote = foo
    #     merge = refs/heads/bar
    # - REFER: man git-config:
    #     branch.<name>.merge
    #     branch.<name>.remote -> remote.pushDefault -> branch.<name>.pushRemote
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
      # Might be empty string if remote exists but not branch.
      # - And unsets rebase boundary if so, which forces sort & sign to
      #   verify all commits, which seems like it makes sense for the
      #   inaugural push.
      #
      # On force-push, use tracking branch as rebase boundary.
      # - This supports workflow where tracking branch is immutable canon,
      #   but remote_current is liminal feature branch, and user doesn't
      #   care about feature branch history since diverged from tracking.
      # - Note that scoped commits likely ahead of remote_current.
      #   - The rebase_boundary really only to resign commits.
      # - Note also won't change commits before remote_current unless
      #   user changed them since previous remote_current push.
      if ! ${PW_OPTION_FORCE_PUSH:-false} || [ -z "${rebase_boundary}" ]; then
        rebase_boundary="${remote_ref}"
      fi
    fi
  fi

  # ***

  # Fallback latest version tag.
  if [ -z "${rebase_boundary}" ]; then
    rebase_boundary="$(git_most_recent_version_tag)"

    if [ -n "${rebase_boundary}" ]; then
      rebase_boundary="refs/tags/${rebase_boundary}"
    fi
  fi

  # ***

  if ${PW_OPTION_SKIP_REBASE:-false}; then
    rebase_boundary=""
  else
    local enable_gpg_sign="$(print_is_gpg_sign_enabled)"

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
      # Side-effect: Sets bools: already_sorted, already_signed, already_normed
      if is_already_sorted_and_signed \
        "${rebase_boundary}" \
        "${enable_gpg_sign}" \
        "${_until_ref:-HEAD}" \
        "${normalize_committer}" \
          > /dev/null \
      ; then
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

        return 1
      fi
    fi

    if ${skip_integrity_checks:-false}; then

      return 0
    fi

    if ! rebase_boundary="$( \
      insist_rebase_range_free_from_canonicals \
        "${rebase_boundary}" \
        "${enable_gpg_sign}" \
        "${normalize_committer}"
    )"; then

      return 1
    fi

    debug_alert_if_ref_tags_after_rebase_boundary \
      "${branch_name}" "${rebase_boundary}" "${applied_tag}"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

print_is_hyper_branch () {
  local branch_name="$1"

  local is_hyper_branch=false
  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ] \
    || [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ] \
  ; then
    is_hyper_branch=true
  fi

  printf "%s" "${is_hyper_branch}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

fetch_and_check_branch_exists_or_remote_online () {
  local remote_name="$1"
  local branch_name="$2"

  local upstream="${remote_name}/${branch_name}"

  if ! git_remote_exists "${remote_name}"; then

    return 1
  fi

  # Fetch the remote, so that our remote branch ref is current, though
  # respect user back-off to be less irritating and run quicker.
  if is_git_fetch_backoff_expired "${remote_name}" "${branch_name}"; then
    >&2 echo_announce "Fetch from ‘${remote_name}’" -n

    if ! git_fetch_with_backoff "${remote_name}" "${branch_name}"; then
      >&2 echo " ...failed!"
      if git ls-remote ${remote_name} -q 2> /dev/null; then
        >&2 echo "- Remote exists but not the branch: ‘${upstream}’"
        # If case remote branch was deleted, remove local ref.
        git fetch -q --prune "${remote_name}"

        return 0
      else
        >&2 echo "- Remote unreachable"
        # We'll still check the branch to see if previously fetched.
        # MAYBE: Might still want to fail because ref. might be stale.
      fi
    else
      >&2 echo
      # Fetched the branch specifically (so final check is a formality).
    fi
  fi

  if git_remote_branch_exists "${upstream}"; then
    printf "%s" "${upstream}"

    return 0
  else
    # No branch, and remote not reachable or fetch backoff in effect.

    return 1
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

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

insist_rebase_range_free_from_canonicals () {
  local rebase_boundary="$1"
  local enable_gpg_sign="$2"
  local normalize_committer="${3:-false}"

  local failed_checks=false

  if ! rebase_boundary="$( \
    insist_nothing_tagged_after "${rebase_boundary}" "${enable_gpg_sign}" "${normalize_committer}"
  )"; then
    failed_checks=true
  fi

  if ! rebase_boundary="$( \
    insist_single_author_used_since "${rebase_boundary}" "${enable_gpg_sign}" "${normalize_committer}"
  )"; then
    failed_checks=true
  fi

  printf "%s" "${rebase_boundary}"

  ! ${failed_checks} || return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PW_OPTION_ORPHAN_TAGS="${PW_OPTION_ORPHAN_TAGS:-false}"

insist_nothing_tagged_after () {
  local rebase_boundary="$1"
  local enable_gpg_sign="$2"
  local normalize_committer="${3:-false}"

  local exclusive_boundary="${rebase_boundary}"

  local failed_checks=false

  # ISOFF/2024-08-30: Should be okay to check all commits.
  #
  #   if [ -z "${rebase_boundary}" ]; then
  #     printf "%s" "${exclusive_boundary}"
  #
  #     return 0
  #   fi

  local gitref="${rebase_boundary}"
  if [ "${gitref}" = "${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}" ]; then
    gitref=""
  fi

  local recent_ver
  recent_ver="$(git_most_recent_version_tag "${gitref}")"

  local recent_tag
  recent_tag="$(git_most_recent_tag "${gitref}")"

  if [ -n "${recent_ver}" ] \
    || [ -n "${recent_tag}" ] \
  ; then
    local msg_fiver="ERROR"
    if ${PW_OPTION_ORPHAN_TAGS:-false}; then
      msg_fiver="ALERT"
    fi

    # ***

    # Check if sorted/signed from rebase_boundary to
    # the tag, and allow if that's the case.
    local tags_will_not_be_orphaned=false

    local newer_tag="${recent_ver}"
    if [ -n "${recent_tag}" ]; then
      if [ -z "${recent_ver}" ] \
        || git merge-base --is-ancestor "refs/tags/${recent_ver}" "refs/tags/${recent_tag}" \
      ; then
        newer_tag="${recent_tag}"
      fi
    fi

    if is_range_sorted_and_signed_and_nothing_scoped_follows \
      "${rebase_boundary}" "${enable_gpg_sign}" "${newer_tag}" "${normalize_committer}" \
    ; then
      tags_will_not_be_orphaned=true

      exclusive_boundary="${newer_tag}"

      msg_fiver="ALERT"
    fi

    # ***

    local log="echo"
    ! ${tags_will_not_be_orphaned} || log="info"

    >&2 ${log} "${msg_fiver}: Tag(s) found within rebase range"
    >&2 ${log} "- Latest tag: ${newer_tag}"
    >&2 ${log} "- Rebase boundary: ${rebase_boundary:-${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}}"

    if ${tags_will_not_be_orphaned}; then
      >&2 ${log} "- But it's okay — the related commit(s) will be untouched on rebase"
    else
      if ${PW_OPTION_ORPHAN_TAGS:-false}; then
        >&2 ${log} "- USAGE: Set PW_OPTION_ORPHAN_TAGS=false (--no-orphan-tags) to fail on this check"
      else
        >&2 ${log} "- USAGE: Set PW_OPTION_ORPHAN_TAGS=true (--orphan-tags) to disable this check"

        failed_checks=true
      fi
    fi
  fi

  printf "%s" "${exclusive_boundary}"

  ! ${failed_checks} || return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Verify contiguous author used since rebase boundary.
#
# - In case user hasn't been consistent with their name, use only email,
#   excluding name, to identify author, e.g.,
#
#     git log -n 1 --perl-regexp --author='^(?!(.*<user@dom>)).*$'
#
#   Vs.
#
#     git log -n 1 --perl-regexp --author='^(?!(User Name <user@dom>)).*$'
#
# - REFER/2024-08-29 01:26: man git-log:
#   --author=<pattern>, --committer=<pattern>
#     Limit the commits output to ones with author/committer header lines
#     that match the specified pattern (regular expression). With more than
#     one --author=<pattern>, commits whose author matches any of the given
#     patterns are chosen (similarly for multiple --committer=<pattern>).
#   - For the ?! negative lookahead:
#     -P, --perl-regexp
#       Consider the limiting patterns to be Perl-compatible regular
#       expressions. Support for these types of regular expressions is
#       an optional compile-time dependency. If Git wasn’t compiled with
#       support for them providing this option will cause it to die.
#
# - Multiple authors:
#
#     --author='^(?!(author1|author2)).*$'
#
# - Not really sure why .* needed but it is.

insist_single_author_used_since () {
  local rebase_boundary="$1"
  local enable_gpg_sign="$2"
  local normalize_committer="${3:-false}"

  local exclusive_boundary="${rebase_boundary}"

  local failed_checks=false

  local latest_author_email
  latest_author_email="$(git log -1 --format=%ae)"

  local author_pattern
  if [ -z "${PW_OPTION_AUTHOR_PATTERN}" ]; then
    author_pattern=".*<${latest_author_email}>"
  else
    author_pattern="${PW_OPTION_AUTHOR_PATTERN}"
  fi

  local latest_other_commit
  latest_other_commit="$( \
    git log -n 1 --format="%H" --perl-regexp --author="^(?!(${author_pattern})).*\$"
  )"

  # If no latest commit, indicates same author throughout # Mono-authorship

  if [ -n "${latest_other_commit}" ] \
    && ( [ -z "${rebase_boundary}" ] \
      || [ "${rebase_boundary}" = "${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}" ] \
      || ! git merge-base --is-ancestor "${latest_other_commit}" "${rebase_boundary}"
  ); then
    local msg_fiver="ERROR"
    if ${PW_OPTION_IGNORE_AUTHOR:-false}; then
      msg_fiver="ALERT"
    fi

    # ***

    # Check if sorted/signed from rebase_boundary to
    # the author commit, and allow if that's the case.
    local commits_will_not_be_changed=false

    if is_range_sorted_and_signed_and_nothing_scoped_follows \
      "${rebase_boundary}" "${enable_gpg_sign}" "${latest_other_commit}" "${normalize_committer}" \
    ; then
      commits_will_not_be_changed=true

      exclusive_boundary="${latest_other_commit}"

      msg_fiver="ALERT"
    fi

    # ***

    >&2 echo "${msg_fiver}: Commits found within rebase range from other author(s)"
    >&2 echo "- Latest author email: ${latest_author_email}"
    >&2 echo "- Latest other commit: ${latest_other_commit}"
    >&2 echo "- Other commit email: $(git log -1 --format=%ae ${latest_other_commit})"
    >&2 echo "- Rebase boundary: ${rebase_boundary:-${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}}"

    if ${commits_will_not_be_changed}; then
      >&2 echo "- But it's okay — the related commit(s) will be untouched on rebase"
    else
      >&2 echo "- USAGE: Set PW_OPTION_AUTHOR_PATTERN=\".*<name@dom>|.*<user@tld>|...\" to ignore authors"
      if ${PW_OPTION_IGNORE_AUTHOR:-false}; then
        >&2 echo "- ALTLY: Set PW_OPTION_IGNORE_AUTHOR=false (--no-ignore-author) to fail on this check"
      else
        >&2 echo "- ALTLY: Set PW_OPTION_IGNORE_AUTHOR=true (--ignore-author) to disable this check"

        failed_checks=true
      fi
    fi
  fi

  printf "%s" "${exclusive_boundary}"

  ! ${failed_checks} || return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# If something canonical found after the rebase boundary, such as
# a version tag, check if the rebase range until then is already
# sorted & signed, so we can just move the boundary forward.
#
# Also checks if rev range ends with 1+ scoped commits, and if any
# later commits are not scoped, or lesser scope, because than the
# rev range is technically not sorted. (And doesn't seem worth it
# to check commits after are equal or greater scope, though really
# that would make this check less exclusive. E.g., if the
# rebase_boundary commit is PROTECTED, than it'd be okay if only
# PRIVATE commits followed. But seems like busy work to implement.)

is_range_sorted_and_signed_and_nothing_scoped_follows () {
  local rebase_boundary="$1"
  local enable_gpg_sign="$2"
  local until_ref="$3"
  local normalize_committer="${4:-false}"

  # Side-effect: Sets bools: already_sorted, already_signed, already_normed
  if is_already_sorted_and_signed \
    "${rebase_boundary}" "${enable_gpg_sign}" "${until_ref}" "${normalize_committer}" \
    > /dev/null \
  ; then
    local scoping_boundary_or_HEAD
    scoping_boundary_or_HEAD="$( \
      identify_scope_ends_at "^${SCOPING_PREFIX}" "^${PRIVATE_PREFIX}" \
    )"

    if git merge-base --is-ancestor "${until_ref}" "${scoping_boundary_or_HEAD}" \
    ; then

      return 0
    fi
  fi

  return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Overzealous UX reporting if diverging from tags, not sure why I care
# to alert user.

debug_alert_if_ref_tags_after_rebase_boundary () {
  local branch_name="$1"
  local rebase_boundary="$2"
  local applied_tag="$3"

  if [ -z "${rebase_boundary}" ]; then

    return 0
  fi

  local arch_tag="$(format_pw_tag_archived "${branch_name}")"

  local work_tag="$(format_pw_tag_starting "${branch_name}")"

  >&2 debug "Checking tags: ${applied_tag}, ${arch_tag}, ${work_tag}"

  for tag_name in \
    "${applied_tag}" \
    "${arch_tag}" \
    "${work_tag}" \
  ; do
    if ! git_tag_exists "${tag_name}"; then

      continue
    fi

    if $(must_confirm_shares_history_with_head "${tag_name}" > /dev/null 2>&1); then
      local divergent_ok=false

      if ! $( \
        must_confirm_commit_at_or_behind_commit \
          "${tag_name}" "${rebase_boundary}" ${divergent_ok} \
          "tag-name" "sort-from" \
            > /dev/null 2>&1 \
      ); then
        >&2 debug "- FYI: '${tag_name}' tag moving to headless sequence" \
          "until reused by future put-wise"
      fi
    fi
  done
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

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
  >&2 echo "    PW_OPTION_SKIP_REBASE=true ${prog_name} ..."
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

