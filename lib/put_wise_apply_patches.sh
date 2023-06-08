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

# ASSUMED: Within the put-wise patches repo, each of the Git files
# (ls-files) should be a GPG archive containing one or more patch files
# from the format-patch command for a specific project. And that archive
# should contain a manifest (metafile) specifying that project's path.
# - The decrypted and unpacked archives are never added to the repo.
# - *ASSUMED* because we expect put-wise manages the patches repo.
#   So we don't expect what we don't expect.

# ***

# ITSCOMPLICATED: Unlike the similar-ish `put_wise_pull_remotes`, for
# each project, we cannot do something "easy" like `git rebase --onto`,
# because `--onto` works on a specific branch, and not on a set of
# patch files.
# - So we might use an ephemeral intermediate branch on which to apply
#   those patches, and then we can rebase on top of that.
#   - But we'll only need such an intermediate branch if the project
#     has PRIVATE commits that need to stay ahead of other work. This
#     is so we apply the patches on commits before PRIVATE commits.

# ***

# This function implements 2 of the 5 put-wise actions,
# --apply and --apply-all. It's also the only action
# that doesn't assume PW_PROJECT_PATH is a path to a git
# project (and that's not a path to patches repo).
# - PW_PROJECT_PATH might be a legit project directory path;
#   or it might be a path to an archive file in PW_PATCHES_REPO;
#   or it might be empty if --apply-all.
put_wise_apply_patches () {
  ${PW_OPTION_DRY_RUN} && DRY_RUN="${DRY_RUN:-__DRYRUN}"

  local before_cd="$(pwd -L)"

  if ${PW_ACTION_APPLY_ALL}; then
    put_wise_apply_patches_apply_all
  else
    # else, ${PW_ACTION_APPLY}.
    put_wise_apply_patches_apply_one
  fi

  cd "${before_cd}"
}

put_wise_apply_patches_apply_all () {
  cd "${PW_PATCHES_REPO}"

  if [ -n "${PW_PROJECT_PATH}" ]; then
    info "So, what? --apply-all doesn't care about your -J/--project-path {path}."
  fi

  if [ -n "${PW_OPTION_BRANCH}" ]; then
    info "So, what? --apply-all doesn't care about your -b/--branch {name}."

    PW_OPTION_BRANCH=""
  fi

  if [ -n "${PW_OPTION_REGENERATE_RECEIPTS}" ]; then
    >&2 echo "ERROR: -g/--regenerate option only works on --apply"

    exit 1
  fi

  local projects_patched=()

  unpack_apply_all_patchkages

  echo
  echo "Congratulations, you've updated the following projects:"
  for project in "${projects_patched[@]}"; do
    echo "  ${project}"
  done
}

put_wise_apply_patches_apply_one () {
  local gpgf=""

  local patch_dir_exists=false

  if [ -z "${PW_PROJECT_PATH}" ] || [ -d "${PW_PROJECT_PATH}" ]; then
    # User wants to apply patches to a specific project, so we
    # need to find a patch archive file for that project path
    # (which defaults to current directory ".".
    must_verify_project_path_and_not_patches_repo
    if [ -n "${PW_OPTION_REGENERATE_RECEIPTS}" ]; then
      # Egregious short-circuit return (exit!) branch, my bad.
      fake_the_return_receipt

      exit 0
    fi
    gpgf="$(must_find_one_patches_archive_for_project_path_and_print)" || exit $?
    # The last function also exit's 0 and prints nothing, handled separately.
    [ -n "${gpgf}" ] || exit 0
    unpack_target_is_not_nonempty_else_info_stderr "${gpgf}" || patch_dir_exists=true
  elif [ -f "${PW_PROJECT_PATH}" ]; then
    # User specified a specific archive file.
    gpgf="${PW_PROJECT_PATH}"
  else
    fatal "What am I looking at? Neither file nor directory: “${PW_PROJECT_PATH}”"
  fi

  # If here and --regenerate, means user did not specify project path.
  if [ -n "${PW_OPTION_REGENERATE_RECEIPTS}" ]; then
    >&2 echo "ERROR: No project path specified for -g/--regenerate option."

    exit 1
  fi

  cd "${PW_PATCHES_REPO}"

  must_verify_patches_repo_archive "${gpgf}"

  local skip_if_decrypted=false
  # DEVs: A little speed bump, just for you.
  #  skip_if_decrypted=true

  if ! ${patch_dir_exists} || ! ${skip_if_decrypted}; then
    decrypt_and_unpack_patchkage "${gpgf}"
  fi
  process_patch_archive "${gpgf}"
}

decrypt_and_unpack_patchkage () {
  local gpgf="$1"

  local progress_msg="Unpacking archive “${gpgf}”... "
  printf "${progress_msg}"

  # If asset previously unpacked, tar will print 'x path/to/file' to
  # stderr for each file that's already unpacked that it skips. So
  # combine streams so we can count lines.
  local unpacked
  unpacked="$(decrypt_asset "${gpgf}" | tar xvJ 2>&1)"

  # Clear the line.
  printf "\r$(echo "${progress_msg}" | sed 's/./ /g')\r"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_verify_project_path_and_not_patches_repo () {
  local before_cd="$(pwd -L)"

  # Side effect: `cd`'s, and updates PW_PROJECT_PATH, to canonicalize.
  # - This function only cares about canonicalizing, to compare against
  #   patches repo path.
  must_cd_project_path_and_verify_repo

  must_not_be_patches_repo_or_hint_and_exit

  cd "${before_cd}"
}

must_not_be_patches_repo_or_hint_and_exit () {
  if ! must_not_be_patches_repo; then
    >&2 echo "- HINT: To unpack and apply a specific archive, specify its path."
    >&2 echo "  - Or to unpack and apply all archives, use --apply-all."

    exit 1
  fi
}

# ***

must_find_one_patches_archive_for_project_path_and_print () {
  local projpath_sha="$(print_project_path_ref)"

  local hostname_sha
  hostname_sha="$(print_sha "$(hostname)")"

  local before_cd="$(pwd -L)"

  cd "${PW_PATCHES_REPO}"

  local repo_matches

  repo_matches="$(print_repo_archive_list "" ":!:${hostname_sha}*" |
    grep -e "^[[:xdigit:]]\+--${projpath_sha}[[:xdigit:]]*--[[:xdigit:]]\+--.*"
  )"

  cd "${before_cd}"

  if [ -z "${repo_matches}" ]; then
    >&2 debug "Nothing found in patches repo matching project “${projpath_sha}”"
    >&2 debug "- For project path: $(pwd -L)"
    >&2 echo "Nothing to do: No matching archive found for this repo"

    ${PW_OPTION_FAIL_ELEVENSES:-false} && exit ${PW_ELEVENSES} || exit 0
  fi

  if [ $(echo "${repo_matches}" | wc -l) -ne 1 ]; then
    >&2 echo "ERROR: Too many matching archives found for this repo:"
    >&2 echo "${repo_matches}"

    exit 1
  fi

  local one_match="${repo_matches}"

  printf "${one_match}"
}

unpack_target_is_not_nonempty_else_info_stderr () {
  local gpgf="$1"

  local nonempty=0

  local before_cd="$(pwd -L)"

  cd "${PW_PATCHES_REPO}"

  # See if there's already an unpacked path. We actually don't care,
  # we'll totally clobber it (well, `tar` overwrites existing files,
  # but lets other files be). In any case, we assume that user only
  # uses put-wise to manage patches repo, so we choose to vet less.
  local patch_dirs
  patch_dirs="$(/bin/ls -A1d "${gpgf}"--* 2> /dev/null)"

  if [ -n "${patch_dirs}" ]; then
    nonempty=1

    >&2 info "Existing Decrytped and Unpacked Patchkage might be overwritten," \
      "or not:\n  ${patch_dirs}"
  fi

  cd "${before_cd}"

  return ${nonempty}
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

unpack_apply_all_patchkages () {
  unpack_all_encrypted_patchkage_archives

  apply_all_decrypted_unpacked_patchkages
}

# ***

# First pass: Iterate over the GPG *patchkages*,
# and unpack (*unpatchk*?) each one.
unpack_all_encrypted_patchkage_archives () {
  local gpgf

  # BWARE: If unpacked path already exists, tar overwrites silently.
  while IFS= read -r -d $'\0' gpgf; do
    decrypt_and_unpack_patchkage "${gpgf}"
  done < <(print_repo_archive_list "-z")
}

# ***

# Second pass: Process each unpacked *patchkage*.
apply_all_decrypted_unpacked_patchkages () {
  local gpgf

  local patchkages=()

  # Build a list of archives to process. Note that we don't process
  # the archives within the while loop, because the while loop uses
  # stdin, which prevents us from being able to prompt the user.
  while IFS= read -r -d $'\0' gpgf; do
    patchkages+=("${gpgf}")
  done < <(print_repo_archive_list "-z")

  for gpgf in "${patchkages[@]}"; do
    process_patch_archive "${gpgf}"
  done
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Process the indicated archive, given its obscured packed name:
# This code simply looks for a directory name with the same prefix.
process_patch_archive () {
  local gpgf="$1"

  debug "Scanning for unpacked “${gpgf}”"

  # Cwd is ${PW_PATCHES_REPO}.
  local before_cd="$(pwd -L)"

  local patch_dir
  patch_dir="$(must_find_path_starting_with_prefix_dash_dash "${gpgf}")"

  debug "Processing patches: ${patch_dir}"

  # Check that the match is a directory, if not, smells like DEV issue.
  if [ ! -d "${patch_dir}" ]; then
    >&2 echo "ERROR: Unexpectedly found that “${patch_dir}” is not a directory."

    exit 1
  fi

  local ret_rec_crypt_path="${gpgf}${PW_RETURN_RECEIPT_CRYPT}"

  local retval=0
  local ret_rec_plain_name
  # Note the OR-ing disables errexit for nonzero return, but not exit.
  # - (Though `$(subprocess) || retval=$?` would prevent `exit`.)
  process_unpacked_patchkage "${patch_dir}" || retval=$?

  if [ ${retval} -eq 0 ]; then
    prepare_return_receipt_encrypt "${ret_rec_crypt_path}" "${ret_rec_plain_name}"

    # This exists on certain errors.
    remove_archive_from_git "${gpgf}" || retval=$?
  fi

  # If process_unpacked_patchkage "failed", it may not have cd'd back.
  cd "${before_cd}"

  remove_plaintext_assets "${patch_dir}" "${ret_rec_plain_name}"

  if [ ${retval} -ne 0 ]; then
    [ ${retval} -ne ${PW_ELEVENSES} ] || return 0

    return ${retval}
  fi

  return 0
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Process the patches in the indicated unpacked archive directory.
#
# BWARE: Because this function runs on the left side of ||, Bash
# (because POSIX) dishonors errexit within the function. So just
# be aware you gotta handle all expected errors. The code will
# otherwise keep running.
process_unpacked_patchkage () {
  local patch_dir="$1"

  local before_cd="$(pwd -L)"

  cd "${patch_dir}"

  # Split directory name on double-spines.
  # E.g., patch_dir="95ac8e9e8750--f5f9abba0151--2022_10_28_19h19m41s--private--git-put-wise".
  # - Note that the project name is last, because it might contain '--'.
  #   As such, a simple `sed` is inadequate, e.g.,
  #     set -- $(echo "${patch_dir}" | sed 's/\-\-/ /g')
  #   So we'll use Python to limit the substitution count.
  # set -- $(python -c "
  #   import re;
  #   print(
  #     re.sub(
  #       '\-\-',
  #       ' ',
  #       '${patch_dir}',
  #       count=5
  # ))")
  set -- $(split_on_double_dash "${patch_dir}" 6)
  local hostname_sha="$1"
  local projpath_sha="$2"
  local starting_sha="$3"  # If remote pulls (not applies), matches one of ours.
  local endingat_sha="$4"  # Not used/relevant to us.
  local timestamp_id="$5"
  local remoteish_br_encoded="$6"
  local project_name="$7"
  # Note that we don't care about project_name, but we'll use, and eventually
  # validate, the other values, starting_sha, timestamp_id, and patch_branch.

  local remoteish_br="$(branch_name_path_decode "${remoteish_br_encoded}")"

  local patch_path="$(pwd -L)"

  local project_path
  project_path="$(must_determine_project_path_from_meta_file "${patch_dir}")"

  local patch_branch="${PW_OPTION_BRANCH:-${remoteish_br}}"

  local ephemeral_branch="$(format_pw_tag_ephemeral_apply "${patch_branch}")"

  cd "${project_path}"

  projects_patched+=("${project_path}")

  print_applying_onto_progress "${patch_path}" "${project_path}"

  git_insist_git_repo

  git_insist_not_applied "${patch_branch}" "${starting_sha}"

  # Insist that the ephemeral branch does not exist.
  must_insist_ephemeral_branch_does_not_exist "${ephemeral_branch}"

  local local_projpath_sha="$(print_project_path_ref)"
  must_confirm_projpath_sha_identical "${projpath_sha}" "${local_projpath_sha}"

  # ***

  if ! prompt_user_and_change_branch_if_working_branch_different_patches \
    "${patch_dir}" "${patch_branch}" "${project_path}" "${patch_path}"; \
  then
    ${PW_OPTION_FAIL_ELEVENSES:-false} && return ${PW_ELEVENSES} || return 0
  fi

  # ***

  # If we changed branches, we committed changes into the previous branch.
  # - Otherwise, commit uncommitted changes now, which we pop post-rebase.

  local pop_after=false
  pop_after=$(maybe_stash_changes)

  # Reset to this branch after maybe using ephemeral branch. (We don't
  # set this value before prompting user to change branches, because we
  # told them that's what we wanted to do (and we didn't tell them we'd
  # switch back). That function also has an await that allows the user
  # to create a local branch if they need, in which case it was the user 
  # who changed the branch, another reason not to set it back.)
  local working_branch="$(git_branch_name)"

  # Ah, memories.
  local old_head="$(git_commit_object_name)"
  echo "whose HEAD is at:"
  echo "  ${working_branch} $(shorten_sha ${old_head})"

  # Check for a return receipt, so "remote" branch pointer up to date.
  process_return_receipts "${projpath_sha}"

  # ***

  # We prefer to apply patches atop the starting_sha, because there
  # will be no conflicts with the patches. And then we rebase local
  # work on top of the patches.

  # The starting_sha represents a commit in the remote's history.
  # - If the remote --pull's code, that commit is also in the local
  #   history.
  # - But if local and the remote share code via --archive/--apply,
  #   then there are no shared IDs, and we look for the pw-upto tag.
  # - When neither matching SHA, nor tag, offer to use scoping boundary
  #   (or HEAD), but confirm with user.

  # E.g., 'pw/private/in'
  local pw_tag_applied="$(format_pw_tag_applied "${patch_branch}")"
  # E.g., 'pw/private/out'
  local pw_tag_archived="$(format_pw_tag_archived "${patch_branch}")"
  # E.g., 'pw/private/work'
  local pw_tag_starting="$(format_pw_tag_starting "${patch_branch}")"

  local patch_base=""
  # (lb): I don't normally set variables using Bash's loose variable scoping,
  # but this function prints progress and might prompt user, so it needs stdout.
  # But I want to have the patch_base "passed" back, meaning we cannot call
  # patch_base="$(subprocess)".
  choose_patch_base_or_ask_user "${starting_sha}" "${pw_tag_applied}" \
    "${PW_TAG_ONTIME_APPLY}"

  # ***

  # Run some checks, then create and checkout ephemeral branch.
  if ! ephemeral_branch="$(\
    prepare_ephemeral_branch_if_commit_scoping "${ephemeral_branch}" "${patch_base}"
  )"; then
    maybe_unstash_changes ${pop_after}

    return 1
  fi

  # - Remember that errexit not in effect, so dying deliberately.
  #   - Though makes me wonder if convention of relying on errexit to die
  #     is lazy and sloppy. Even how `return 1` can kill the script. It's
  #     definitely not a programming language best practice.
  if ! git check-ref-format --branch "${ephemeral_branch}"; then
    maybe_unstash_changes ${pop_after}

    return 1
  fi

  # ***

  apply_patches_unless_dry_run "${patch_path}" "${working_branch}"

  local last_patch="$(git_commit_object_name)"

  local rev_count
  rev_count="$(git_number_of_commits)"

  rebase_working_atop_ephemeral_branch "${working_branch}" "${ephemeral_branch}"

  cleanup_ephemeral_branch "${ephemeral_branch}"

  maybe_unstash_changes ${pop_after}

  add_patch_history_tags "${old_head}" "${last_patch}" "${patch_branch}" \
    "${starting_sha}" "${patch_base}"

  manage_pw_tracking_tags "${pw_tag_applied}" "${pw_tag_archived}" \
    "${last_patch}" "${pw_tag_starting}" "${patch_base}"

  # NOTE: We don't need ${project_name} to process the return receipt, but
  #       having a third set of dashes makes `/bin/ls -A1d "${gpgf}"--*`
  #       more shareable between archives and return receipts processing.
  # NOTE: Using ${remoteish_br} (what archive says),
  #       not ${patch_branch} (what user could say using --branch option).
  #
  # BWARE: The ${gpgf}-- prefix is how process_returns_receipts_ finds the
  #   unpacked receipt. CXREF: must_find_path_starting_with_prefix_dash_dash.
  #   - CXREF: crypt_name=, in --archive's compose_filenames.
  # - CXREF: See also other `  ret_rec_plain_name=`.
  ret_rec_plain_name="${hostname_sha}--${projpath_sha}--${starting_sha}--${endingat_sha}--${timestamp_id}${PW_RETURN_RECEIPT_PLAIN}--${remoteish_br_encoded}--${project_name}"

  # Just so we end up where we started, so to speak.
  cd "${before_cd}"

  prepare_return_receipt_hydrate "${rev_count}" "${ret_rec_plain_name}" \
    "${patch_branch}" "${starting_sha}" "${last_patch}"
}

# ***

fake_the_return_receipt () {
  local project_path="${PW_PROJECT_PATH}"

  if [ ! -d "${PW_PROJECT_PATH}" ]; then
    # I don't think this branch is possible.
    >&2 echo "ERROR: Please specify the project path."

    exit 1
  fi

  # Without the original archive, this script doesn't know what IDs to use
  # to recreate the return receipt or its filename.
  # - Some of the IDs, like the starting_sha and endingat_sha, are meaningless
  #   after --apply, but they're used in the return-receipt filename. This was
  #   probably as a convenience when debugging, so the DEV (me) could tell
  #   which encrypted receipt file belongs with which archive, but it's not
  #   necessary. Only the first two components, the host SHA and the project
  #   SHA (and later, we'll add the branch SHA), are used when the remote
  #   processes the receipt.
  local gpgf="${PW_OPTION_REGENERATE_RECEIPTS}"

  # Strip trailing receipt extension suffix, if exists.
  # - Use case: User copy-pastes existing receipt filename.
  gpgf="$(echo "${gpgf}" | sed "s/${PW_RETURN_RECEIPT_CRYPT}$//")"

  # Grab the first component off the encrypted file name, which is the host SHA.
  local hostname_sha
  hostname_sha="$(echo "${gpgf}" | sed 's/^\([^-]\+\)--.*/\1/')"
  # echo "hostname_sha: ${hostname_sha}"

  if [ -z "${hostname_sha}" ]; then
    >&2 echo "ERROR: Could not determine hostname SHA from: ${gpgf}"

    exit 1
  fi

  local starting_sha
  starting_sha="$(echo "${gpgf}" | sed 's/--/ /g' | awk '{ print $3 }')"
  # echo "starting_sha: ${starting_sha}"

  local before_cd="$(pwd -L)"
  cd "${project_path}"

  # We could also parse this from ${gpgf}.
  #  local projpath_sha="$(print_project_path_ref)"
  projpath_sha="$(echo "${gpgf}" | sed 's/--/ /g' | awk '{ print $2 }')"
  # echo "projpath_sha: ${projpath_sha}"

  # MEH: Who knows if this is the correct branch. The -g/--regenerate
  # option is already kinda weird (and not documented), so we'll just
  # trust the user had the branch set where it needs to be.
  local remoteish_br
  remoteish_br="$(git_branch_name)"
  # echo "remoteish_br: ${remoteish_br}"

  local remoteish_br_encoded
  remoteish_br_encoded="$(branch_name_path_encode "${remoteish_br}")"

  local project_name
  project_name="$(basename "$(pwd)")"
  # echo "project_name: ${project_name}"

  local ret_rec_plain_name
  # BWARE: The ${gpgf}-- prefix is how process_returns_receipts_ finds the
  #   unpacked receipt. CXREF: must_find_path_starting_with_prefix_dash_dash.
  #   - CXREF: crypt_name=, in --archive's compose_filenames.
  # - CXREF: See also other `ret_rec_plain_name=`.
  ret_rec_plain_name="${gpgf}${PW_RETURN_RECEIPT_PLAIN}--${remoteish_br_encoded}--${project_name}"
  echo "ret_rec_plain_name/1: ${ret_rec_plain_name}"

  local last_patch_tag
  last_patch_tag="refs/tags/$(format_pw_tag_applied "${remoteish_br}")"
  # echo "last_patch_tag: ${last_patch_tag}"

  local rev_count
  rev_count="$(git_number_of_commits "${last_patch_tag}")"
  # echo "rev_count: ${rev_count}"

  local last_patch
  last_patch="$(git_commit_object_name "${last_patch_tag}" "--short=${PW_SHA1SUM_LENGTH}")"
  # echo "last_patch: ${last_patch}"

  cd "${PW_PATCHES_REPO}"

  prepare_return_receipt_hydrate "${rev_count}" "${ret_rec_plain_name}" \
    "${remoteish_br}" "${starting_sha}" "${last_patch}"

  local ret_rec_crypt_path="${gpgf}${PW_RETURN_RECEIPT_CRYPT}"

  prepare_return_receipt_encrypt "${ret_rec_crypt_path}" "${ret_rec_plain_name}"

  remove_plaintext_assets_file "${ret_rec_plain_name}"

  cd "${before_cd}"
}

# ***

must_determine_project_path_from_meta_file () {
  local patch_dir="$1"

  local meta_file="${PW_ARCHIVE_MANIFEST:-.manifest.pw}"
  if [ ! -f "${meta_file}" ]; then
    >&2 echo "ERROR: No meta file found at “${meta_file}” for “${patch_dir}”"

    exit 1
  fi

  local project_path
  project_path="$(cat "${meta_file}" | head -1)"

  # The project path is home-agnostic, and almost definitely starts with
  # $HOME (unless you put-wise'd some path outside home?). Rather than use
  # simple yet possibly deadly `eval echo ${project_path}`, sed-expand it.
  project_path="$(echo "${project_path}" | sed "s#^\$HOME/#${HOME}/#")"

  if [ ! -d "${project_path}" ]; then
    >&2 echo "ERROR: Invalid project path “${project_path}” specified by “${patch_dir}”"

    # This seems like too serious an offense to keep processing.
    exit 1
  fi

  echo "${project_path}"
}

# ***

print_applying_onto_progress () {
  local patch_path="$1"
  local project_path="$2"

  local n_patches=$(/bin/ls -1d "${patch_path}"/*.patch | wc -l)

  echo "Applying ${n_patches} patch(es) from:"
  echo "  $(substitute_home_tilde ${patch_path})"
  echo "onto the project:"
  echo "  $(substitute_home_tilde ${project_path})"
}

# ***

# Before applying archive, look for tag with ${starting_sha}.
# - The tag has the format:
#     pw/<branch>/<apply-datetime>/starting/<starting-sha>
#   We know everything but the datetime, which we'll glob out.
git_insist_not_applied () {
  local patch_branch="$1"
  local starting_sha="$2"

  local tag_match="pw/${patch_branch}/*/apply/starting/${starting_sha}"

  local tagged_sha
  tagged_sha="$(git rev-parse --tags=${tag_match})"

  [ -n "${tagged_sha}" ] || return 0

  >&2 echo "ERROR: The incoming archive has already been applied, apparently!"
  >&2 echo
  >&2 echo "- Here's the start commit of the previous --apply,"
  >&2 echo "  found via '--tags=${tag_match}':"
  >&2 echo
  >&2 git --no-pager log -1 "${tagged_sha}"

  exit 1
}

# ***

must_confirm_projpath_sha_identical () {
  local archive_projpath_sha="$1"
  local local_projpath_sha="$2"

  [ "${archive_projpath_sha}" != "${local_projpath_sha}" ] || return 0
  
  # Smells like a dev error, if it's possible at all.
  # (I suppose the user could hack the manifest, but would they?)
  >&2 echo "ERROR: The path-ref's don't match:"
  >&2 echo "- Manifest (${PW_ARCHIVE_MANIFEST}) says: “${project_path}”."
  >&2 echo "- But that local path-sha (${local_projpath_sha})" \
    "!= archive path-sha (${archive_projpath_sha})."
  >&2 echo "- That is, the project_path path-ref is different from the archive path-ref."
  >&2 echo "This is likely a very rare error, and probably a DEV issue, i.e.," \
                                                      "it's not you, it's me."

  exit 1
}

# ***

# Not sure we need to, but prompt user if they were working on a different
# branch. I guess this makes sense, because in my DepoXy workflow I almost
# always work from the same long-living branch (e.g., 'private'). So if I
# was on another branch, and DepoXy switched to the $patch_branch and
# applied changes, I'd want to know not to expect that the patches were
# applied what was the active branch. Especially because this script
# should probably switch back to the previously active branch after it
# completes, right? It'd be like a shell function that `cd`'s somewhere
# to do some work, finishes there, and leaves your terminal there.
prompt_user_and_change_branch_if_working_branch_different_patches () {
  local patch_dir="$1"
  local patch_branch="$2"
  local project_path="$3"
  local patch_path="$4"

  local branch_name
  branch_name="$(git_branch_name)"

  maybe_prompt_user_and_change_branch () {
    local to_branch="$1"

    [ "${branch_name}" != "${to_branch}" ] \
      || return 0

    local will_commit_wip=false
    test -z "$(git status --porcelain=v1)" 
      || will_commit_wip=true

    echo "ALERT: These patches were not generated from the"
    echo "       same-named branch as the current branch."
    echo
    echo "- Would you like us to checkout the appropriate branch?"
    echo
    printf "- We will "
    if ! ${will_commit_wip}; then
      #  "- We will change from “${branch_name}”"
      echo "change from “${branch_name}”"
    else
      #  "- We will commit untidy changes"
      #  "      and change from “${branch_name}”"
      echo "commit untidy changes"
      echo "      and change from “${branch_name}”"
    fi
    echo "                   to “${to_branch}”"
    echo "  in project found at “${project_path}”"
    echo "   because patches at “${patch_dir}”"
    echo
    printf "Shall we proceed? [Y/n] "

    local key_pressed
    local opt_chosen
    prompt_read_single_keypress "y" "n"
    [ "${opt_chosen}" = "y" ] || return 1

    # Note that we don't pop this WIP. User must do so.
    # - We told them so above, so it's fine.
    maybe_stash_changes

    git checkout -q "${to_branch}"
  }

  if [ "${branch_name}" != "${patch_branch}" ]; then
    if git_branch_exists "${patch_branch}"; then
      maybe_prompt_user_and_change_branch "${patch_branch}" || return 1
    elif [ "${patch_branch}" = "${LOCAL_BRANCH_RELEASE}" ] \
      && git_branch_exists "${LOCAL_BRANCH_PRIVATE}"; \
    then
      maybe_prompt_user_and_change_branch "${LOCAL_BRANCH_PRIVATE}" || return 1
    else
      echo
      echo "ERROR: These patches were not generated from the same-named"
      echo "branch as the current branch and there's no local branch of"
      echo "the same name."
      echo "- The patches target branch “${patch_branch}”"
      echo "  in the project located at “${project_path}”"
      echo "  from the unpacked archive “${patch_dir}”"
      echo "- Please address this issue and then continue this script."
      echo "  - You might just need to create and checkout the branch:"
      echo "      cd \"${project_path}\""
      echo "      git checkout -b private"
      echo "  - If you choose not to continue, you can try again later:"
      echo "      cd \"$(realpath "${patch_path}/..")\""
      echo "      $(basename "$0") \"${patch_dir}\""
      echo

      while [ "$(git_branch_name)" != "${patch_branch}" ]; do
        # This will exit 1 on anything but 'y' or 'Y'. Otherwise, it'll
        # loop to check if user created and checked out ${patch_branch},
        # or it'll prompt again.
        must_prompt_user_and_await_resolved_uffda
      done
    fi
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

apply_patches_unless_dry_run () {
  local patch_path="$1"
  local working_branch="$2"

  # Note that we're not `git fetch`'ing. We could fetch 'protected', but if
  # consuming patches, this is likely @personal, which is only machine that
  # pushes to 'protected/protected'. And same with 'release/release'. So a
  # git fetch seems unnecessary here.
  # - Unless the upstream scoping branch moves along otherwise... I guess
  #   my concern is if mine or someone's workflow differs... and while
  #   fetch is costly, so is put-wise, and it's not something you run
  #   all the time (and the commands you might run most, --archive
  #   and --push, can be optimized).

  # Set commit author to, e.g.,  "$(git config user.name) <$(git config user.email)>"
  if ! ${PW_OPTION_RESET_AUTHOR_DISABLE}; then
    local author_name=${PW_OPTION_APPLY_AUTHOR_NAME:-$(git config user.name)}
    local author_email=${PW_OPTION_APPLY_AUTHOR_EMAIL:-$(git config user.email)}

    for patch_file in "${patch_path}"/*.patch; do
      awk '
        BEGIN { changed = 0; }
        /^From: / && ! changed {
          print "From: \"'${author_name}'\" <'${author_email}'>";
          changed = 1;
          next;
        }
        { print $0 }
      ' "${patch_file}" > "${patch_file}.tmp"
      mv -f "${patch_file}.tmp" "${patch_file}"
    done
  fi

  if ! ${DRY_RUN} git am "${patch_path}"/*.patch; then
    echo
    echo "cat .git/rebase-apply/info"
    echo "--------------------------"
    cat ".git/rebase-apply/info"

    must_await_user_resolve_conflicts

    checkout_branch_quietly "${working_branch}"
  fi
}

# ***

rebase_working_atop_ephemeral_branch () {
  local working_branch="$1"
  local ephemeral_branch="$2"

  [ -n "${ephemeral_branch}" ] || return 0

  echo "git checkout ${working_branch} && git rebase refs/heads/${ephemeral_branch}"

  checkout_branch_quietly "${working_branch}"

  if ! ${DRY_RUN} git rebase "refs/heads/${ephemeral_branch}"; then
    must_await_user_resolve_conflicts
  fi

  # Because who knows what the user did.
  checkout_branch_quietly "${working_branch}"
}

# You'll see the starting_sha tag in history visible from HEAD. It represents
# the merge-base with the patches that were --apply'ed. The final patch commit
# is also visible, and is tagged with the -apply-last_patch suffix. The branch
# you had before --apply is also tagged so that it's preserved and so you can
# see it, using the -apply-old_head suffix. So you can deduce the tag name
# from those you see from HEAD. E.g., if the tag is
#   pw-private-abcd1234-apply-starting
# then you'll know that
#   pw-private-abcd1234-apply-old_head
# shows the old branch, from before you ran --apply.
add_patch_history_tags () {
  local old_head="$1"
  local last_patch="$2"
  local patch_branch="$3"
  local starting_sha="$4"
  local patch_base="$5"

  # last_patch will be empty if -g/--regenerate-receipts.
  [ -n "${last_patch}" ] || return 0

  local old_head_short
  old_head_short="$(shorten_sha "${old_head}")"

  # CXREF: PW_TAG_TMP_APPLY_FORMAT ("pw/%s/apply")
  #          format_pw_tag_ephemeral_apply
  local tag_prefix="pw/${patch_branch}/$(date '+%y%m%d#%H%M')/apply"

  local pw_tag_patch_tag

  pw_tag_patch_tag="${tag_prefix}/old_head"
  echo "git tag \"${pw_tag_patch_tag}\" \"${old_head}\""
  ${DRY_RUN} git tag "${pw_tag_patch_tag}" "${old_head}"

  # The starting_sha tag is used as a pre-apply check, to check that
  # the archive has not previously been applied.
  # - CXREF: git_insist_not_applied
  # Note that we record starting_sha from patchkage, which will be same
  # as patch_base for --apply/--push projects. But starting_sha will be
  # meaningless on --apply/--archive projects. So this is basically just
  # how we capture the patchkage starting_sha, as part of the tag name
  # applied to the equivalent but meaningful patch_base.
  pw_tag_patch_tag="${tag_prefix}/starting/${starting_sha}"
  echo "git tag \"${pw_tag_patch_tag}\" \"${patch_base}\""
  ${DRY_RUN} git tag "${pw_tag_patch_tag}" "${patch_base}"

  pw_tag_patch_tag="${tag_prefix}/last_patch"
  echo "git tag \"${pw_tag_patch_tag}\" \"${last_patch}\""
  ${DRY_RUN} git tag "${pw_tag_patch_tag}" "${last_patch}"
}

# LOGIC: Advance the --archive and --apply tracking tags, which are used thusly:
# - The pw/branch/in tag tracks the latest, final --apply patch commit.
#   - This tag gets set on --apply. It is not changed by --archive.
# - The pw/branch/out tag tracks the latest, final --archive commit.
#   - The tag gets set on --archive. It is also removed on --apply, or by a
#     return-receipt, because we know the remote has consumed the commits
#     indicated by the old range (parent of pw/branch/in)..pw/branch/out.
#     So the next --archive will start from (parent of new pw/branch/in),
#     after we move pw/branch/in here to the final patch commit from the
#     git-am we just ran.
manage_pw_tracking_tags () {
  local pw_tag_applied="$1"
  local pw_tag_archived="$2"
  local last_patch="$3"
  local pw_tag_starting="$4"
  local patch_base="$5"

  [ -n "${last_patch}" ] || return 0

  # Move pw/in.
  echo "git tag -f \"${pw_tag_applied}\" \"${last_patch}\""
  ${DRY_RUN} git tag -f "${pw_tag_applied}" "${last_patch}" > /dev/null

  # Delete pw/out.
  echo "git tag -d \"${pw_tag_archived}\""
  # Don't show not-found output, e.g., "error: tag 'foo' not found."
  ${DRY_RUN} git tag -d "${pw_tag_archived}" > /dev/null 2>&1 || true

  # Move pw/work.
  echo "git tag -f \"${pw_tag_starting}\" \"${patch_base}\""
  ${DRY_RUN} git tag -f "${pw_tag_starting}" "${patch_base}" > /dev/null

  # Delete user's pw-apply-here.
  echo "git tag -d \"${PW_TAG_ONTIME_APPLY}\""
  ${DRY_RUN} git tag -d "${PW_TAG_ONTIME_APPLY}" > /dev/null 2>&1 || true
}

# ***

prepare_return_receipt_hydrate () {
  local rev_count="$1"
  local ret_rec_plain_name="$2"
  local patch_branch="$3"
  local starting_sha="$4"
  local last_patch="$5"

  echo "ret_rec_plain_name/2: ${ret_rec_plain_name}"

  local hostname_sha
  hostname_sha="$(print_sha "$(hostname)")"

  # In the unlikely event the return-receipt exists (in the unlikely event
  # that put-wise is updated to support more than 2 machines in the pretzel),
  # or I suppose if the -g/--regenerate-receipts option is enabled, remove
  # this machine's details from the receipt file.
  if [ -f "${ret_rec_plain_name}" ]; then
    sed -i "/^[0-9]\+ ${hostname_sha} /d" "${ret_rec_plain_name}"
  fi

  echo "Recording return receipt: ${hostname_sha} ⇒ ${rev_count}"

  echo \
    "${rev_count} ${hostname_sha} ${patch_branch} ${starting_sha} ${last_patch}" \
    >> "${ret_rec_plain_name}"

  echo "  # cat \${ret_rec_plain_name}"
  echo "  \$ cat ${ret_rec_plain_name}"
  echo "  # rev_count hostname_sha patch_branch starting_sha last_patch"
  cat ${ret_rec_plain_name} | sed 's/^/  /'
}

# ***

prepare_return_receipt_encrypt () {
  local ret_rec_crypt_path="$1"
  local ret_rec_plain_name="$2"

  local temp_archive
  temp_archive="$(mktemp)"

  debug "Archiving return receipt: ${ret_rec_plain_name}"
  debug "- Creating ciphertext at: ${ret_rec_crypt_path}"

  tar -cJf "${temp_archive}" "${ret_rec_plain_name}"

  if [ -f "${ret_rec_crypt_path}" ]; then
    /bin/rm -f "${ret_rec_crypt_path}"
  fi

  encrypt_asset "${ret_rec_crypt_path}" "${temp_archive}"

  /bin/rm -f "${temp_archive}"

  ${DRY_RUN} git add "${ret_rec_crypt_path}"

  commit_changes_and_counting
}

# ***

# This cleanup doesn't support arbitrary names for the unpacked directory.
# Specifically, if the user calls us with a path to an unpacked patch
# directory, we expect it to have the same name as what git-put-wise
# used when it was created, so that we can identify the GPG archive from
# which it was unpacked. (Although we don't `exit 1` if violated.)
remove_archive_from_git () {
  local gpgf="$1"

  if [ ! -f "${gpgf}" ]; then
    >&2 echo "ERROR: Did not find GPG archive named “${gpgf}”"

    # Dead branch: Earlier checks should prevent this.
    return 1
  elif ! git_nothing_staged; then
    # Dead branch: Caller called git_insist_nothing_staged previously.
    >&2 echo "ERROR: The transport repo already has changes staged."

    # Dead branch: Earlier checks should prevent this.
    return 1
  else
    ! ${PW_OPTION_NO_CLEANUP:-false} || return 0

    # So that git-rm's output doesn't look like we called /bin/rm (it
    # doesn't include 'git' in the output), we'll echo, not Git:
    echo "git rm -q \"${gpgf}\""
    ${DRY_RUN} git rm -q "${gpgf}"

    commit_changes_and_counting
  fi
}

remove_plaintext_assets () {
  local patch_dir="$1"
  local ret_rec_plain_name="$2"

  ! ${PW_OPTION_NO_CLEANUP:-false} || return 0

  [ -z "${DRY_RUN}" ] || ${DRY_RUN} "CWD: $(pwd -L)"

  remove_plaintext_assets_dir "${patch_dir}"
  remove_plaintext_assets_file "${ret_rec_plain_name}"
}

remove_plaintext_assets_dir () {
  local a_dir="$1"

  ! ${PW_OPTION_NO_CLEANUP:-false} || return 0

  if [ -d "${a_dir}" ]; then
    echo "/bin/rm -rf \"${a_dir}\""
    ${DRY_RUN} /bin/rm -rf "${a_dir}"
  fi
}

remove_plaintext_assets_file () {
  local a_file="$1"

  ! ${PW_OPTION_NO_CLEANUP:-false} || return 0

  if [ -f "${a_file}" ]; then
    echo "/bin/rm -f \"${a_file}\""
    ${DRY_RUN} /bin/rm -f "${a_file}"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE}" ]; then
  >&2 echo "😶"
fi

