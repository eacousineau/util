# util

Random bash utils, some adapted from other peeps' stuff. Primarily

*	git-submodule-ext - Submodule extensions. See `SUBMODULES.md` for more info.
*	git-new-workdir - Modified from git/contrib to work for submodules
*	git-emeld - Editable version of git-meld using git-new-workdir
*	run-or-raise - Basic implementation (should use other one ??? )

# Setup

	sudo ./install /usr/local/bin
	./aliases # Set some git aliases

If you wish to develop on them while keeping in your `$PATH`, then do

	./install --link ~/local/bin
	./aliases

# Credits

*	Jens Lehmann, Junio Hamano, Heiko Voigt, Phil Hord - Design guidance and suggestions and for modifications to submodule foreach.
*	Julian Phillips, Shawn O. Pearce - Original git-new-workdir
*	Antonin Hildebrand - [Discussion](http://comments.gmane.org/gmane.comp.version-control.git/196019) for git-new-workdir with submodules
*	wmanley - Original [git-meld](https://github.com/wmanley/git-meld)
*	Vicky Chijwani - run-or-raise [blog post](http://vickychijwani.github.io/2012/04/15/blazing-fast-application-switching-in-linux/)
*	David Mikalova - better run-or-raise implementation, [brocket](https://github.com/dmikalova/brocket.git)

# Todo

*	Add `git-submodule-ext dir-sync` with two options:
	1.	`super` - Will ensure that all submodule `$GIT_DIR`'s are in the supermodule's `$GIT_DIR/modules/$path`
	2.	`repo` - Will ensure that all submodule `$GIT_DIR`'s are in the submodule's `$path/.git`
