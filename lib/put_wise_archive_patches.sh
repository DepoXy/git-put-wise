#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

DRY_ECHO=""
# DRY_ECHO=__DRYRUN  # Uncomment to always dry-run, regardless -T|--dry-run.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

put_wise_archive_patches () {
  ${PW_OPTION_DRY_RUN:-false} && DRY_ECHO="${DRY_ECHO:-__DRYRUN}"

  local before_cd="$(pwd -L)"

  # Side effect: `cd`'s, and updates PW_PROJECT_PATH, to canonicalize.
  must_cd_project_path_and_verify_repo
  local before_co

  put_wise_archive_patches_go

  cd "${before_cd}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

put_wise_archive_patches_go () {
  local starting_ref_arg="${PW_OPTION_STARTING_REF}"

  if [ -n "${starting_ref_arg}" ]; then
    info "ALERT: Using --starting-ref is unchartered territory." \
      "What's wrong with using the upstream branch as the ref?"
  fi

  local projpath_sha
  projpath_sha="$(print_project_path_ref)"

  process_return_receipts "${projpath_sha}"

  local branch_name
  branch_name="$(git_branch_name)"
  # E.g., 'pw/private/in'
  local pw_tag_applied="$(format_pw_tag_applied "${branch_name}")"
  # E.g., 'pw/private/out'
  local pw_tag_archived="$(format_pw_tag_archived "${branch_name}")"

  # ***

  local starting_ref
  starting_ref="$(
    print_starting_ref_or_upstream_branch \
      "${starting_ref_arg}" "${pw_tag_applied}" \
  )" || exit_1

  local context=""
  if [ "${starting_ref}" = "${GIT_EMPTY_TREE}" ]; then
    context=" [magic empty tree object]"
  fi

  debug "starting_ref: $(git_sha_shorten "${starting_ref}")${context}"

  # ***

  # Sort & sign commits. Unless exit 0/11 if starting_ref → HEAD
  # (because no-op); or exit_1 if ahead of HEAD, or diverged.
  resort_and_sign_commits_before_push "${_rebase_boundary:-${starting_ref}}" \
    ${_enable_gpg_sign:-false}

  # Determine the extent of the diff range.
  # - Note this local is set as a side effect.
  local commit_range_end
  identify_commit_range_end

  # Exit 0/11 is archive bounds unchanged since last --archive.
  must_have_non_empty_rev_range_not_already_tagged "${starting_ref}" \
    "${commit_range_end}" "${pw_tag_applied}" "${pw_tag_archived}"

  # Make the diff filename from the project name, datetime, and from-sha.
  # - Note these locals are set by compose_filenames.
  #   - Such heavily coupled, side effect wow.
  local hostname_sha
  local starting_sha
  local endingat_sha
  local temp_dir
  local patch_dir
  local patch_name
  local crypt_name
  compose_filenames "${starting_ref}" "${projpath_sha}" "${commit_range_end}"

  # Exit 0/11 is archive already exists.
  must_not_already_be_archived "${crypt_name}" \
    "${hostname_sha}" "${projpath_sha}" \
    "${starting_sha}" "${endingat_sha}"

  # Create the patch directory.
  must_produce_nonempty_patch "${starting_ref}" "${commit_range_end}" "${patch_dir}"

  # Archive and encrypt the format-patch directory.
  local cleartext_name
  cleartext_name="${temp_dir}/${patch_name}.xz"

  local crypt_path
  local success=true
  # Bash let's you assign in a conditional statement, e.g.,
  #   if crypt_path="$(encrypt_archive_and_cleanup)"; then
  # but how silly would that be?
  # - If false, means `pass` or `gpg` failed.
  crypt_path="$(encrypt_archive_and_cleanup)" || success=false

  # Really if ! ${success}, ${crypt_path} also always empty,
  # but being explicit about intent. (And I love commenting.)
  if ! ${success} || [ -z "${crypt_path}" ]; then
    >&2 echo "ERROR: Unable to encrypt patches." \
      "What went wrong, I thought we were a perfect match."

    exit_1
  else
    local before_cd="$(pwd -L)"

    cd "${PW_PATCHES_REPO}"

    maybe_remove_outdated_archives "${crypt_name}" \
      "${hostname_sha}" "${projpath_sha}" \
      "${starting_sha}"

    add_archive_to_repo "${crypt_name}"

    # This doesn't do much except clear objects for any "outdated
    # archives" that were not pushed to the remote.
    git_gc_expire_all_prune_now

    cd "${before_cd}"

    update_archive_tags \
      "${pw_tag_applied}" "${starting_sha}" \
      "${pw_tag_archived}" "${endingat_sha}"

    report_success "${crypt_path}"
  fi

  return 0
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Choosing the starting ref. on --archive is similar to
# choosing the starting ref. on --apply, but the latter
# is more strict about picking the correct ref, and even
# asking the user to confirm.
#
# - For comparison, consider if on --archive we did like
#   the --apply method, and we called
#
#     choose_patch_base_or_ask_user "${starting_ref}" "${pw_tag_applied}" \
#       "${PW_TAG_ONTIME_START}" "${patch_branch}"
#
#   If the user used the on-demand PW_TAG_ONTIME_START tag, the chooser
#   would just pick that. If not, next it checks the starting ref, which
#   makes more sense for --apply: It's the starting-ref indicated in the
#   archive. But at this point during --archive, we don't know the starting
#   ref (that's what we're trying to figure out). Third up is checking the
#   pw/in tag. Which I think for --archive we should always check (and
#   prefer to use). Finally, --apply uses HEAD if there's only 1 commit,
#   otherwise it interacts with the user.
#   - After identifying the starting commit, --apply verifies that using
#     it won't be bad for history. Check out the nifty function
#
#       suss_which_known_branch_is_furthest_along
#
#     which reports which commit from a list of refs is the one furthest
#     along in history (closest to HEAD in the branch). --apply will use
#     this verification step to readjust the starting-ref if necessasry
#     to avoid causing a temporal rift.
#
#  All that said, --archive is a titch different, but somewhat the same.
#  - --archive prefers the pw/in tag to know where to start, much like
#    --apply prefers the starting-ref SHA from the archive.
#  - While --archive doesn't change the working directory, per se, it'll
#    rebase to sort scoping commits, so it doesn't want to totally wing
#    the starting-ref choice. But if it's wrong, user could reset their
#    work, set the pw/in how they want, and re-run the command if they
#    want a specific --archive range.
#  - --archive cares not to include commits that remotes know about, but
#    it doesn't need to use suss_which_known_branch_is_furthest_along
#    (which isn't perfect, currently). It can just identify a single
#    upstream branch, and not worry about the others. Which makes
#    user messages more meaningful (the suss command returns a single
#    commit ref, and doesn't tell you which branches or remotes exist
#    or not, so its use doesn't help us help the user any more).

# Prints an appropriate starting_ref.
# - This functions prefers to use the pw/<branch>/in tag, if it exists
#   and is not behind an upstream branch. Otherwise, this function will
#   start from the first upstream branch it finds.
# - For either special branch, 'private' or 'release', if at least one
#   upstream exists, the starting_ref is the furthest-along put-wise
#   upstream, e.g.,
#     'publish/release' <= 'release' <= 'entrusted/scoping' <= 'private'
#   - For any other branch, this function checks that branch's configured
#     upstream branch, or it checks for an 'origin' remote and looks for
#     the default branch.
# - This function also verifies that commits since starting_ref have
#   not been shared with any remotes, at least verified as best it can.
print_starting_ref_or_upstream_branch () {
  local starting_ref="$1"
  local pw_tag_applied="$2"

  [ -n "${starting_ref}" ] && echo "${starting_ref}" && return 0 || true

  # ***

  local upstream_ref=""
  identify_first_upstream_branch

  local upstream_ref_ref
  [ -z "${upstream_ref}" ] ||
    upstream_ref_ref="$( \
      git_commit_object_name "refs/remotes/${upstream_ref}" 2> /dev/null \
    )"

  # ***

  local pw_tag_ref=""
  if git_tag_exists "${pw_tag_applied}"; then
    pw_tag_ref="$(git_tag_object_name "${pw_tag_applied}")"

    if [ -z "${pw_tag_ref}" ]; then
      >&2 echo "GAFFE: Unexpected DEV error:" \
        "git_tag_object_name \"${pw_tag_applied}\" failed"

      return 1
    fi
  fi

  # ***

  if [ -n "${pw_tag_ref}" ] && [ -n "${upstream_ref_ref}" ]; then
    if [ "${pw_tag_ref}" = "${upstream_ref_ref}" ]; then
      >&2 echo "Start identified by 2-0 vote: both '${pw_tag_applied}'" \
        "tag and upstream '${upstream_ref}' branch agree."

      starting_ref="${pw_tag_ref}"
    else
      # We use merge-base vs. more complicated must_confirm_commit_at_or_behind_commit.
      local ancestor_sha
      ancestor_sha="$(git merge-base "${pw_tag_ref}" "${upstream_ref_ref}")"

      if [ "${ancestor_sha}" = "${pw_tag_ref}" ]; then
        >&2 echo "Start identified by upstream '${upstream_ref}' branch," \
          "because the '${pw_tag_applied}' is loafing behind."

        starting_ref="${upstream_ref_ref}"
      elif [ "${ancestor_sha}" = "${upstream_ref_ref}" ]; then
        >&2 echo "Start identified by '${pw_tag_applied}' tag (set by --apply)," \
          "which is ahead of the '${upstream_ref}' branch."

        starting_ref="${pw_tag_ref}"
      else
        # The pw/in tag and the upstream ref have diverged, which most
        # likely means user rebased past pw/in and then pushed. In the
        # --archive → --apply → --push → --pull use case, this is fine,
        # because the --pull/--archive host expects to rebase all the
        # commits in the --archive (on the --apply/--push host, there's
        # a pw/work tag that shows where the latest --apply started,
        # which is the commit to which the other host will reset).
        # - The caller verifies starting_sha visible from HEAD, which
        #   will verify it's not the upstream the diverged from HEAD.
        >&2 echo "ALERT: The '${pw_tag_applied}' tag and '${upstream_ref}'" \
          "upstream have diverged."
        >&2 echo "- Most likely, you rebased past '${pw_tag_applied}'" \
          "and then pushed, totally fine."

        starting_ref="${upstream_ref_ref}"
      fi
    fi
  else
    # Either or neither but not both pw_tag and upstream_ref.

    # Report why starting_ref picked.
    local picked_because=""

    if [ -n "${upstream_ref_ref}" ]; then
      >&2 echo "Start identified by upstream '${upstream_ref}' branch"
      picked_because="- no '${pw_tag_applied}' tag"
      starting_ref="${upstream_ref_ref}"
    else
      local scoping_branch="${SCOPING_REMOTE_BRANCH}"
      # If feature branch, use current branch name, e.g., 'entrust/<feature>'
      ${is_hyper_branch} || scoping_branch="${branch_name}"

      picked_because="- no remote branch '${SCOPING_REMOTE_NAME}/${scoping_branch}'"
      if ! ${is_hyper_branch}; then
        picked_because="${picked_because}\n- no remote branch '${remote_name}/${branch_name}'"
      fi
      picked_because="${picked_because}\n- no remote branch '${REMOTE_BRANCH_RELEASE}'"
      picked_because="${picked_because}\n- no local branch '${LOCAL_BRANCH_RELEASE}'"

      if [ -n "${pw_tag_ref}" ]; then
        >&2 echo "Start identified by '${pw_tag_applied}' tag"

        starting_ref="${pw_tag_ref}"
      else
        # Most likely, this is a new private-private project (like DepoXy Client),
        # and this is the first time the user is running this command.
        # - Unless this issue happens for other reasons, shouldn't need to
        #   confirm with user if okay to continue.
        >&2 echo "ALERT: Archiving from very first revision (root commit)"
        picked_because="- no '${pw_tag_applied}' tag\n${picked_because}"

        # CALSO: See also ${PUT_WISE_REBASE_ALL_COMMITS:-ROOT}
        # - But here we'll use the magic empty Git tree SHA.
        # - Note using $(git_first_commit_sha) won't work, because lhs
        #   commit in revision range passed to format-patch is exclusive.
        starting_ref="${GIT_EMPTY_TREE}"
      fi
    fi

    >&2 info "Start identified because:\n${picked_because}"
  fi

  echo "${starting_ref}"
}

# ***

identify_first_upstream_branch () {
  # USYNC: must_identify_rebase_base (pull) & identify_first_upstream_branch (archive)

  # "Return" variable.
  upstream_ref=""

  local branch_name=""
  local local_release=""
  local remote_release=""
  local remote_protected=""
  local remote_current=""
  local remote_name=""
  local rebase_boundary=""
  local already_sorted=false
  local already_signed=false
  # CXREF: ~/.kit/git/git-put-wise/lib/dep_rebase_boundary.sh
  if put_wise_identify_rebase_boundary_and_remotes \
    "${_action_desc:-archive}" "${_inhibit_exit_if_unidentified:-true}" \
  ; then
    # Identify first put-wise upstream: Check first for remote scoping
    # branch, then remote feature branch, then remote release branch,
    # then local release branch.

    # Note the identify fcn. sets remote strings if remote exists but
    # branch absent, i.e., if user can create new branch on push. So
    # here we also check if branch actually exists.
    if git_remote_branch_exists "${remote_protected}"; then
      # Exits 1 if diverged, or exits 0/11 if up-to-date or ahead of remote.
      must_confirm_upstream_shares_history_with_head "${remote_protected}" \
        ${_strict_check:-true}

      upstream_ref="${remote_protected}"
    elif git_remote_branch_exists "${remote_current}"; then
      must_confirm_upstream_shares_history_with_head "${remote_current}" \
        ${_strict_check:-true}

      upstream_ref="${remote_current}"
    elif git_remote_branch_exists "${remote_release}"; then
      # MAYBE: Ignore for feature branch if diverges from HEAD.
      must_confirm_upstream_shares_history_with_head "${remote_release}" \
        ${_strict_check:-true}

      upstream_ref="${remote_release}"
    elif git_branch_exists "${local_release}"; then
      # MAYBE: Ignore for feature branch if diverges from HEAD.
      must_confirm_upstream_shares_history_with_head "${local_release}" \
        ${_strict_check:-true}

      upstream_ref="${local_release}"
    fi
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# It's our convention that no branch publishes or shares its PRIVATE commits.
# - This mechanism is similar to a user deliberately managing their own
#   private branch, but without the hassle of manually of managing multiple
#   branches.
#   - Specifically, it lets the user mingle PRIVATE and non-PRIVATE commits
#     in the same branch, committing either at will.
#   - If the user were instead managing two branches separately, they might
#     find themselves often checking out the non-private branch to make the
#     non-PRIVATE commits. But then they'd likely return to 'private' and
#     rebase to receive those new commits, but also because they want the
#     'private' branch always checked out, so that's the code that's used
#     for whatever they're doing.
#   - The put-wise workflow, on the other hand, lets the user work from
#     the same branch throughout. The user can make both non-PRIVATE and
#     PRIVATE commits to the same branch as they work. When they're later
#     ready to push code upstream or to share with their other machines,
#     put-wise handles bubbling the PRIVATE commits atop all the rest, and
#     then moving the other branch's pointer to the last commit before the
#     start of the PRIVATE commits.
#   - This ia a "simple" strategy (in this author's opinion) for
#     intermingling public and private code, albeit one with a somewhat
#     prescriptive workflow that I expect anyone will need a moment (or
#     perhaps a diagram) to truly grok. Or maybe you'll just dive right
#     in, use the tool a few times, and then realize how it works, and
#     what problem it solves.

# Note that there's no reason *not* to allow PRIVATE commits in any
# branch, especially when pushing (who cares! we could rebase since
# upstream, and it wouldn't affect any branch but the local branch).
# But we choose, nay, we deem this practice inferior.
# - The branch name 'private' should be a signal to the user that the
#   branch contains PRIVATE commits. We could allow the user to have
#   PRIVATE commits in, say, a branch named 'release', and if they
#   always used git-put-wise, they'd have no problems. But what if
#   they forgot to use put-wise? What if they saw the branch name
#   'release' and felt free to `git pr` (the author's alias to
#   `git push release release`)? They might inadvertently publish
#   PRIVATE commits because they mistook the 'release' branch name
#   to mean that all commits were okay to publish.
#   - As such, put-wise doesn't allow this practice. If the user
#     wants to use PRIVATE commits, they should do so from a branch
#     named 'private', and then at least they'll avoid not knowing
#     which branches include PRIVATE commits.

# Here we identify the final commit before PRIVATEs start, falling back
# on HEAD if this branch does not contain any PRIVATE commits.
identify_commit_range_end () {
  local branch_name
  branch_name="$(git_branch_name)"

  # Find the latest non-PRIVATEly-scoped commit.
  # - Not using determine_scoping_boundary, because the --archive
  #   may contain PROTECTED commits, but not PRIVATE.
  commit_range_end="$(find_oldest_commit_by_message "^${PRIVATE_PREFIX}")"

  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ]; then
    # A 'private' branch doesn't publish its PRIVATE commits.
    if [ -n "${commit_range_end}" ]; then
      # Use parent, because format-patch (and diff) includes the
      # ending commit in the output.
      commit_range_end="${commit_range_end}^"
    else
      commit_range_end="HEAD"
    fi
  elif [ -n "${commit_range_end}" ]; then
    # A branch not named 'private' contains PRIVATE commits.
    # - See comment afore this function for reasoning why this is discouraged.
    >&2 echo "ERROR: The branch named “${branch_name}” contains PRIVATE commits."
    >&2 echo "- Please keep your PRIVATEs to a “${LOCAL_BRANCH_PRIVATE}” branch."
    >&2 echo "- (This is a convention for your own good, so that when you see the "
    >&2 echo "   branch name, you are reminded that the branch contains PRIVATEs.)"
    >&2 echo "- Hint: If you are worried that you might accidentally \`git push\` to"
    >&2 echo "  a non-private upstream, set git-push to always require a refspec:"
    >&2 echo
    >&2 echo "    git config push.default nothing"
  
    exit_1
  else
    commit_range_end="HEAD"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_have_non_empty_rev_range_not_already_tagged () {
  local starting_ref="$1"
  local commit_range_end="$2"
  local pw_tag_applied="$3"
  local pw_tag_archived="$4"

  # Note that we elevensesied already if starting_ref → HEAD, so we
  # at least know that reference is not HEAD (and we also know that
  # a commit_range_end was also identified).
  # - The range lhs, aka 'from'.
  local archive_from="$(git_commit_object_name "${starting_ref}")"
  # However, we have not verified if archive_upto → archive_from, which
  # means all commits since pw/in are PRIVATE commits.
  # - The range rhs, aka 'upto'.
  local archive_upto="$(git_commit_object_name "${commit_range_end}")"

  debug "archive_from ${archive_from} / archive_upto ${archive_upto}"

  # If archive bounds are the same, means only PRIVATE..HEAD.
  if [ "${archive_from}" = "${archive_upto}" ]; then
    >&2 echo "Nothing to do: Only PRIVATE commits since previous archive"

    exit_elevenses
  fi

  # If pw/<branch>/out tag exists, means --archive was run more recently than
  # --apply or --pull, because --apply/--pull removes the pw/<branch>/out tag.
  # - The pw/in tag, created on --apply, also aka 'from'
  local in_tag
  in_tag="$(git_tag_object_name "${pw_tag_applied}")" || true
  # - The pw/out tag, created on --archive, also aka 'upto'.
  local out_tag
  out_tag="$(git_tag_object_name "${pw_tag_archived}")" || true

  debug "in_tag ${in_tag:-<empty>} / out_tag ${out_tag:-<empty>}"

  if [ -n "${in_tag}" ]; then
    # It's okay if there's a pw/in tag but no pw/out tag: the --apply or --pull
    # command removes the pw/out tag when it sets pw/in. So this would mean
    # first time --archiving since most recent --apply/--pull.
    if [ -z "${out_tag}" ]; then
      >&2 info "Welcome back to the --archive."
    # Check if in and out tags are at same commit, dunno why we're care,
    # doesn't matter to us, but put-wise would-should never do the (the
    # [ "${archive_from}" = "${archive_upto}" ] above prevents it). But
    # I guess if you want to detect if you're in a simulation, you need
    # to perform pointless tests of your surroundings.
    elif [ "${in_tag}" = "${out_tag}" ]; then
      >&2 warn "Why are the two put-wise twist tags having a party on the same commit?"
    fi
    # You'll notice that the pw/in tag and the 'entrust/scoping' branch
    # are usually the same, if the remote branch exists. Also, the 'from'
    # commit is usually determined to be 'entrust/scoping', if the remote
    # branch exists, or it's pw/in. So it'd be odd if the tag and the
    # remote branch were not the same.
    if [ "${in_tag}" != "${archive_from}" ]; then
      >&2 warn "The '${pw_tag_applied}' tag is not the same as" \
        "the archive starting commit we determined: '${starting_ref}'."
    fi
  fi

  if [ -n "${out_tag}" ]; then
    # If one, then both, so say we all. (Though not commutative, if only
    # pw/in, then who cares pw/out; but if pw/out, then most def. pw/in.)
    if [ -z "${in_tag}" ]; then
      # This case is fine, really: The pw/out tag is for user eyes only. The
      # --archive command doesn't use it, it just sets the tag on success.
      # And the pw/in tag is also created on sucess (used starting_ref, which
      # is one of 'entrusted/scoping', 'publish/release', 'release', or the
      # first-commit).
      # - But this case would probably mean user tampering, because put-wise
      #   won't leave a pw/out tag without a pw/in tag (though it will leave
      #   an in tag without an out tag).
      >&2 warn "The '${pw_tag_archived}' tag exists, but not '${pw_tag_applied}'."
    fi
    # Here we expect old upto tag to be at or behind now-ly identified archive-upto.
    # - Diverged is also okay, means user rebased their work, don't care.
    local divergent_ok=true

    # ${divergent_ok} "out-tag" "archive-upto"
    if ! must_confirm_commit_at_or_behind_commit "${out_tag}" "${archive_upto}" \
      ${divergent_ok} "${pw_tag_archived}" "archive-upto" \
    ; then
      >&2 warn "The '${pw_tag_archived}' tag is behind or not at (diverged from)" \
        "the archive-upto-ref we determined: '${archive_upto}'."
    fi
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

compose_filenames () {
  local starting_ref="$1"
  local projpath_sha="$2"
  local commit_range_end="$3"

  hostname_sha="$(print_sha "$(hostname)")"

  starting_sha=$(git rev-parse --short=${PW_SHA1SUM_LENGTH} "${starting_ref}")

  endingat_sha=$(git rev-parse --short=${PW_SHA1SUM_LENGTH} "${commit_range_end}")

  local now

  now=$(date +%Y_%m_%d_%Hh%Mm%Ss)

  crypt_name="${hostname_sha}--${projpath_sha}--${starting_sha}--${endingat_sha}--${now}"

  local encoded_br="$(branch_name_path_encode "$(git_branch_name)")"

  patch_name="${crypt_name}--${encoded_br}--$(basename -- "$(pwd)")"

  temp_dir="$(mktemp -d /tmp/$(basename -- "$0")-XXXXXXX)"
  [ ! -d "${temp_dir}" ] && >&2 echo "ERROR: \`mktemp\` failed" && exit_1 || true

  patch_dir="${temp_dir}/${patch_name}"

  mkdir "${patch_dir}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_produce_nonempty_patch () {
  local starting_ref="$1"
  local commit_range_end="$2"
  local patch_dir="$3"

  # ALTLY: To include root commit in format-patch:
  # - Use magic empty tree SHA:
  #     ${GIT_EMPTY_TREE}..${commit_range_end}
  # - Or use --root option:
  #     --root ${commit_range_end}
  # Because git-diff doesn't have a --root option, caller sets
  # starting_ref to empty tree SHA if root should be included.
  local rev_range="${starting_ref}..${commit_range_end}"

  # Exclude the signature, which defaults to appending a double-dash
  # and the Git version to the patch file. E.g.,
  #   --
  #   2.46.1
  # and sometimes this ends up in the commit message.
  # - SAVVY: Normally these two lines are ignored, but for empty commits
  #   (e.g., via `git am --empty=keep`, or `git am --allow-empty`), the
  #   two lines are added to the commit message.

  git -c diff.noprefix=false format-patch -q --no-signature -o "${patch_dir}" ${rev_range}

  if [ -z "$(command ls -A "${patch_dir}")" ]; then
    >&2 echo -e "Unexpected: Nothing archived! Try:\n" \
      " git diff ${rev_range}"

    exit_1
  fi

  # Tell the other side what project this is.
  # - Note that ${project_path} might be relative,
  #   but that we're currently in that directory.
  local homely_path
  homely_path=$(home_agnostic_current_path)

  echo "${homely_path}" > "${patch_dir}/${PW_ARCHIVE_MANIFEST:-.manifest.pw}"
}

home_agnostic_current_path () {
  pwd -L | sed "s#^${HOME}/#\$HOME/#" 
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# tar notes:
# - xz is only slightly smaller than gz, at least for small patch archives,
#   e.g., 6.3K vs 6.7K. But for larger inputs, e.g., compressing 26M DepoXy
#   working tree, xz 11M vs. gz 16M, nor we're talking decent improvement.
# - Specify files to pack using relative path, not absolute, lest message:
#     tar: Removing leading '/' from member names
#   Also tar unpacks according to the paths you use when packing.
encrypt_archive_and_cleanup () {
  local success=true

  cd "${temp_dir}"

  tar -cJf "${cleartext_name}" "${patch_name}"

  local crypt_path
  crypt_path="${PW_PATCHES_REPO}/${crypt_name}"

  encrypt_asset "${crypt_path}" "${cleartext_name}" || success=false

  # Aka `cd "${before_cd}"`.
  # - Not that it matters: Called in a subshell.
  cd - > /dev/null

  # Cleanup.
  remove_temp_files \
    || return 1

  if ${success}; then
    printf "${crypt_path}"
  else
    return 1
  fi
}

# ***

remove_temp_files () {
  [ -z "${cleartext_name}" ] && >&2 echo "ERROR: cleartext_name unset!" && return 1 || true
  [ -z "${temp_dir}" ] && >&2 echo "ERROR: temp_dir unset!" && return 1 || true
  ${DRY_ECHO} command rm -f "${cleartext_name}"
  ${DRY_ECHO} command rm -rf "${temp_dir}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_not_already_be_archived () {
  local crypt_name="$1"
  local hostname_sha="$2"
  local projpath_sha="$3"
  local starting_sha="$4"
  local endingat_sha="$5"

  local before_cd="$(pwd -L)"

  cd "${PW_PATCHES_REPO}"

  local matching_archives
  matching_archives="$(print_repo_archive_list "" ":!:${crypt_name}" |
    grep -e "^${hostname_sha}[[:xdigit:]]*--${projpath_sha}[[:xdigit:]]*--${starting_sha}[[:xdigit:]]*--${endingat_sha}[[:xdigit:]]*--.*"
  )" || true

  if [ -n "${matching_archives}" ]; then
    >&2 echo "Nothing to do: Archive already exists: $(echo ${matching_archives} | head -1)"

    exit_elevenses
  fi

  cd "${before_cd}"

  return 0
}

# ***

maybe_remove_outdated_archives () {
  local crypt_name="$1"
  local hostname_sha="$2"
  local projpath_sha="$3"
  local starting_sha="$4"

  local outdated

  # See also: print_repo_archive_list.
  outdated="$(print_repo_archive_list "" ":!:${crypt_name}" |
    grep -e "^${hostname_sha}[[:xdigit:]]*--${projpath_sha}[[:xdigit:]]*--${starting_sha}[[:xdigit:]]*--.*"
  )" || true

  if maybe_confirm_remove_outdated_archives "${crypt_name}" "${outdated}"; then
    remove_outdated_archives "${outdated}"
  fi

  return 0
}

maybe_confirm_remove_outdated_archives () {
  local crypt_name="$1"
  local outdated="$2"

  [ -n "${outdated}" ] || return 1

  echo "- The repo contains outdated archive(s) for the same project:"
  echo "${outdated}" | sed "s/^/    /"
  echo "  The new archive will be:"
  echo "    ${crypt_name}"
  printf "Would you like to remove the outdated archive(s)? [Y/n] "

  local key_pressed
  local opt_chosen
  prompt_read_single_keypress "y" "n"

  [ "${opt_chosen}" = "y" ] && return 0 || return 1
}

remove_outdated_archives () {
  local outdated="$1"

  local ux_prefix="- "

  local archive
  while IFS= read -r archive; do
    [ -z "${archive}" ] && >&2 echo "ERROR: 'archive' unset!" && exit_1 || true

    echo "${ux_prefix}git rm -q \"${archive}\""
    ${DRY_ECHO} git rm -q "${archive}"

    ux_prefix="  "
  done <<< "${outdated}"

  commit_changes_and_counting
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

add_archive_to_repo () {
  local crypt_name="$1"

  local before_cd
  before_cd="$(pwd -L)"

  cd "${PW_PATCHES_REPO}"

  ${DRY_ECHO} git add "${crypt_name}"

  commit_changes_and_counting

  cd "${before_cd}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# git-tag is quiet if tag doesn't exist, otherwise `git tag -f`
# will print, e.g., "Updated tag 'tagname' (was c5c32a3)".
update_archive_tags () {
  local pw_tag_applied="$1"
  local starting_sha="$2"
  local pw_tag_archived="$3"
  local endingat_sha="$4"

  echo "  git tag -f \"${pw_tag_applied}\" \"${starting_sha}\""
  git tag -f "${pw_tag_applied}" "${starting_sha}" > /dev/null

  echo "  git tag -f \"${pw_tag_archived}\" \"${endingat_sha}\""
  git tag -f "${pw_tag_archived}" "${endingat_sha}" > /dev/null
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

report_success () {
  local crypt_path="$1"

  echo "Prepared patchkage: ${crypt_path}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
  >&2 echo "😶"
fi

