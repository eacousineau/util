#!/bin/sh

# Supermodule stuff works
# TODO Add a '--update-linked-config' option to go through and update linked configs?
# NOTE: Not robust to submodules being created after the link. New workdirs should be disposable.

# Wait... How does this work if worktree is unset? Seems like doing submodule init or update somehow fixes that... ???

bin_path=$0
bin=$(basename $bin_path)

usage () {
	echo "usage: $bin [--always-link-config] [--skip-submodules] [--bare] [-c | --constrain] <repository> <new_workdir> [<branch>]"
	exit 127
}

die () {
	echo $@
	exit 128
}

always_link_config=
bare=
skip_submodules=
constrain=

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
		-c|--constrain)
			constrain=1
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

if test -n "$always_link_config"
then
	recurse_flags="--always-link-config"
fi


orig_workdir=$1
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
git_dir_check_hack()
{
	( cd $1 && test -e HEAD -a -e config -a -d refs )
}

# want to make sure that what is pointed to has a .git directory ...
orig_gitdir=$(get_git_dir "$orig_workdir") || die "Not a git repository: \"$orig_workdir\""
# make sure the links use full paths
case "$orig_gitdir" in
.git)
	orig_gitdir="$orig_workdir/.git"
	;;
.)
	orig_gitdir=$orig_workdir
	;;
esac
orig_gitdir=$(readlink -f $orig_gitdir)

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
	die "\"$orig_workdir\" is a working directory only, please specify" \
		"a complete repository."
fi

# don't recreate a workdir over an existing repository
if test -e "$new_workdir"
then
	die "destination directory '$new_workdir' already exists."
fi

echo "[ Old -> New ]\n\t$orig_workdir\n\t$new_workdir"

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
	echo "\t[ Note ] Copying .git/config and unsetting core.worktree"
	cp "$orig_gitdir/$x" "$new_config"
	git config -f "$new_config" --unset core.worktree
else
	ln -s "$orig_config" "$new_config"
fi

x=modules
orig_modules="$orig_gitdir/$x"
new_modules="$new_gitdir/$x"
is_supermodule=
if test -d "$orig_modules" -a -z "$skip_submodules"
then
	is_supermodule=1
	# TODO Allow for directory structure... Checking if a module is 
	echo "\t[ Note ] Applying $bin to .git/modules since it's a supermodule"

	modulate()
	{
		orig_path=$1
		new_path=$2
		modules=$(dir $orig_path)
		for module in $modules
		do
			orig_module=$orig_path/$module
			new_module=$new_path/$module
			# If it's not a git module itself, then it might be a directory containing them. GO MONKEY GO!
			if git_dir_check_hack $orig_module
			then
				# Teh recursion
				$bin_path --bare $recurse_flags $orig_module $new_module
			else
				# Other recursion
				echo "[ Submodule \"$module\" ]"
				( modulate $orig_module $new_module )
			fi
			# See if it's a git module
		done
	}

	modulate $orig_modules $new_modules
fi

# copy the HEAD from the original repository as a default branch
cp "$orig_gitdir/HEAD" $new_gitdir/HEAD

if test -z "$bare"
then
	# now setup the workdir
	cd "$new_workdir"
	# checkout the branch (either the same as HEAD from the original repository, or
	# the one that was asked for)
	git checkout -f $branch > /dev/null

	# Update submodules - TODO Use `git sube` to allow --constrain option to be recursive	?
	if test -n "$is_supermodule"
	then
		if test -n "$constrain"
		then
			modules=$(git config scm.focusGroup)
		else
			modules=
		fi
		git submodule update --init --recursive -- $modules
	fi
fi