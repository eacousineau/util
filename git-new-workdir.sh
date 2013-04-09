#!/bin/sh

# TODO Make it an option to link the submodule git-dir's in different submodules for ease of distributed development.
# ... Would need to strip out work tree, setting, and then set it to the new structures...
# Very constrained situation. Check if it is at root level?

# TODO Seems like $(git rev-parse --git-dir) in a new workdir submodule still yields original module file path.
# Is that OK? Meh.

# TODO To do this for a supermodule, need to go through each submodule that's in the index.
# 1.	Get it's git_dir
# 2.	Do git-new-workdir for it, but will need to have it such that the work tree is the same as before.
#		So don't check things out, wait for submodule update to do that...
#		****Just need to do the git-new-workdir for the gitdir only, no checking out. Config can stay the same -- YAY!
#	How to get the existing submodules relative path? By maintaining the same one it had in the supermodule...
#	So really, we would keep the config...
# 3.	Since git rev-parse --git-dir seems to resolve symlinks, will nee
# NOTE: Is not robust for remotes with relative paths...

bin_path=$0
bin=$(basename $bin_path)

usage () {
	echo "usage: $bin [--always-link-config] [--skip-submodules] [--bare] <repository> <new_workdir> [<branch>]"
	exit 127
}

die () {
	echo $@
	exit 128
}

always_link_config=
bare=
skip_submodules=

while test $# -gt 0
do
	case "$1" in
		--always-link-config)
			always_link_config=1
			;;
		--bare)
			bare=1
			;;
		--skip-submodules)
			skip_submodules=1
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

if test -z "$bare"
then
	new_gitdir="$new_workdir/.git"
else
	new_gitdir="$new_workdir"
fi

get_git_dir()
{
	( cd $1 && git rev-parse --git-dir ) 2>/dev/null
}
git_dir_check_ghetto()
{
	( cd $1 && test -d config -a -d refs -a -e HEAD )
}

# want to make sure that what is pointed to has a .git directory ...
git_dir=$(get_git_dir "$orig_git") || die "Not a git repository: \"$orig_git\""

case "$orig_gitdir" in
.git)
	git_dir="$orig_git/.git"
	;;
.)
	git_dir=$orig_git
	;;
esac

# don't link to a configured bare repository
isbare=$(git --git-dir="$orig_gitdir" config --bool --get core.bare)
if test ztrue = z$isbare -a -z "$bare"
then
	die "\"$orig_gitdir\" has core.bare set to true," \
		" remove from \"$orig_gitdir/config\" to use $0"
fi

# don't link to a workdir
if test -h "$orig_gitdir/config"
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
git_dir=$(cd "$orig_gitdir"; pwd)

echo "Git dir: $orig_gitdir"
echo "New gitdir: $new_gitdir"
echo "New workdir: $new_workdir"

# create the gitdir
mkdir -p "$new_gitdir" || die "unable to create \"$new_gitdir\"!"

# create the links to the original repo.  explicitly exclude index, HEAD and
# logs/HEAD from the list since they are purely related to the current working
# directory, and should not be shared.
for x in refs logs/refs objects info hooks packed-refs remotes rr-cache svn
do
	case $x in
	*/*)
		mkdir -p "$(dirname "$new_gitdir/$x")"
		;;
	esac
	ln -s "$orig_gitdir/$x" "$new_gitdir/$x"
done

x=config
orig_config="$orig_gitdir/$x"
new_config="$new_gitdir/$x"
# Allow submodules to be checked out
if test -z "$always_link_config" && git config -f "$orig_config" core.worktree > /dev/null
then
	echo "[ Note ] Copying .git/config and unsetting core.worktree"
	cp "$orig_gitdir/$x" "$new_config"
	git config -f "$new_config" --unset core.worktree
else
	ln -s "$orig_config" "$new_config"
fi

x=modules
git_modules="$orig_gitdir/$x"
is_supermodule=
if test -d "$git_modules" -a -z "$skip_submodules"
then
	is_supermodule=1
	# TODO Allow for directory structure... Checking if a module is 
	echo "[ Note ] Applying $bin to .git/modules since it's a supermodule"
	modulate()
	{
		path=$1
		dirs=$(dir $git_modules)
		for module in $modules
		do
			$orig_module=$path/$module
			# If it's not a git module itself, then it might be a directory containing them. GO MONKEY GO!
			if ! git_dir_check_ghetto $orig_module
			then
				# Teh recursion
				$bin_path 
			fi
			# See if it's a git module
	}
	modulate $git_modules
fi


# copy the HEAD from the original repository as a default branch
cp "$orig_gitdir/HEAD" $new_gitdir/HEAD

if test -n "$bare"
	# now setup the workdir
	cd "$new_workdir"
	# checkout the branch (either the same as HEAD from the original repository, or
	# the one that was asked for)
	git checkout -f $branch

	# Update submodules
	if test -n "$is_supermodule"
	then
		git submodule update
	fi
fi