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

**git-put-wise** is Copyright (c) 2022-2023 Landon Bouma &lt;<depoxy@tallybark.com>&gt;

This software is released under the MIT license (see <LICENSE> file for more)

## REPORTING BUGS

&lt;<https://github.com/DepoXy/git-put-wise/issues>&gt;

## SEE ALSO

&lt;<https://github.com/DepoXy/git-put-wise>&gt;
