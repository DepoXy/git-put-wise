git-put-wise — Seamlessly manage private commits 🥨
===================================================

## SYNOPSIS

`git put-wise` &lt;command&gt; [&lt;options&gt;...] [--] [&lt;path&gt;]

## DESCRIPTION

  Seamlessly manage private commits, and share GPG-encrypted patches.

## COMMANDS

  Specify one:

    General commands
    ----------------

    -h|--help|help            Print this help
    -V|--version              Print the program version

    Single Project commands
    -----------------------

    -o|--push|push            Publish changes to relevant remotes
    -i|--pull|pull            Consume changes from remote branch
    -e|--archive|archive      Create encrypted patch archive
    -y|--apply|apply          Apply patches from encrypted patch archive
                                (where <path> is project path or archive path)

    Other commands
    --------------

    -A|--apply-all            Apply patches from all encrypted archives found
      |apply-all|all            in the patches repo (where --patches-repo is
                                required and <path> is read from each archive)

    -R|--reset                (Re)create the patches repo

    --sha|sha [<path>]        Print <path> SHA (defaults to project directory)

## PATH ARG

  Project or Archive path:

    <path>                    Optional path to the project to work on
                                (defaults to the current directory);
                              Or path to the patch archive to apply
                                (when used with --apply)

## OPTIONS

  Command options:

    -J|--project-path <path>  Project or archive path to use (this is an alt-
                                ernative to using the final <path> argument,
                                so `git put-wise -J .` == `git put-wise .`)

    -O|--patches-repo <repo>  Directory path to repo of patch archives (those
                                created on --archive and consumed on --apply*)

    -n|--pass-name            Password Store entry containing passphrase to use
                                with --archive and --apply* (if unspecified you
                                will be prompted twice by GPG for each archive)

    -c|--cleanup              With --apply*, git-rm each processed archive and
                                /bin/rm -rf its unpacked directory [default]
    -C|--no-cleanup           With --apply*, don’t cleanup (leave both)

    -N|--author-name <name>   With --apply, set commit author name to <name>
    -M|--author-email <mail>  With --apply, set commit author email to <mail>
    -L|--leave-author         With --apply, uses author specified in patches
    --reset-author            ^^^, uses local project’s user.name <user.email>
                                [default] (customize with -N/-M, -L disables)

    -f|--force                With --push, uses git push --force-with-lease
    -F|--no-force             With --push, don’t --force-with-lease [default]

    --explain                 With --push, explain how tig prompt works [default]
    -E|--no-explain           With --push, don’t explain how tig prompt works

    -u|--squash               Fixup commits to the patches repo [default]
    -U|--no-squash            Make new commits to patches repo

    -S|--starting-ref <ref>   On --archive, format-patch <starting gitref>..HEAD
                                but generally for special circumstances

    -b|--branch <name>        Override put-wise branch choice
    -r|--remote <name>        Override put-wise remote choice

    -v|--verbose              Print excess blather
    --no-verbose              Don’t print excess blather
    -T|--dry-run              Print git commands to run but do not make changes
                              - Hint: When combined with --apply-all, dry-run
                                decrypts all patchkages, leaves them unpacked,
                                but does not apply them.

## ENVIRONS

  Environment variables you can use instead of options above:

    -o|--push|push            PW_ACTION_PUSH=true|false
    -i|--pull|pull            PW_ACTION_PULL=true|false
    -e|--archive|archive      PW_ACTION_ARCHIVE=true|false
    -y|--apply|apply          PW_ACTION_APPLY=true|false
    -A|--apply-all|...        PW_ACTION_APPLY_ALL=true|false
    -R|--reset                PW_ACTION_RESET=true|false
    --sha|sha [<path>]        PW_ACTION_SHA=true PW_PROJECT_PATH="<path>"

    -J|--project-path <path>  PW_PROJECT_PATH="<path>"
    -O|--patches-repo <repo>  PW_PATCHES_REPO="<repo>"

    -n|--pass-name            PW_OPTION_PASS_NAME="<name>"

    -C|--no-cleanup           PW_OPTION_NO_CLEANUP=true
    -c|--cleanup              PW_OPTION_NO_CLEANUP=false

    -N|--author-name <name>   PW_OPTION_APPLY_AUTHOR_NAME="<name>"
    -M|--author-email <mail>  PW_OPTION_APPLY_AUTHOR_EMAIL="<mail>"
    -L|--leave-author         PW_OPTION_RESET_AUTHOR_DISABLE=true
    --reset-author            PW_OPTION_RESET_AUTHOR_DISABLE=false

    -f|--force/-F|--no-force  PW_OPTION_FORCE_PUSH=true|false
    --explain/-E|--no-explain PW_OPTION_QUICK_TIG=false|true

    -U|--no-squash            PW_OPTION_SKIP_SQUASH=true
    -u|--squash               PW_OPTION_SKIP_SQUASH=false

    -S|--starting-ref <ref>   PW_OPTION_STARTING_REF="<ref>"
    -b|--branch <name>        PW_OPTION_BRANCH="<name>"
    -r|--remote <name>        PW_OPTION_REMOTE="<name>"

    -v|--[no-]verbose         PW_OPTION_VERBOSE=true|false
    -T|--dry-run              PW_OPTION_DRY_RUN=true|false

## ABOUT

This program supports a particular Git workflow, wherein you can
intermingle "private" and "protected" commits in the same branch
as public (published) commits, without needing to manually manage
separate branches.

This program manages the process for you, so you can always work
from the same branch. You won‘t have to worry about changing
branches, moving branch pointers around, nor specifying what
branch or commit to push to which remote branch, just to keep
some commits local while pushing other commits.

This program also supports an oblique method for sharing changes
between environments (i.e., between your machines), subverting the
normal push/pull to/from a remote branch, but instead bundling and
encrypting patch archives that will later be decrypted and applied
to your projects.

- You might want such a feature if you don‘t want your private bits
  uploaded unencrypted to a third-party service (like GitHub or
  GitLab). For example, this is how the author syncs their personal
  notes between two machines that cannot communicate otherwise.

- Or you might want such a feature to defer publishing code changes
  from the machine you are using. For example, say you‘re on the
  clock, but you need to quickly fix and add something to one of
  your many open source projects. You can make the (possibly crude)
  change and get back to work. Then, when you clock out, you can
  privately move that change to your personal machine to test it,
  refine it, and finally publish it.

## EXAMPLES

  Push the appropriate commit to the remote branch:

    $ git put-wise push

  Pull the latest commits, rebasing scoped commits as necessary:

    $ git put-wise pull

  On a client machine, create an encrypted patch archive with the
  latest commits and upload to remote Git host (e.g., GitHub):

    @client $ cd path/to/project
    @client $ git put-wise archive -O path/to/patches
    @client $ cd path/to/patches
    @client $ git push -f

  Hint: Use the `PW_PATCHES_REPO` environ so you don't have to use
  the `-O {path}` option.

  On the leader machine, download the encrypted patches, decrypt,
  and apply to your local project:

    @leader $ cd path/to/patches
    @leader $ git pull --rebase
    @leader $ git put-wise apply-all

## AUTHOR

**git-put-wise** is Copyright (c) 2022-2023 Landon Bouma &lt;depoxy@tallybark.com&gt;

This software is released under the MIT license (see `LICENSE` file for more)

## REPORTING BUGS

&lt;https://github.com/DepoXy/git-put-wise/issues&gt;

