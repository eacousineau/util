# Git Submodules

Small primer on Git submodules and using `git-submodule-ext`.

Submodules / supermodules are useful because they can contain other Git repos, but there is not any overhead of having to be directly in charge of the other repo's history. This allows you to easily switch around URLs, etc., with your supermodule

# Terminology

*	worktree, `$WORKTREE` - The files you deal with.
*	git-dir, `$GIT_DIR` - Place where Git data is
*	module - A Git repo whose git-dir might be in it's own worktree or in its supermodule's `$GIT_DIR`
*	submodule - A module whose git-dir is its supermodule's `$GIT_DIR/modules folder`. `.git` is a file instead of a folder, that points to its `$GIT_DIR` located in the supermodule `$GIT_DIR`.
*	detached head - No local branch is pointing to your commit. If you make changes, it may be hard to get back to them if you check out another commit.

# Cloning a Supermodule

To recursively clone a supermodule, just do a normal `clone` but with the `--recursive` option. You can also clone a specific branch.
Example:
	
	git clone --recursive git://host/repo.git -b develop

# Useful Commands

First of all, see `man git-submodule`. A quick summary:

* 	`git submodule`
	*	`add` - Add a submodule with the correct stuff, just like `git clone`
	*	`foreach` - Iterate through submodules. Example: `git submodule foreach --recursive 'git status`
	*	`init` - Register a submodule specified in your index in and `$GIT_DIR/config`. Useful if you can't see a submodule in your worktree.
	*	`update` - Checkout submodules to the commits specified in your supermodule's commit.
	*	`sync` - Go through each submodule and set it's `origin` URL to the URL defined in `.gitmodules`. This is one way.

Other commands:

*	`git rev-parse --git-dir` - Get the `$GIT_DIR` for your module. Useful for inspecting your Git config
*	`git config -e`, `git config --global -e` - Use your `$EDITOR` to edit your Git config (the repo's or your global config)

And extensions:

*	`git submodule-ext` or `git sube`
	*	`foreach` - Modified to allow more flexible iteration: post-order, with top-level module, and constrained. Constrained iteration is done by using a list specified in `scm.focusGroup` in `$GIT_DIR/config`
	*	`branch write`, `branch checkout` - Record and checkout the branch your submodules are on, recorded in `.gitmodules`. You can specify `foreach` options, including `--constrain`. If submodule does not have a branch, `branch checkout` will do nothing.
	*	`refresh` - Makes sure that your submodules are correctly checked out and up to date with remote repos, including checking out the branches specified in `.gitmodules`. **NOTE**: This is intended for development. If you write all of your submodule's branches, you may update some of your submodules further than you want.

# Practices

In your supermodule, your submodules will appear as single 'files', which represent the commits of your submodule. You can stage, commit, diff, and checkout those as you wish. Note that having an indexed commit in your submodule does not mean your submodule is at that commit -- for that you use `git submodule update`.

If you want to commit in your supermodule, you need to be sure to commit / push your submodules first. You can do that with `git sube`, like so:

	git sube foreach -t -r -p 'git gui'

This is post-order, recursive, and includes the top-level, so `git gui` is called in the super module last.

# Git Versions

Right now, Ubuntu 12.04 uses `v1.7.9.5`. There is more Git submodule functionality in `v1.8.2`, which you can build from source. Most notable difference is that later versions use relative paths for submodule paths, which simplifies stuff a lot (as in you can move your supermodule and not have to climb through mounds of files).

# Direct Supermodule Cloning 

To recursively clone another person's supermodule

	git clone git://bobby.local/repo
	cd repo
	git sfe -t -r 'git sube set-url super && yes | git sube refresh -T --no-sync --reset'

Afterwards, restore original urls, then add the direct clone url

	git remote add bobby "$(git config remote.origin.url)"
	git submodule sync --recursive
	git sube set-url -r --remote bobby base

## Their Branches

If they haven't used `git sube branch write`, you can still peek at their branches with a remote HEAD. See all of their branches using the following command:

	git tsferp 'remote=origin; tmp=$(git name-rev --name-only $remote/HEAD); echo "\tMine: $(git bg)\n\tTheirs: $tmp"'

To reset to their branches

	git tsferp 'remote=origin; tmp=$(git name-rev --name-only $remote/HEAD); git checkout -B $tmp $remote/$tmp'

# Other Articles

*	[Pro Git Book](http://git-scm.com/book/en/Git-Tools-Submodules)
*	[Atlassian Blogs](http://blogs.atlassian.com/2013/03/git-submodules-workflows-tips/)