#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/depoxy/git-put-wise#🥨
# License: MIT

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PW_ABOUT='
About git-put-wise
==================

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
'

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

