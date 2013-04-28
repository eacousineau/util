#!/bin/bash
# Some redundant commands to get everything updated in the submodule and updating the branches with the most recent stuff

# http://www.davidpashley.com/articles/writing-robust-shell-scripts.html#idm1248
set -e -u

# TODO Does not seem robust to having really old local branches...
# TODO Try not to use submodule update since that does not seem too reliable. Instead, only do a fetch, then merge remote branch (using git branch-get)

# 	How to get update to only update uninitialized submodules?
#	Get a list of uninitialized submodules, directly from git-submodule.sh
# Add a --reset option - Allow submodule to get top-level branch config, then do a hard reset to the origin's version of that branch
local clean= set_upstream= no_pull= force=
local remote=origin
while [ $# -gt 0 ]
do
	case $1 in
		-r|--remote)
			shift
			remote=$1
			;;
		-c|--clean)
			clean=1
			;;
		-u|--set-upstream)
			set_upstream=1
			;;
		-n|--no-pull)
			no_pull=1
			;;
		-f|--force)
			echo "Not implemented" && exit 1
			force=1
			;;
		*)
			break
			;;
	esac
	shift
done

export remote
test -n "$set_upstream" && ( git branch --set-upstream $(git branch-get) $remote/$(git branch-get) || return 1 )
git submodule sync

if test -z "$no_pull"
then
	echo "[ Pulling Supermodule ]"
	git pull --no-recurse-submodules $remote || return 1
fi

echo "[ Submodule Init / Update ]"
git submodule init
git submodule update

test -n "$clean" && git clean -fd

echo "[ Submodule Fetch ]"
git sfe 'git fetch $remote'

echo "[ Branch Checkout ]"
git-sfe-branch-checkout

test -n "$set_upstream" && git sfe 'branch=$(git branch-get); git branch --set-upstream $branch $remote/$branch'

echo "[ Updating Local Branches to Origin via Merge ]"
git sfe 'git merge $remote/$(git branch-get)'