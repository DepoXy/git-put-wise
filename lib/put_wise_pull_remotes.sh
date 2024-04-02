#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

DRY_RUN=""
# DRY_RUN=__DRYRUN  # Uncomment to always dry-run, regardless -T|--dry-run.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# The user called us on a specific project, and not the transport repo,
# so we'll update just the current project's active branch.
put_wise_pull_remotes () {
  ${PW_OPTION_DRY_RUN} && DRY_RUN="${DRY_RUN:-__DRYRUN}"

  local before_cd="$(pwd -L)"

  # Side effect: `cd`'s, and updates PW_PROJECT_PATH, to canonicalize.
  must_cd_project_path_and_verify_repo

  must_not_be_patches_repo

  put_wise_pull_remotes_go

  cd "${before_cd}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# The pw/<branch>/out tag is created by --archive, and it represents
# published commits, albeit the commits in the --archive will have
# been published under different commit IDs. So if there's a pw/out
# tag and pull finds new commits, it means the --archive commits were
# remotely consumed, potentially changed, and then pushed. To consume
# those new commits locally, we reset to the upstream branch and
# cherry-pick to restore local revisions we know are *not* published.
# - But if there's no pw/out tag, if means there are no conflicting
#   revision we need to drop, and this can be treated like a normal
#   pull.
put_wise_pull_remotes_go () {
  local branch_name="$(git_branch_name)"

  # Look for pw/out tag.
  # - If found, there should be a logical equivalent commit in the latest
  #   upstream revisions, if those commits have come full pretzel.
  local pw_tag_archived
  pw_tag_archived="$(format_pw_tag_archived "${branch_name}")"

  local pick_from=""
  pick_from="$(git_tag_object_name "${pw_tag_archived}")" || true

  if [ -z "${pick_from}" ]; then
    put_wise_pull_unspecially "${branch_name}" "${pw_tag_archived}"
  else
    put_wise_pull_complicated "${branch_name}" "${pw_tag_archived}" "${pick_from}"
  fi
}

# ***

put_wise_pull_unspecially () {
  local branch_name="$1"
  local pw_tag_archived="$2"

  local tracking_upstream=""
  tracking_upstream="$(must_locate_tracking_upstream "${branch_name}")" || exit $?

  local upstream_remote
  local upstream_branch
  upstream_remote="$(git_upstream_parse_remote_name "${tracking_upstream}")"
  upstream_branch="$(git_upstream_parse_branch_name "${tracking_upstream}")"

  echo "Will rebase atop '${tracking_upstream}' (no '${pw_tag_archived}' tag)"
  echo "  Old HEAD is at:"
  echo "    ${branch_name} $(shorten_sha "$(git_commit_object_name)")"

  echo "  git pull --rebase --autostash \"${upstream_remote}\" \"${upstream_branch}\""

  local retcode=0

  git pull --rebase --autostash "${upstream_remote}" "${upstream_branch}" \
    || retcode=$?

  if [ ${retcode} -ne 0 ]; then
    # Set rebase-todo 'exec' to call optional user hook, GIT_POST_REBASE_EXEC.
    git_post_rebase_exec_inject

    badger_user_rebase_failed
  else
    # Call optional post-rebase user hook immediately.
    git_post_rebase_exec_run
  fi

  return ${retcode}
}

# ***

# We assume what we're pulling is canon, so we'll reset-hard to
# the upstream/HEAD. We'll then cherry-pick commits that we know
# are not upstream. This includes any revision after the latest
# pw/<branch>/out tag, which represents the latest --archive we
# sent to the remote, which is presumably what's being pulled.
put_wise_pull_complicated () {
  local branch_name="$1"
  local pw_tag_archived="$2"
  local pick_from="$3"

  # ***

  # Note that PROTECTED: commits will not be properly grouped on pull.
  # - If pulling from entrust/scoping, the leader (the other remote)
  #   manages PROTECTED: commits, so you may find PROTECTED: commits
  #   just before pw/in, and you may find newer PROTECTED: commits
  #   after pw/out. But we don't want to resort on pull, because we're
  #   just going to replace up (reset-hard) to pw/in.
  # - If pulling from publish/release (or any non-protected upstream),
  #   there may yet be PROTECTED: commits before pw/in that --archive
  #   sent to the remote, which the remote will have consumed and nested,
  #   and for which the follower will drop them on reset-hard (which is
  #   just how it works with PROTECTED: commits in a non-private branch).
  # - So pick-from will only precede the PRIVATE: commits; and
  #   it's pointless to care about the PROTECTED: commits at this point.
  # - Also note that checking the scoping boundary also implies -lte HEAD:
  #
  #     must_confirm_commit_at_or_behind_commit "${pick_from}" "HEAD"

  local protected_boundary_or_HEAD
  protected_boundary_or_HEAD="$(identify_scope_ends_at "^${PRIVATE_PREFIX}")"

  local divergent_ok=false
  must_confirm_commit_at_or_behind_commit \
    "${pick_from}" "${protected_boundary_or_HEAD}" \
    ${divergent_ok} \
    "${pw_tag_archived}" "private-scoping-boundary-or-HEAD"

  # ***

  local tracking_upstream=""
  tracking_upstream="$(must_locate_tracking_upstream "${branch_name}")" || exit $?
  local reset_ref="refs/remotes/${tracking_upstream}"

  local pop_after=false
  pop_after=$(maybe_stash_changes)

  local old_head="$(git_commit_object_name)"

  echo "Rebasing local changes atop:"
  echo "  ${tracking_upstream}"
  echo "picking local changes since:"
  echo "  ${pw_tag_archived}"
  echo "where the latest HEAD is at:"
  echo "  ${branch_name} $(shorten_sha "${old_head}")"

  # ***

  # Walk commits and find one that diffs empty against
  # pick_from, stopping at shared reset_ref commit.

  local merge_base=$(git merge-base "${reset_ref}" "HEAD")

  echo
  echo "Running multiple git-diff against local pick-from rev:"
  echo "  ${pw_tag_archived} ($(shorten_sha "${pick_from}"))"
  local rev_count=$(git rev-list --count ${merge_base}..${reset_ref})
  echo "Comparing against each rev between shared merge-base and remote reset-ref (${rev_count} total):"
  echo "  $(shorten_sha "${merge_base}")..${reset_ref}"
  echo "looking for the rev with the least number of additions and deletions:"

  local visitor="${reset_ref}"

  local least_diffy_cnt=-1
  local least_diffy_ref=""
  local visitation_cnt=0

  while [ -n "${visitor}" ] && [ "${visitor}" != "${merge_base}" ]; do
    let "visitation_cnt += 1"

    local tot_adds_dels=""
    tot_adds_dels="$( \
      git --no-pager diff ${pick_from}..${visitor} --numstat \
      | awk '{ total += $1 + $2 } END { print total }' \
    )"

    local rev_range="$(shorten_sha "${pick_from}")..$(shorten_sha "${visitor}")"
    local git_cmd_called="git --no-pager diff ${rev_range} --numstat"
    # COPYD: Next two printf calls identical except for '\n'
    printf "\r  Min: %4d / Cur: %4d / Rev: %d/%d / ${git_cmd_called}" \
      "${least_diffy_cnt}" "${tot_adds_dels:-0}" "${visitation_cnt}" "${rev_count}"

    if [ -z "${tot_adds_dels}" ]; then
      least_diffy_cnt=0
      least_diffy_ref="${visitor}"

      # Reprint same message but with new min (0) and a newline.
      printf "\r  Min: %4d / Cur: %4d / Rev: %d/%d / ${git_cmd_called}\n" \
        "${least_diffy_cnt}" "${tot_adds_dels:-0}" "${visitation_cnt}" "${rev_count}"

      # Double-check.
      if [ -n "$(git --no-pager diff ${pick_from}..${visitor})" ]; then
        # This would mean pipeline above is not WAD.
        >&2 echo "ERROR: You git-diff | awk pipeline doesn't work how you think."

        exit 1
      fi

      echo "Found it!"
      echo
      echo "- The local pick-from commit diffs empty against"
      echo "  the incoming upstream HEAD or an ancestor of it:"
      echo "  - Pick-from '${pw_tag_archived}' tag: $(shorten_sha ${pick_from})"
      echo "  - Reset-hard '${reset_ref}' ancestor:"
      echo "      ${visitor}"
      echo "  - You can see the emptiness yourself:"
      echo "      git --no-pager diff ${pw_tag_archived}..$(shorten_sha "${visitor}")"
      echo

      break
    elif [ ${least_diffy_cnt} -eq -1 ] \
      || [ ${tot_adds_dels} -lt ${least_diffy_cnt} ]; \
    then
      least_diffy_cnt=${tot_adds_dels}
      least_diffy_ref="${visitor}"
    fi
    visitor="$(git_parent_of "${visitor}")"
  done

  if [ ${least_diffy_cnt} -ne 0 ]; then
    echo "Unable to identify an empty diff!"
    echo
    echo "- The best candidate is ${least_diffy_ref}"
    echo "- It has ${least_diffy_cnt} changes against ${pw_tag_archived} ($(shorten_sha ${pick_from}))"
    echo
    echo "  \$ git --no-pager diff \${pick_from}..\${least_diffy_ref} --compact-summary"
    echo "  \$ git --no-pager diff ${pick_from}..${least_diffy_ref} --compact-summary"
    git --no-pager diff ${pick_from}..${least_diffy_ref} --compact-summary
    echo
    echo "- Wanna see more of it?:"
    echo
    echo "    cd $(pwd)"
    echo "    git --no-pager diff ${pw_tag_archived}..${least_diffy_ref} --compact-summary"
    echo "    git diff ${pw_tag_archived}..${least_diffy_ref}"
    echo
    echo "I'll understand if you want to cancel and deal with this yourself."
    echo "- You could rebase and reset '${pw_tag_archived}' tag and re-run this command."
    echo "Otherwise, I'm here if you want to continue."
    echo
  fi

  # Add 'E' binding to run the previous git-diff command from tig, ha!
  # - While I like idea of using 'main' keymap, using 'generic' so it's
  #   grouped in the help with the other put-wise commands.
  local diff_binding="\
bind generic E !sh -c \" \\
  git_put_wise__pull__diff_reset_changes____ () { \\
    echo; \\
    echo \\\"git diff ${pw_tag_archived}..${least_diffy_ref}\\\"; \\
    git diff ${pw_tag_archived}..${least_diffy_ref}; \\
    echo; \\
    echo \\\"Done! Back to tig...\\\"; \\
  }; git_put_wise__pull__diff_reset_changes____\"
    "

  local least_diffy_ref_short=$(shorten_sha "${least_diffy_ref}")

  # REFER: These all show up in tig @linux: pw-🚩🏁🔀🖖🆚
  local pw_tag_least_diffy_ref="pw/🆚/diff-distance/${least_diffy_cnt}/${tracking_upstream}"
  git tag -f "${pw_tag_least_diffy_ref}" "${pick_from}" > /dev/null

  local approved=true

  print_tig_review_instructions_pull \
    "${pw_tag_least_diffy_ref}" "${tracking_upstream}" "${least_diffy_ref_short}" "${pick_from}" \
    || approved=false

  if ${approved}; then
    prompt_user_to_review_action_plan_using_tig "${diff_binding}" \
      || approved=false
  fi

  git tag -d "${pw_tag_least_diffy_ref}" > /dev/null 2>&1 || true

  if ! ${approved}; then
    >&2 echo "${PW_USER_CANCELED_GOODBYE}"

    maybe_unstash_changes ${pop_after}

    exit 1
  fi

  echo

  # ***

  # Cherry pick commits from breadcrumb tag through old HEAD. This represents
  # local work you've done since --archive. We cherry-pick onto the remote
  # branch HEAD, which we assume contains everything up to and including the
  # latest --archive, and maybe more, because the remote branch may have new
  # work from the remote host.

  local ephemeral_branch="$(format_pw_tag_ephemeral_pull "${branch_name}")"

  if ! must_insist_ephemeral_branch_does_not_exist "${ephemeral_branch}"; then
    maybe_unstash_changes ${pop_after}

    return 1
  fi

  ephemeral_branch="$(\
    prepare_ephemeral_branch_if_commit_scoping "${ephemeral_branch}" "${reset_ref}"
  )" || exit $?

  echo "git reset --hard \"${reset_ref}\""

  ${DRY_RUN} git reset --hard "${reset_ref}"

  # The original put-wise-pull ran cherry-pick:
  #     git cherry-pick "${pick_from}..${old_head}"
  # - And then wait-prompts the user to resolve conflicts (if any).
  # - If the user cancels (e.g., Ctrl-c) the wait-prompt, their working
  #   tree is left in a weird state (on ephemeral branch, tags not deleted).
  # - But we can do better if we play off rebase 'exec' — we don't need
  #   to hog one terminal to wait-prompt; and we can support an abort.
  # - Note that cherry-pick doesn't use an editable todo. It uses
  #   `.git/sequencer/todo`, which contains 'pick' commands. But if you
  #   try to append an 'exec', it breaks `git cherry-pick --continue`.

  # Whether we cleanup immediately (on pick success) or if we defer
  # cleanup via rebase-todo 'exec'.
  local cleanup_func=put_wise_pull_remotes_cleanup

  if [ "${pick_from}" != "${old_head}" ]; then
    echo
    echo_announce "Rebase-pick $(shorten_sha "${pick_from}")..$(shorten_sha "${old_head}")"

    local retcode=0

    export GIT_SEQUENCE_EDITOR="f () { \
      local rebase_todo_path=\"\$1\"; \
      \
      local commit; \
      \
      for commit in \$(git rev-list ${pick_from}..${old_head}); do \
        echo \"pick \$(git log -1 --pretty=oneline --abbrev-commit \${commit})\" \
          >> \"\${rebase_todo_path}\"; \
      done; \
    }; f \"\$1\""

    [ -z "${DRY_RUN}" ] || __DRYRUN "GIT_SEQUENCE_EDITOR=${GIT_SEQUENCE_EDITOR}"

    ${DRY_RUN} git rebase -i HEAD || retcode=$?

    unset -v GIT_SEQUENCE_EDITOR

    if [ ${retcode} -ne 0 ]; then
      cleanup_func="git_post_rebase_exec_inject_callback ${cleanup_func}"

      badger_user_rebase_failed
    fi
  fi

  GIT_ABORT=false \
  ${cleanup_func} \
    "${branch_name}" \
    "${pw_tag_archived}" \
    "${pick_from}" \
    "${old_head}" \
    "${reset_ref}" \
    "${merge_base}" \
    "${pop_after}" \
    "${ephemeral_branch}"

  return ${retcode}
}

put_wise_pull_remotes_cleanup () {
  local branch_name="$1"
  local pw_tag_archived="$2"
  local pick_from="$3"
  local old_head="$4"
  local reset_ref="$5"
  local merge_base="$6"
  local pop_after="$7"
  local ephemeral_branch="$8"

  # In case running via rebase-todo 'exec', or from `git abort`,
  # run entry point checks.
  #
  # E.g., `PW_OPTION_DRY_RUN=true git put-wise abort`
  ${PW_OPTION_DRY_RUN} && DRY_RUN="${DRY_RUN:-__DRYRUN}"
  #
  local before_cd="$(pwd -L)"
  #
  # Side effect: `cd`'s, and updates PW_PROJECT_PATH, to canonicalize.
  must_cd_project_path_and_verify_repo
  #
  must_not_be_patches_repo

  if ! ${GIT_ABORT:-false}; then
    # Do you care how we wind down? We want to set the original branch
    # HEAD to the ephemeral branch HEAD, and then to delete the ephemeral
    # branch. Here's that approach:
    #
    #   git branch -f "${branch_name}" "${ephemeral_branch}"
    #   checkout_branch_quietly "${branch_name}"
    #   cleanup_ephemeral_branch "${ephemeral_branch}"
    #
    # But an easier approach is to delete the original branch and then to
    # assume its position.

    # Don't blather or we besmirch user's terminal,
    # because 'exec' ran in background (&).
    # 
    #  echo "resume branch \"${branch_name}\""

    git branch -q -D "${branch_name}"
    git branch -m "${branch_name}"
  else
    # User called `git abort`.

    # Don't blather or we besmirch user's terminal,
    # because 'exec' ran in background (&).
    #
    #  echo "restore branch \"${branch_name}\""

    git checkout "${branch_name}"
    git branch -q -D "${ephemeral_branch}"
  fi

  # Call optional post-rebase user hook immediately.
  git_post_rebase_exec_run ${pop_after}

  ! ${GIT_ABORT:-false} || return 0

  # ***

  add_patch_history_tags "${branch_name}" "${old_head}" \
    "${pick_from}" "${reset_ref}" "${merge_base}"

  manage_pw_tracking_tags "${branch_name}" "${reset_ref}" "${pw_tag_archived}"

  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ] \
    && [ "${reset_ref}" = "refs/remotes/${REMOTE_BRANCH_RELEASE}" ]; \
  then
    maybe_move_branch_forward "${LOCAL_BRANCH_RELEASE}" "${reset_ref}"
  fi

  # For completeness, otherwise completely unnecessary.
  cd "${before_cd}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_locate_tracking_upstream () {
  local branch_name="$1"

  local tracking_upstream=""

  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ] ||
    [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ]; \
  then
    if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ]; then
      if git_remote_exists "${SCOPING_REMOTE_NAME}" && \
        must_ensure_protected_remote_branch_exists; \
      then
        tracking_upstream="${REMOTE_BRANCH_SCOPING}"
      fi
      # else, no scoping remote, so might be a 'private' branch with
      # 'release' upstream.
    fi

    if [ -z "${tracking_upstream}" ]; then
      if git_remote_exists "${RELEASE_REMOTE_NAME}"; then
        # Look instead for refs/remotes/publish/release.
        must_ensure_ready_to_rebase_onto_remote_release_branch
        tracking_upstream="${REMOTE_BRANCH_RELEASE}"
      else
        ${PW_OPTION_FAIL_ELEVENSES} && exit ${PW_ELEVENSES}

        >&2 echo "ERROR: Please setup an appropriate remote for '${branch_name}':" \
                 "Try either/and “${SCOPING_REMOTE_NAME}” or “${RELEASE_REMOTE_NAME}”."

        exit 1
      fi
    fi
  else
    # Arbitrary, non-special (not 'private' or 'release') branch.
    tracking_upstream="$(must_have_git_tracking_branch_or_exit)" || exit $?

    # MAYBE/2023-01-18: GIT_FETCH: Use -q?
    ${DRY_RUN} git fetch -q "$(git_upstream_parse_remote_name "${tracking_upstream}")"
  fi

  printf "${tracking_upstream}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# We've identified refs/remotes/entrust, but not entrust/scoping.
#
# We run this command once or twice, a second time to fetch then retest.
must_ensure_protected_remote_branch_exists () {
  # MAYBE/2023-01-18: GIT_FETCH: Use -q?
  ${DRY_RUN} git fetch -q "${SCOPING_REMOTE_NAME}"

  local remote_sha
  remote_sha="$(git_remote_branch_object_name "${REMOTE_BRANCH_SCOPING}")" || remote_sha=""

  if [ -z "${remote_sha}" ]; then
    # Has 'entrust' remote, and definitely no upstream 'entrust/scoping'.
    # - We /could/ fallback 'publish/release', but this seems like an
    #   error. Why would the user have the 'entrust' remote?
    >&2 echo "ERROR: There's no remote “${REMOTE_BRANCH_SCOPING}” branch," \
             "but the “${SCOPING_REMOTE_NAME}” remote exists. You" \
             "should push or remove or change the remote name."

    exit 1
  fi

  must_confirm_upstream_shares_history_with_head \
    "${REMOTE_BRANCH_SCOPING}" "${remote_sha}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_have_git_tracking_branch_or_exit () {
  # See also: git_tracking_branch_safe
  reset_ref="$(git_tracking_branch)" || true

  if [ -z "${reset_ref}" ]; then
    ${PW_OPTION_FAIL_ELEVENSES} && exit ${PW_ELEVENSES}

    >&2 echo "ERROR: Please set a tracking branch so we know what to pull"

    exit 1
  fi

  printf "${reset_ref}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_ensure_ready_to_rebase_onto_remote_release_branch () {
  # MAYBE/2023-01-18: GIT_FETCH: Use -q?
  ${DRY_RUN} git fetch -q "${RELEASE_REMOTE_NAME}"

  local remote_sha
  remote_sha="$(git_remote_branch_object_name "${REMOTE_BRANCH_RELEASE}")" || remote_sha=""

  if [ -z "${remote_sha}" ]; then
    >&2 echo "ERROR: Please setup an appropriate remote branch for '${LOCAL_BRANCH_PRIVATE}':" \
             "Try either/and “${REMOTE_BRANCH_SCOPING}” or “${REMOTE_BRANCH_RELEASE}”."

    exit 1
  fi

  if ! git_branch_exists "${LOCAL_BRANCH_RELEASE}"; then
    fatal_report_missing_local_release_branch
  fi

  must_confirm_upstream_shares_history_with_head \
    "${REMOTE_BRANCH_RELEASE}" "${remote_sha}"
}

# ***

fatal_report_missing_local_release_branch () {
  local merge_base=$(git merge-base "${REMOTE_BRANCH_RELEASE}" "HEAD")

  >&2 echo "ERROR: Found remote “${REMOTE_BRANCH_RELEASE}”" \
    "but not local “${LOCAL_BRANCH_RELEASE}”."
  >&2 echo "- HINT: You might be able to create “${LOCAL_BRANCH_RELEASE}”" \
    "at the merge-base:"
  >&2 echo "    # git merge-base \"\${REMOTE_BRANCH_RELEASE}\" HEAD"
  >&2 echo "    $ git merge-base \"${REMOTE_BRANCH_RELEASE}\" HEAD"
  >&2 echo "    ${merge_base}"
  >&2 echo "    $ git branch ${LOCAL_BRANCH_RELEASE}" \
    "$(git rev-parse --short=${PW_SHA1SUM_LENGTH} ${merge_base})"

  exit 1
}

# ***

# 2022-11-14: This function inspired by must_confirm_shares_history_with_head,
# but markedly different, too, especially the ancestor_sha = remote_sha check.
must_confirm_upstream_shares_history_with_head () {
  local remote_ref="$1"
  local remote_sha="$2"

  local head_sha
  head_sha="$(git rev-parse HEAD)"

  if [ "${remote_sha}" = "${head_sha}" ]; then
    >&2 echo "Nothing to do: Already up-to-date with “${remote_ref}”"

    exit ${PW_ELEVENSES}
  fi

  local ancestor_sha
  ancestor_sha="$(git merge-base "${remote_sha}" "HEAD")"

  if [ "${ancestor_sha}" = "${remote_sha}" ]; then
    >&2 echo "Nothing to do: “${remote_ref}” is behind HEAD"

    exit ${PW_ELEVENSES}
  elif [ "${ancestor_sha}" != "${head_sha}" ]; then
    # The common ancestor is not HEAD, which we would expect if the
    # remote publish/release was ahead of release. And since we already
    # checked that publish/release and release don't already reference
    # the same object, and that publish/release is not behind HEAD,
    # and now that publish/release is not ahead of HEAD, it seems the
    # two branches have diverged.
    # - We assume if the ancestor is at least not the first commit,
    #   that it's safe to 3-way rebase.
    if [ "${ancestor_sha}" = "$(git_first_commit_sha)" ]; then
      >&2 echo "ERROR: The remote “${remote_ref}” branch does not share history with HEAD."

      exit 1
    fi
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

print_tig_review_instructions_pull () {
  local pw_tag_least_diffy_ref="$1"
  local tracking_upstream="$2"
  local least_diffy_ref_short="$3"
  local pick_from="$4"

  # COPYD: See similar `print_tig_review_instructions` function(s) elsewhere.
  print_tig_review_instructions () {
    echo "Please review and confirm the *pull plan*"
    echo
    echo "We'll run tig, and you can look for this tag in the revision history:"
    echo
    local help_tag_prefix="  <${pw_tag_least_diffy_ref}> — "
    echo "${help_tag_prefix}Pick patches from this revision (‘${least_diffy_ref_short}’)"
    echo "$(echo "${help_tag_prefix}" | sed 's/./ /g') after resetting to remote '${tracking_upstream}' HEAD"
    echo
    echo "Press 'E' to git-diff the local pick-from rev against the closest remote match"
    echo
    echo "- This shows you what local changes, if any, will be \"lost\" by the reset."
    echo "  - Usually, nothing is really lost:"
    echo "    - Oftentimes, after you --archive work and --apply on the leader, you'll"
    echo "      rebase the work before pushing it, such that when you --pull it back"
    echo "      to the client, it's not exactly the same work."
    echo "    - Other times, you'll --archive PROTECTED commits, but if the leader"
    echo "      only --push'es to a public remote, those commits will not come back"
    echo "      down to the client on --pull. If you want to keep such commits, reword"
    echo "      them PRIVATE, otherwise they'll drop from the client (but remain on the"
    echo "      leader)."
    echo
    echo "Then press 'w' to confirm the plan and apply patches"
    echo "- Or press 'q' to quit tig and cancel everything"
    ${PW_OPTION_QUICK_TIG:-false} || tig_prompt_print_skip_hint
  }
  print_tig_review_instructions

  ${PW_OPTION_QUICK_TIG:-false} || tig_prompt_confirm_launching_tig
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

add_patch_history_tags () {
  local branch_name="$1"
  local old_head="$2"
  local pick_from="$3"
  local reset_ref="$4"
  local merge_base="$5"

  local old_head_short
  old_head_short="$(shorten_sha "${old_head}")"

  # Choose a datetime delimiter that's not a word boundary, like '#', b/c double-click.
  local tag_prefix="pw/${branch_name}/$(date '+%y%m%d_%H%M')/apply"

  local pw_tag_patch_tag

  pw_tag_patch_tag="${tag_prefix}/old_head"
  ${DRY_RUN} git tag "${pw_tag_patch_tag}" "${old_head}"

  pw_tag_patch_tag="${tag_prefix}/pick_from"
  ${DRY_RUN} git tag "${pw_tag_patch_tag}" "${pick_from}"

  pw_tag_patch_tag="${tag_prefix}/merge_base"
  ${DRY_RUN} git tag "${pw_tag_patch_tag}" "${merge_base}"

  pw_tag_patch_tag="${tag_prefix}/reset_ref"
  ${DRY_RUN} git tag "${pw_tag_patch_tag}" "${reset_ref}"
}

# ***

manage_pw_tracking_tags () {
  local branch_name="$1"
  local reset_ref="$2"
  local pw_tag_archived="$3"

  local pw_tag_applied
  pw_tag_applied="$(format_pw_tag_applied "${branch_name}")"

  # Set pw/in.
  ! ${GIT_ABORT:-false} \
    || echo "  git tag -f \"${pw_tag_applied}\" \"${reset_ref}\""
  ${DRY_RUN} git tag -f "${pw_tag_applied}" "${reset_ref}" > /dev/null

  # Remove pw/out. Confirms user has consolidated with remote.
  # - If they run put-wise --pull again, calls normal git-pull.
  ! ${GIT_ABORT:-false} \
    || echo "  git tag -d \"${pw_tag_archived}\""
  ${DRY_RUN} git tag -d "${pw_tag_archived}" > /dev/null 2>&1 || true
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

maybe_move_branch_forward () {
  local local_ref="$1"
  local remote_ref="$2"

  [ -n "${local_ref}" ] || return

  # Only advance 'release' if this is not the 'release' branch already.
  [ "$(git_branch_name)" != "${local_ref}" ] || return

  local local_sha="$(git_commit_object_name "${local_ref}")"

  local remote_sha
  remote_sha="$(git_remote_branch_object_name "${remote_ref}")" || remote_sha=""

  # Only advance 'release' if it's strictly behind the remote.
  local ancestor_sha
  ancestor_sha="$(git merge-base "${local_sha}" "${remote_sha}")"

  if [ "${ancestor_sha}" = "${local_sha}" ]; then
    ! ${GIT_ABORT:-false} \
      || echo "Advance “${local_ref}” to match “${remote_ref}”."

    ! ${GIT_ABORT:-false} \
      || echo "git branch -f --no-track \"${local_ref}\" \"${remote_ref}\""

    ${DRY_RUN} git branch -f --no-track "${local_ref}" "${remote_ref}"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE}" ]; then
  >&2 echo "😶"
fi

