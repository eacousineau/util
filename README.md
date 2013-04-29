# util

Random bash utils, some adapted from other peeps' stuff. Primarily

*	git-submodule-ext - Submodule extensions. See `SUBMODULES.md` for more info.
*	git-new-workdir - Modified from git/contrib to work for submodules
*	git-emeld - Editable version of git-meld using git-new-workdir
*	run-or-raise - Basic implementation (should use other one ??? )

**TODO**: Post links to originals

## Setup

	sudo ./install /usr/local/bin
	./aliases # Set some git aliases

If you wish to develop on them while keeping in your `$PATH`, then do

	./install --link ~/local/bin
	./aliases