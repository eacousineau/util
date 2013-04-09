#!/bin/sh

bin=$0

usage () {
	echo "usage: $bin [--always-link-config] <repository> <new_workdir> [<branch>]"
	exit 127
}

die () {
	echo $@
	exit 128
}

always_link_config=
while test $# -gt 0
do
	case "$1" in
		--always-link-config)
			always_link_config=1
			;;
		*)
			break
			;;
	esac
	shift
done	

if test $# -lt 2 || test $# -gt 3
then
	usage
fi

orig_git=$1
new_workdir=$2
branch=$3

# want to make sure that what is pointed to has a .git directory ...
git_dir=$(cd "$orig_git" 2>/dev/null &&
  git rev-parse --git-dir 2>/dev/null) ||
  die "Not a git repository: \"$orig_git\""

case "$git_dir" in
.git)
	git_dir="$orig_git/.git"
	;;
.)
	git_dir=$orig_git
	;;
esac

# don't link to a configured bare repository
isbare=$(git --git-dir="$git_dir" config --bool --get core.bare)
if test ztrue = z$isbare
then
	die "\"$git_dir\" has core.bare set to true," \
		" remove from \"$git_dir/config\" to use $0"
fi

# don't link to a workdir
if test -h "$git_dir/config"
then
	die "\"$orig_git\" is a working directory only, please specify" \
		"a complete repository."
fi

# don't recreate a workdir over an existing repository
if test -e "$new_workdir"
then
	die "destination directory '$new_workdir' already exists."
fi

# make sure the links use full paths
git_dir=$(cd "$git_dir"; pwd)

# create the workdir
mkdir -p "$new_workdir/.git" || die "unable to create \"$new_workdir\"!"

# create the links to the original repo.  explicitly exclude index, HEAD and
# logs/HEAD from the list since they are purely related to the current working
# directory, and should not be shared.
for x in refs logs/refs objects info hooks packed-refs remotes rr-cache svn
do
	case $x in
	*/*)
		mkdir -p "$(dirname "$new_workdir/.git/$x")"
		;;
	esac
	ln -s "$git_dir/$x" "$new_workdir/.git/$x"
done

x=config
git_config="$git_dir/$x"
new_config="$new_workdir/.git/$x"

# Allow submodules to be checked out
if test -z "$always_link_config" && git config -f "$git_config" core.worktree
then
	echo "[ Note ] Copying .git/config and unsetting core.worktree"
	cp "$git_dir/$x" "$new_config"
	git config -f "$new_config" --unset core.worktree
else
	ln -s "$git_dir/$x" "$new_workdir/.git/$x"
fi

# now setup the workdir
cd "$new_workdir"
# copy the HEAD from the original repository as a default branch
cp "$git_dir/HEAD" .git/HEAD
# checkout the branch (either the same as HEAD from the original repository, or
# the one that was asked for)
git checkout -f $branch
