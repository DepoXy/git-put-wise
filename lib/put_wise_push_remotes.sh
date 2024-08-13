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

put_wise_push_remotes () {
  ${PW_OPTION_DRY_RUN} && DRY_RUN="${DRY_RUN:-__DRYRUN}"

  local before_cd="$(pwd -L)"

  # Side effect: `cd`'s, and updates PW_PROJECT_PATH, to canonicalize.
  must_cd_project_path_and_verify_repo

  must_not_be_patches_repo

  put_wise_push_remotes_go

  cd "${before_cd}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Reusable fcn. to determine oldest sort-by-scope commit automatically.
# - E.g., if you have a local 'release' (or 'private') branch, and the
#   upstream remote is 'publish/release', sets
#     sort_from_commit='publish/release'
# - Also used by put-wise-push to suss other remote and branch vars.
#
# SORRY: I don't generally like to "abuse" `local` like this. It seems
# like a weird side-effect to have a fcn. set its caller's vars.
# - But this is shell script, and passing data is not always so simple.
#   And I want to reuse the sort_from_commit susser without refactoring
#   complex code that's been working for years.
#
# REFER:
# - This fcn will set the following vars (its "return" values):
#     local_release=""
#     remote_release=""
#     remote_liminal=""
#     remote_protected=""
#     remote_current=""
#     remote_name=""
#     branch_name=""
#     sort_from_commit=""
# - Other side effects:
#   - Calls `git fetch` as appropriate to ensure remote branch
#     ref is accurate/up to date.
#   - Fails if bad state detected (e.g., diverged branches).

put_wise_suss_push_vars_and_rebase_sort_by_scope_automatic () {
  local action_desc="$1"

  # Caller vars set below:
  branch_name="$(git_branch_name)"
  local_release=""
  remote_release=""
  remote_liminal=""
  remote_protected=""
  remote_current=""
  remote_name=""
  sort_from_commit=""

  local include_liminal="${PW_OPTION_USE_LIMINAL:-false}"
  local force_liminal=false

  local sortless_msg=""

  local applied_tag="$(format_pw_tag_applied "${branch_name}")"

  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ]; then
    local_release="${LOCAL_BRANCH_RELEASE}"
    remote_release="${REMOTE_BRANCH_RELEASE}"
    remote_liminal="${REMOTE_BRANCH_LIMINAL}"
    remote_protected="${REMOTE_BRANCH_SCOPING}"

    # The pw/in tag signifies the final patch from the latest --apply command.
    # It's the remote's HEAD, essentially (minus PRIVATE commits).
    # This is the fallback sort-from, in case there's no 'release' branch.
    # Note that this will move PRIVATE commits toward HEAD, but it'll
    # leave behind PROTECTED commits that may precede pw/work. (The
    # pw/work tag is the merge-base from the latest --apply command. It's
    # what the patches were based from, and it signifies what this host
    # pushed before that the remote added work to. I.e., when this host
    # pushed pw/work, it had just resorted, and PROTECTED commits were
    # bubbled toward pw/work. So if we wanted to move those commits
    # forward now, we'd have to set sort-from to a commit preceding
    # pw/work. Fortunately, we can use the 'release' branch, which
    # precedes these PROTECTED commits, as the sort-from base. Using
    # this tag is just fallback, but note that it means we won't move
    # earlier PROTECTED commits forward. Which we can a feature of not
    # having a 'release' branch.
    if git_tag_exists "${applied_tag}"; then
      sort_from_commit="${applied_tag}"
    fi

    # User can opt-into 'liminal' usage, or if remote branch exists,
    # then it's automatic. (User has to manually delete that branch
    # if you want to disable 'liminal' behavior.)
    if ${include_liminal} || git_remote_branch_exists "${remote_liminal}"; then
      force_liminal=true
    else
      remote_liminal=""
    fi

    if git_remote_branch_exists "${remote_protected}"; then
      # The --push host is considered the leader, and it will rebase as far
      # back as it takes to bubble up PROTECTED commits. The simplest case
      # is when there's a 'release' branch -- we'll pick that (below) as the
      # sort-from-commit, and we'll rebase all commits since 'release'.
      # But if there's no 'release' branch, there's not much point to having
      # PROTECTED commits, is there? And without the 'release' branch as
      # reference, it's less trivial to determine the sort-from-commit:
      # we could either rebase from the very first commit (easy solution),
      # or we could start walking from pw/work (with is the last --apply
      # command merge-base) -- because there are PROTECTED commits adjacent
      # to the pw/work tag. Walk from pw/work toward the root commit
      # until there are no more PROTECTED commits, and rebase from there,
      # and you'll bubble all the PROTECTED commits forward to HEAD. But this
      # sounds tedious, and doesn't seem like a feature anyone cares about
      # (surfacing PROTECTED commits in a repo that's not being published
      # (has no 'release' branch)). So we (I, the author) choose to leave
      # PROTECTED commits behind, abandoned, frozen in time if there's no
      # 'release' branch. If that's the case -- no 'release' reference --
      # we'll first fallback pw/applied, and then we'll fallback the
      # protected remote. Which, to be honest, generally ref. the same.
      if [ -z "${sort_from_commit}" ]; then
        sort_from_commit="${remote_protected}"
      fi

      # Always fetch the remote, so that our ref is current,
      # because this function also does a lot of state validating.
      # MAYBE/2023-01-18: GIT_FETCH: Use -q?
      echo_announce "Fetch from ‘${SCOPING_REMOTE_NAME}’"

      git fetch "${SCOPING_REMOTE_NAME}"
    else
      remote_protected=""
    fi

    # Prefer sorting from local or remote 'release' branch. This is easier
    # than walking from pw/work to see when scoping ends, and sorting from
    # there.
    if git_remote_branch_exists "${remote_release}"; then
      sort_from_commit="${remote_release}"

      # MAYBE/2023-01-18: GIT_FETCH: Use -q?
      echo_announce "Fetch from ‘${RELEASE_REMOTE_NAME}’"

      git fetch "${RELEASE_REMOTE_NAME}"
    else
      remote_release=""
    fi

    if git_branch_exists "${local_release}"; then
      sort_from_commit="${local_release}"
    else
      local_release=""
    fi

    # else, if sort_from_commit unset, will die after return from if-block.

    if [ -n "${remote_release}" ] && [ -n "${local_release}" ]; then
      # Verify 'release/release' is at or behind 'release'.
      local divergent_ok=false

      must_confirm_commit_at_or_behind_commit "${remote_release}" "${local_release}" \
        ${divergent_ok} "remote-release" "local-release"

      # Resort since 'release', which is guaranteed further along.
      sort_from_commit="${local_release}"
    fi

    # When liminal enabled, we never force-push to 'release'.
    if ${PW_OPTION_FORCE_PUSH} && ${force_liminal}; then
      local_release=""
      remote_release=""
    fi

    # NOTE: If resorting since 'release' or 'publish/release', it means
    #       you will need to push --force 'entrust/scoping', and then
    #       on the @business device, you need to rebase on pull. Just
    #       how it works because you're managing so many unshareable
    #       forks.

    if [ -z "${sort_from_commit}" ]; then
      sortless_msg="$(echo -e \
        "Options:" \
        "\n- Use --apply command, so '${applied_tag}' tag gets set." \
        "\n- Push upstream to '${REMOTE_BRANCH_SCOPING}' branch." \
        "\n- Push upstream to '${REMOTE_BRANCH_RELEASE}' branch." \
        "\n- Create local '${LOCAL_BRANCH_RELEASE}' branch." \
        "\nComplete any one of these activities and then you may ${action_desc}" \
      )"
    fi

  # fi: very long [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ]

  elif [ "$(git_branch_name)" = "${LOCAL_BRANCH_RELEASE}" ]; then
    # Because we rebase to reorder scoping commits, we need to identify
    # a starting ref. Without a starting ref, it gets complicated (do
    # we resort everything? Do we find the first PROTECTED or PRIVATE
    # commit and rebase from there?). It's easier to tell the user to
    # make the first push.
    must_verify_remote_branch_exists "${REMOTE_BRANCH_RELEASE}"

    # So that merge-base is accurate.
    # MAYBE/2023-01-18: GIT_FETCH: Use -q?
    echo_announce "Fetch from ‘${RELEASE_REMOTE_NAME}’"
    git fetch "${RELEASE_REMOTE_NAME}"

    sort_from_commit="${REMOTE_BRANCH_RELEASE}"

    remote_release="${REMOTE_BRANCH_RELEASE}"
  else
    # $(git_branch_name) not 'release'|'protected'|'private'.
    # - Note that push.default defaults to 'simple', which pushes to upstream
    #   tracking branch when pushing to that remote, otherwise works like
    #   push.default 'current', which uses same name for pushing.
    #   - For feature branches, I like to track the trunk, so git-pull
    #     rebases appropriately. But I like push.default 'current', so
    #     that push uses the same feature branch name that I use locally.
    # - The following effectively mimics 'current'.
    local tracking_branch

    if ! tracking_branch="$(git_tracking_branch)"; then
      >&2 echo "ERROR: No tracking branch: Needed to determine push remote"
      >&2 echo "- Either \`git branch -u <remote>/<branch>\` or use --remote"

      exit 1
    fi

    remote_name="${PW_OPTION_REMOTE}"

    if [ -z "${remote_name}" ]; then
      remote_name="$(git_upstream_parse_remote_name "${tracking_branch}")"
    fi

    if [ -z "${remote_name}" ]; then
      >&2 echo "ERROR: Cannot determine push remote from tracking branch"
      >&2 echo "- Either \`git branch -u <remote>/<branch>\` or use --remote"

      exit 1
    fi

    echo_announce "Fetch from ‘${remote_name}’"

    # MAYBE/2023-01-18: GIT_FETCH: Use -q?
    git fetch "${remote_name}"

    remote_current="${remote_name}/${branch_name}"

    if ! ${PW_OPTION_FORCE_PUSH} && git_remote_branch_exists "${remote_current}"; then
      sort_from_commit="${remote_current}"
    else
      # Similarly to the 'release' branch, which dies if no 'publish/release'
      # yet, here we die if there's not upstream ref, either. But this path
      # will likely not happen for new feature branches so long as the user
      # uses a tracking branch. E.g., consider a new branch was made like this:
      #   git checkout -b feature/abc && git branch -u origin/main
      # Then when you first call `put-wise --archive`, this if-block runs,
      # and we'll set sort_from_commit to origin/main.
      must_verify_remote_branch_exists "${tracking_branch}"

      sort_from_commit="${tracking_branch}"
    fi
  fi

  if [ -z "${sort_from_commit}" ]; then
    ${PW_OPTION_FAIL_ELEVENSES} && exit ${PW_ELEVENSES}

    >&2 echo "ERROR: Nothing upstream identified for project: “$(pwd -L)”"
    >&2 echo "- Branch: “$(git_branch_name)”"
    if [ -n "${sortless_msg}" ]; then
      >&2 echo -e "${sortless_msg}"
    else
      >&2 echo "You may need to get things rolling by initiating the first push."
    fi

    exit 1
  fi

  # ***

  # Overzealous UX reporting if diverging from tags, not sure why I care
  # to alert user.

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
          "${tag_name}" "${sort_from_commit}" ${divergent_ok} \
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

put_wise_push_remotes_go () {
  local git_push_force=""
  ! ${PW_OPTION_FORCE_PUSH} || git_push_force="--force-with-lease"

  # ***

  # The following vars are set by the sort_from_commit, etc., susser:
  local branch_name=""
  local local_release=""
  local remote_release=""
  local remote_liminal=""
  local remote_protected=""
  local remote_current=""
  local remote_name=""
  local sort_from_commit=""
  put_wise_suss_push_vars_and_rebase_sort_by_scope_automatic "push"

  # ***

  # Note that confirm_state_and_resort_to_prepare_branch checks that
  # sort-from shares history with HEAD:
  #   must_confirm_commit_at_or_behind_commit "${sort_from_commit}" "HEAD"

  >&2 debug "sort_from_commit: ${sort_from_commit}"

  if ! git_is_same_commit "${sort_from_commit}" "HEAD"; then
    confirm_state_and_resort_to_prepare_branch "${sort_from_commit}" \
      ${_enable_gpg_sign:-true}
  fi

  # ***

  local release_boundary_or_HEAD
  release_boundary_or_HEAD="$( \
    identify_scope_ends_at "^${SCOPING_PREFIX}" "^${PRIVATE_PREFIX}" \
  )"

  local protected_boundary_or_HEAD
  protected_boundary_or_HEAD="$( \
    identify_scope_ends_at "^${PRIVATE_PREFIX}" \
  )"

  # It's assumed you control the 'release' branch and that you wouldn't
  # be using this script otherwise, which is why we just move this pointer.
  if [ -n "${local_release}" ]; then
    # local_release non-empty iff current branch is LOCAL_BRANCH_PRIVATE
    # (so this if-check always passes).
    if [ "$(git_branch_name)" != "${LOCAL_BRANCH_RELEASE}" ]; then
      if git merge-base --is-ancestor \
        "${LOCAL_BRANCH_RELEASE}" "${release_boundary_or_HEAD}" \
      ; then
        echo_announce "Move ‘${LOCAL_BRANCH_RELEASE}’ HEAD"

        git_force_branch "${LOCAL_BRANCH_RELEASE}" "${release_boundary_or_HEAD}"
        # MAYBE/2023-12-03: Restore branch pointer if git-push canceled/fails?
      else
        # See also: must_confirm_commit_at_or_behind_commit
        >&2 warn "BWARE: Not moving ‘${LOCAL_BRANCH_RELEASE}’ HEAD, because it is"
        >&2 warn "  not an ancestor of the release boundary:"
        >&2 warn "    ${release_boundary_or_HEAD}"
        >&2 warn "- This means the ‘${LOCAL_BRANCH_RELEASE}’ branch includes scoped commits!"
        >&2 warn "  - I.e., commit messages that start with \"${SCOPING_PREFIX}\" or \"${PRIVATE_PREFIX}\""
      fi
    fi
  fi

  # ***

  # Temporary pw-private/pw-protected scoping tags. For user, not for code.
  # - Note that some characters will not claim their full width in the
  #   terminal (including tig) such as 🛡 or 🛡️. Odder, some might show up
  #   in the terminal but appear blank in tig, such as 🥷 (on author's @linux).
  #   - Just FYI that you should `git tag test-🥷-me` aforehand.
  PW_TAG_SCOPE_MARKER_PRIVATE="pw-🔴"
  PW_TAG_SCOPE_MARKER_PROTECTED="pw-🔵"
  # Here's a test tag to show which characters display properly in @linux tig:
  #   PW_TAG_SCOPE_MARKER_PROTECTED="pw-🔴🟠🟡🟢🔵🟣🟤⚫⚪🟥🟧🟨🟩🟦🟪🟫⬛⬜"
  #                             @linux: ^^      ^^    ^^^^              ^^^^
  #                             @macOS: ^^      ^^
  # NOTED/2024-06-23: @macOS tig doesn't render these all, either, even
  # with ncusrsw support.
  # - The terminal shows these characters, though. E.g., echo the line above
  #   to iTerm2 or Kitty and it looks good, and echoed to Alacritty it looks
  #   mostly good, but Alacritty uses the simpler black and white VS15 variation
  #   selector for some symbols, e.g., ⚫ and ⚪ print as ⚫︎and ⚪︎ (though when
  #   you copy-paste from Alacritty to another app, they appear VS16 again).
  #   - REFER: https://en.wikipedia.org/wiki/Variation_Selectors_(Unicode_block)
  #            https://en.wikipedia.org/wiki/Miscellaneous_Symbols
  # - But when you commit these symbols to Git and view in tig, many of them
  #   are simply absent/blank. And if you copy from the text from tig and
  #   paste elsewhere, you'll see the symbols have been replaced with spaces.
  # - See OMR tig build, which supports wide-char:
  #     ~/.depoxy/ambers/home/.kit/git/_mrconfig-git-core
  #   - But only 🔴 and 🔵 are visible.

  # Use different flags for different branches: release, liminal, scoping, therest.
  # - SAVVY: Test new emoji b/c not all visible in tig ... # ↓↓↓↓↓ These all visible in tig @linux
  #   - On @macOS, below are all visible in tig except: 🧚⛔⛓️
  PW_TAG_PREFIX_RELEASE="${PW_TAG_PREFIX_RELEASE:-pw-📢}"  # 📢🚀
  PW_TAG_PREFIX_LIMINAL="${PW_TAG_PREFIX_LIMINAL:-pw-💥}"  # 🔥🌀💥🎯🧚
  PW_TAG_PREFIX_SCOPING="${PW_TAG_PREFIX_SCOPING:-pw-💪}"  # 🔰💪🔐🔒🔏🔑🔓⛔🙌🤐🛑👇⛓️
  PW_TAG_PREFIX_THEREST="${PW_TAG_PREFIX_THEREST:-pw-🚩}"  # 🚩🏁🔀
  PW_TAG_SCOPE_PUSHES_RELEASE="${PW_TAG_PREFIX_RELEASE}-${RELEASE_REMOTE_BRANCH}"
  PW_TAG_SCOPE_PUSHES_LIMINAL="${PW_TAG_PREFIX_LIMINAL}-${LIMINAL_REMOTE_BRANCH}"
  PW_TAG_SCOPE_PUSHES_SCOPING="${PW_TAG_PREFIX_SCOPING}-${SCOPING_REMOTE_NAME}"
  PW_TAG_SCOPE_PUSHES_THEREST="${PW_TAG_PREFIX_THEREST}-${branch_name}"

  # Skip ${DRY_RUN}, tags no biggie, and user wants to see in tig.
  git tag -f "${PW_TAG_SCOPE_MARKER_PRIVATE}" "${protected_boundary_or_HEAD}" > /dev/null
  git tag -f "${PW_TAG_SCOPE_MARKER_PROTECTED}" "${release_boundary_or_HEAD}" > /dev/null

  local tagged_release=""
  local tagged_liminal=""
  local tagged_scoping=""
  local tagged_current=""

  if [ -n "${remote_release}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_RELEASE}" "${release_boundary_or_HEAD}" > /dev/null
    tagged_release="${PW_TAG_SCOPE_PUSHES_RELEASE}"
  fi

  if [ -n "${remote_liminal}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_LIMINAL}" "${release_boundary_or_HEAD}" > /dev/null
    tagged_liminal="${PW_TAG_SCOPE_PUSHES_LIMINAL}"
  fi

  if [ -n "${remote_protected}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_SCOPING}" "${protected_boundary_or_HEAD}" > /dev/null
    tagged_scoping="${PW_TAG_SCOPE_PUSHES_SCOPING}"
  fi

  if [ -n "${remote_current}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_THEREST}" "${release_boundary_or_HEAD}" > /dev/null
    tagged_current="${remote_name}/${branch_name}"
  fi

  # ***

  # Don't errexit on git-push failure until after cleaning up tags.
  local keep_going=false

  handle_push_failed () {
    local remote_branch="$1"

    keep_going=false

    local ornament="$(fg_lightyellow)$(bg_myrtle)"

    echo "${ornament}ERROR: Push failed! denied by ‘${remote_branch}’$(attr_reset)"
  }

  # In the prompt_user call, note that we have "<remote>/<branch>" vars.
  # already, e.g., we could use ${remote_release} instead of the complete
  #   ${RELEASE_REMOTE_NAME}/${RELEASE_REMOTE_BRANCH}
  # but the latter matches the git-push command, so using that for matchability.

  if prompt_user_to_continue_update_remotes \
    "${tagged_release}" "${RELEASE_REMOTE_NAME}/${RELEASE_REMOTE_BRANCH}" \
    "${tagged_liminal}" "${LIMINAL_REMOTE_NAME}/${LIMINAL_REMOTE_BRANCH}" \
    "${tagged_scoping}" "${SCOPING_REMOTE_NAME}/${SCOPING_REMOTE_BRANCH}" \
    $(test -z "${remote_name}" || printf "%s" "${tagged_current}") \
      $(test -z "${remote_name}" || printf "%s" "${remote_name}/${branch_name}") \
  ; then
    # Add 'r' command to restrict push just to 'release'.
    # - Useful when 'liminal' or 'entrust' diverged, and
    #   user didn't use <Ctrl-f> force-push.
    local restrict_release=false
    # - SAVVY: Override tig's built-in `r` — 'view-refs'
    # - COPYD: Similar to lib/tig/config-put-wise
    #   - CXREF: ~/.kit/git/git-put-wise/lib/tig/config-put-wise
    # - SAVVY: The `echo > ${REPLY_PATH}` is reingested as GPW_TIG_PROMPT_CONTENT.
    local restrict_release_binding="\
bind generic r +<sh -c \" \\
 git_put_wise__prompt__r_for_release_branch () { \\
    REPLY_PATH=\\\"\${PW_PUSH_TIG_REPLY_PATH:-.gpw-yes}\\\"; \\
    if [ ! -e \\\"\${REPLY_PATH}\\\" ]; then \\
      echo \\\"${remote_release}\\\" > \\\"\${REPLY_PATH}\\\"; \\
    else \\
      >&2 echo \\\"ERROR: Already exists: \${REPLY_PATH}\\\"; \\
    fi; \\
  }; git_put_wise__prompt__r_for_release_branch\"
    "

    # Side-effect: Caller sets GPW_TIG_PROMPT_CONTENT.
    if prompt_user_to_review_action_plan_using_tig "${restrict_release_binding}"; then
      keep_going=true

      if [ "${GPW_TIG_PROMPT_CONTENT}" = "${remote_release}" ]; then
        restrict_release=true
      fi
    else
      >&2 echo "${PW_USER_CANCELED_GOODBYE}"
    fi

    if ${keep_going}; then
      if prompt_user_to_continue_push_remote_branch ${keep_going} "${remote_release}"; then
        echo_announce_push "${RELEASE_REMOTE_BRANCH}"
        ${DRY_RUN} git push "${RELEASE_REMOTE_NAME}" \
          "${release_boundary_or_HEAD}:refs/heads/${RELEASE_REMOTE_BRANCH}" ${git_push_force} \
            || handle_push_failed "${RELEASE_REMOTE_NAME}/${RELEASE_REMOTE_BRANCH}"
      fi
    fi

    if ${keep_going} && ! ${restrict_release}; then
      if prompt_user_to_continue_push_remote_branch ${keep_going} "${remote_liminal}"; then
        echo_announce_push "${LIMINAL_REMOTE_BRANCH}"
        ${DRY_RUN} git push "${LIMINAL_REMOTE_NAME}" \
          "${release_boundary_or_HEAD}:refs/heads/${LIMINAL_REMOTE_BRANCH}" ${git_push_force} \
            || handle_push_failed "${LIMINAL_REMOTE_NAME}/${LIMINAL_REMOTE_BRANCH}"
      fi

      if prompt_user_to_continue_push_remote_branch ${keep_going} "${remote_protected}"; then
        echo_announce_push "${SCOPING_REMOTE_BRANCH}"
        ${DRY_RUN} git push "${SCOPING_REMOTE_NAME}" \
          "${protected_boundary_or_HEAD}:refs/heads/${SCOPING_REMOTE_BRANCH}" ${git_push_force} \
            || handle_push_failed "${SCOPING_REMOTE_NAME}/${SCOPING_REMOTE_BRANCH}"
      fi

      if prompt_user_to_continue_push_remote_branch ${keep_going} "${remote_current}"; then
        echo_announce_push "${branch_name}"
        ${DRY_RUN} git push "${remote_name}" \
          "${release_boundary_or_HEAD}:refs/heads/${branch_name}" ${git_push_force} \
            || handle_push_failed "${remote_name}/${branch_name}"
      fi
    fi
  fi

  if ! ${keep_going}; then
    echo_announce "Canceled put-wise-push"
  fi

  # ***

  quietly_delete_tag () {
    git tag -d "$1" > /dev/null 2>&1 || true
  }

  quietly_delete_tag "${PW_TAG_SCOPE_MARKER_PRIVATE}"
  quietly_delete_tag "${PW_TAG_SCOPE_MARKER_PROTECTED}"

  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_RELEASE}"
  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_LIMINAL}"
  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_SCOPING}"
  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_THEREST}"

  # Indicate success/failure.
  ${keep_going}
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_verify_remote_branch_exists () {
  local remote_branch="$1"

  ( [ -z "${remote_branch}" ] || ! git_remote_branch_exists "${remote_branch}" ) \
    || return 0

  >&2 echo "ERROR: Where's remote branch “${remote_branch}”?"
  >&2 echo "- Nothing to do for project: “$(pwd -L)”"
  >&2 echo "(We use remote to set scoping rebase starting ref," \
    "and we'd rather not rebase from the first commit nor ask" \
    "you where to start from, so we let you make the first push," \
    "and then we'll use that upstream the next time you call us." \
    "Alternatively, if this is not a special branch" \
    "('${LOCAL_BRANCH_PRIVATE}' or '${LOCAL_BRANCH_RELEASE}')" \
    "you can set a \`git branch -u <>\` upstream tracking branch" \
    "and we'll use that as the rebase-resort start reference."

  exit 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

echo_announce_push () {
  local branch="$1"

  echo_announce "Sending ‘${branch}’"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

git_force_branch () {
  local branch_name="$1"
  local start_point="$2"

  if git_branch_exists "${branch_name}"; then
    ${DRY_RUN} git branch -f --no-track "${branch_name}" "${start_point}"
  else
    # Might as well make a local branch, eh.
    ${DRY_RUN} git branch "${branch_name}" "${start_point}"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

prompt_user_to_continue_update_remotes () {
  local something_tagged=false

  local orig_count="$#"

  local remote_names=""

  while [ $# -gt 0 ]; do
    local tagged_name="$1"
    local remote_branch_nickname="$2"

    if ! shift 2; then
      >&2 echo "GAFFE: prompt_user_to_continue_update_remotes:" \
        "Uneven arg count (${orig_count})"

      exit 1
    fi

    if [ -n "${tagged_name}" ]; then
      something_tagged=true
    fi

    [ -z "${remote_names}" ] || remote_names="${remote_names}\n"
    remote_names="${remote_names}    ${remote_branch_nickname}"
  done

  if ! ${something_tagged}; then
    >&2 echo "ABORT: Cannot push, because no remote branch identified from candidates:"
    >&2 echo -e "${remote_names}"
    >&2 echo "- Hint: If you have not pushed yet, do so manually the first time"
    >&2 echo "  - Or, if this is a private repo without a push remote,"
    >&2 echo "    try the ‘archive’ command"

    exit 1
  fi

  # ***

  ! ${PW_OPTION_QUICK_TIG:-false} || return 0

  # COPYD: See similar `print_tig_review_instructions` function(s) elsewhere.
  print_tig_review_instructions () {
    echo "Please review and confirm the *push plan*"
    echo
    echo "We'll run tig, and you can look for these tag(s) in the revision history:"
    echo

    local pushed_to_msg="This revision will be pushed to"

    local n_args=0
    for arg in "$@"; do
      local tagged_name="$1"
      local remote_branch_nickname="$2"

      if [ -n "${tagged_name}" ]; then
        echo "  <${tagged_name}> — ${pushed_to_msg} ${remote_branch_nickname}"
      fi
    done

    echo
    echo "Then press 'w' to confirm the plan and push"
    echo "- Or press 'q' to quit tig and cancel everything"

    tig_prompt_print_skip_hint
  }
  print_tig_review_instructions

  tig_prompt_confirm_launching_tig
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

prompt_user_to_continue_push_remote_branch () {
  local keep_going="$1"
  local remote_branch="$2"

  ${keep_going} || return 1

  [ -n "${remote_branch}" ] || return 1

  ! ${PW_OPTION_QUICK_TIG:-false} || return 0

  printf "Would you like to push “${remote_branch}”? [y/N] "

  local key_pressed
  local opt_chosen
  prompt_read_single_keypress "n" "y"
  [ "${opt_chosen}" = "y" ] && return 0 || return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
  >&2 echo "😶"
fi

