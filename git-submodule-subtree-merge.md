# Git Submodule Subtree Merge

First add the repo you want to merge in

	git remote add other /path/to/other

Next, fetch the changes from that remote.

	git fetch other

Now do a normal merge

	git merge --no-ff other/master

Or a subtree merge? (Not tested)

	git subtree merge --prefix=other other develop


When merging `.gitmodules`, it's easier to deal with if they're sorted. See `git-config-sort.py`. 