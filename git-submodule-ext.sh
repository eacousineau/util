#!/bin/sh
#
# git-submodule-ext.sh: submodule extensions
#
# Lots of things copied and pasted from git-submodule.sh
# TODO Add in other updates to git-submodule-foreach

dashless=$(basename "$0" | sed -e 's/-/ /')
USAGE="foreach [-l | --list LIST] [-c | --constrain] [-t | --top-level] [-r | --recursive] [-p | --post-order] <command>
	or: $dashless branch [FOREACH_FLAGS] [write | checkout]
	or: $dashless womp [FOREACH_FLAGS] [--remote REMOTE] [--force] [--oompf] [--no-sync] [--no-track] [-N | --no-fetch] <branch>
	or: $dashless resync"
OPTIONS_SPEC=
. git-sh-setup
. git-sh-i18n
. git-parse-remote
require_work_tree

# http://stackoverflow.com/questions/171550/find-out-which-remote-branch-a-local-branch-is-tracking
# git name-rev --name-only HEAD

# get_default_remote

# var=origin/feature/something; echo ${var#origin/}

set -u -e

#
# Get submodule info for registered submodules
# $@ = path to limit submodule list
#
module_list()
{
	(
		git ls-files --error-unmatch --stage -- "$@" ||
		echo "unmatched pathspec exists"
	) |
	perl -e '
	my %unmerged = ();
	my ($null_sha1) = ("0" x 40);
	my @out = ();
	my $unmatched = 0;
	while (<STDIN>) {
		if (/^unmatched pathspec/) {
			$unmatched = 1;
			next;
		}
		chomp;
		my ($mode, $sha1, $stage, $path) =
			/^([0-7]+) ([0-9a-f]{40}) ([0-3])\t(.*)$/;
		next unless $mode eq "160000";
		if ($stage ne "0") {
			if (!$unmerged{$path}++) {
				push @out, "$mode $null_sha1 U\t$path\n";
			}
			next;
		}
		push @out, "$_\n";
	}
	if ($unmatched) {
		print "#unmatched\n";
	} else {
		print for (@out);
	}
	'
}

die_if_unmatched ()
{
	if test "$1" = "#unmatched"
	then
		exit 1
	fi
}

#
# Map submodule path to submodule name
#
# $1 = path
#
module_name()
{
	# Do we have "submodule.<something>.path = $1" defined in .gitmodules file?
	sm_path="$1"
	re=$(printf '%s\n' "$1" | sed -e 's/[].[^$\\*]/\\&/g')
	name=$( git config -f .gitmodules --get-regexp '^submodule\..*\.path$' |
		sed -n -e 's|^submodule\.\(.*\)\.path '"$re"'$|\1|p' )
	test -z "$name" &&
	die "$(eval_gettext "No submodule mapping found in .gitmodules for path '\$sm_path'")"
	echo "$name"
}

# TODO Add below functionality, for syncing with other computers via git-daemon
# git sfer 'echo $(cd $toplevel && cd $(git rev-parse --git-dir) && pwd)/modules/$path'

# Add 'write' / 'sub' to write submodule's url to .gitmodules
# Good words for doing that?

set_module_config_url() {
	local path=$1
	local myurl=$2
	git config -f $toplevel/.gitmodules submodule.$path.url $myurl
	git config submodule.$path.url $myurl
}

cmd_resync()
{
	remote=
	change_url=1
	foreach_flags=
	reverse=
	while test $# -ne 0
	do
		case $1 in
			-r|--recursive)
				foreach_flags="$foreach_flags $1"
				;;
			--no-change)
				change_url=
				;;
			--reverse)
				reverse=1
				;;
			-h|--help|--*)
				usage
				;;
			*)
				break
				;;
		esac
		shift
	done

	if test $# -eq 1
	then
		remote=$1
	else
		# Allow submodules to have different default remotes?
		remote=$(get_default_remote || :) # Does not return successful at times?
		echo $remote
	fi
	# Add a non-isolated command for foreaech?

	# --include-staged option is somehting to be wary of...
	resync_iter() {
		if test -z "$reverse"
		then
			# Redundant :/
			topurl=$(cd $toplevel && git config remote."$remote".url)
			myurl=$topurl/modules/$path
		else
			if test -n "$is_worktree"
			then
				myurl=$(git config remote."$remote".url)
			fi
		fi

		# What about changing the gitdir if it's not a worktree?

		# Doesn't do relative paths

		say "Submodule url is now $myurl"
		set_module_config_url "$path" "$myurl"

		if test -z "$reverse" -a -n "$is_worktree" -a -n "$change_url"
		then
			say "Repo remote url is now $myurl"
			git config remote.$remote.url "$myurl"
		fi
	}

	cmd_foreach --include-staged $foreach_flags resync_iter
}

foreach_read_constrained() {
	if test -n "$constrain"
	then
		if test -z "$list"
		then
			# Ensure that if this command fails, it still returns zero status
			list=$(git config scm.focusGroup || :)
		else
			echo "Note: List set for parent, only constraining on submodules"
		fi
	fi
}

cmd_foreach()
{
	# parse $args after "submodule ... foreach".
	recursive=
	post_order=
	include_super=
	constrain=
	list=
	recurse_flags=--not-top
	is_top=1
	include_staged=
	while test $# -ne 0
	do
		case "$1" in
		-q|--quiet)
			GIT_QUIET=1
			;;
		-r|--recursive)
			recursive=1
			recurse_flags="$recurse_flags $1"
			;;
		-p|--post-order)
			post_order=1
			recurse_flags="$recurse_flags $1"
			;;
		-c|--constrain)
			constrain=1
			recurse_flags="$recurse_flags $1"
			;;
		-t|--top-level)
			include_super=1
			;;
		-l|--list)
			list=$2
			shift
			;;
		--not-top)
			is_top=
			;;
		--include-staged)
			include_staged=1
			;;
		-*)
			usage
			;;
		*)
			break
			;;
		esac
		shift
	done

	toplevel=$(pwd)

	# dup stdin so that it can be restored when running the external
	# command in the subshell (and a recursive call to this function)
	exec 3<&0

	# For supermodule
	name=$(basename $toplevel)

	# This is absolute... Is that a good idea?
	prefix=
	path=$toplevel

	is_worktree=1

	super_eval()
	{
		verb=$1
		shift
		say "$(eval_gettext "$verb supermodule '$name'")"
		( eval "$@" ) || die "Stopping at supermodule; script returned non-zero status."
	}

	if test -n "$include_super" -a -z "$post_order"
	then
		super_eval Entering "$@"
	fi
	
	foreach_read_constrained

	test -z "${prefix+D}" && prefix=

	module_list $list |
	while read mode sha1 stage sm_path
	do
		die_if_unmatched "$mode"
		if test -e "$sm_path"/.git
		then
			enter_msg="$(eval_gettext "Entering '\$prefix\$sm_path'")"
			exit_msg="$(eval_gettext "Leaving '\$prefix\$sm_path'")"
			die_msg="$(eval_gettext "Stopping at '\$sm_path'; script returned non-zero status.")"
			(
				is_worktree=1
				list=
				name=$(module_name "$sm_path")
				prefix="$prefix$sm_path/"
				clear_local_git_env
				# we make $path available to scripts ...
				path=$sm_path
				cd "$sm_path" &&
				if test -z "$post_order"
				then
					say "$enter_msg"
					( eval "$@" ) || exit 1
				fi &&
				if test -n "$recursive"
				then
					(
						# Contain so things don't spill to post_order
						cmd_foreach $recurse_flags "$@" || exit 1
					) || exit 1
				fi &&
				if test -n "$post_order"
				then
					say "$exit_msg"
					( eval "$@" ) || exit 1
				fi
			) <&3 3<&- || die "$die_msg"
		elif test -n "$include_staged"
		then
			enter_msg="$(eval_gettext "Entering staged '\$prefix\$sm_path'")"
			say "$enter_msg"
			(
				is_worktree=
				path=$sm_path
				eval "$@"
			) || exit 1
		fi
	done || exit 1

	if test -n "$include_super" -a -n "$post_order"
	then
		super_eval Leaving "$@"
	fi
}

branch_get() {
	git rev-parse --abbrev-ref HEAD
}
branch_set_upstream() {
	# For Git < 1.8
	branch=$(branch_get)
	git branch --set-upstream $branch $remote/$branch
}

branch_iter_write() {
	branch=$(branch_get)
	git config -f $toplevel/.gitmodules submodule.$name.branch $branch
}
branch_iter_checkout() {
	if branch=$(git config -f $toplevel/.gitmodules submodule.$name.branch 2>/dev/null)
	then
		git checkout $branch
	fi
}

cmd_branch()
{
	foreach_flags= command=
	while test $# -gt 0
	do
		case $1 in
			-s|-c|-r)
				foreach_flags="$foreach_flags $1"
				;;
			*)
				break
				;;
		esac
		shift
	done
	test $# -eq 0 && usage
	case $1 in
		write | checkout)
			command=$1
			;;
		*)
			usage
			;;
	esac
	cmd_foreach $foreach_flags branch_iter_${command}
}

# TODO I think subshells are preventing things from properly dying on error. Need to fix

cmd_womp()
{
	# How to get current remote?
	remote=origin track=1 sync=1
	force= oompf= no_fetch= recursive= force= list= constrain=
	branch=
	foreach_flags= update_flags=
	no_top_level_merge=
	dry_run=
	while test $# -gt 0
	do
		case $1 in
			--remote)
				remote=$2
				shift
				;;
			-f|--force)
				force=1
				;;
			--oompf)
				force=1
				oompf=1
				;;
			--no-sync)
				sync=
				;;
			--no-track)
				track=
				;;
			-T|--no-top-level-merge)
				no_top_level_merge=1
				;;
			-N|--no-fetch)
				no_fetch=1
				update_flags=-N
				;;
			-c|--constrain)
				constrain=1
				;;
			-s|-c|-r)
				foreach_flags="$foreach_flags $1"
				;;
			-n|--dry-run)
				dry_run=1
				;;
			-h|--help|--*)
				usage
				;;
			*)
				break
				;;
		esac
		shift
	done

	if test $# -eq 1
	then
		branch=$1
	elif test $# -gt 1
	then
		die "Invalid number of arguments specified"
	fi

	# For update, either need to a) update only the submodules not changed or
	# b) do a post-order update... Or the submodule can decide

	# Can do something like `cd $toplevel; git submodule update $update_flags -- $path`

	womp_iter() {
		if test -z "$no_fetch"
		then
			say "Fetching $prefix"
			test -z "$dry_run" && git fetch --no-recurse-submodules $remote || :
		fi

		if test -z "$is_top"
		then
			test -z "$dry_run" && branch_iter_checkout
		elif test -n "$branch"
		then
			test -z "$dry_run" && git checkout $branch
		fi
		branch=$(branch_get)

		echo "Branch: $branch"

		if test "$branch" = "HEAD"
		then
			echo "$name is in a detached head state. Can't womp, skipping"
		elif test -z "$is_top" -o -z "$no_top_level_merge"
		then
			if test -n "$force"
			then
				if test -n "$oompf" -a -n "$is_top"
				then
					# This does not need to applied recursively
					# Add an option to skip ignored files? How? Remove everything except for .git? How to do that?
					say "Removing files"
					test -z "$dry_run" && rm -rf ./* || :
				fi
				say "Force checkout"
				test -z "$dry_run" && git checkout -fB $branch $remote/$branch || :
			else
				say "Merge $remote/$branch"
				test -z "$dry_run" && git merge $remote/$branch || :
			fi
		fi

		# Do supermodule things
		# TODO Need more elegant logic here
		# 'recursive' is set by foreach
		if test -e .gitmodules -a \( -n "$is_top" -o -n "$recursive" \)
		then
			# NOTE: $list comes from cmd_foreach
			say "Submodule initialization, sync, and update"
			if test -z "$dry_run"
			then
				git submodule init -- $list
				git submodule sync -- $list
				git submodule update $update_flags -- $list || echo "Update failed... Still continuing"
			fi
		fi
	}

	foreach_read_constrained

	if test -n "$force"
	then
		echo "WARNING: A force womp will do a HARD reset on all of your branches to your remote's branch."
		if test -n "$oompf"
		then
			echo "MORE WARNING: An oompf womp will remove all files before the reset."
			if test -n "$list"
			then
				echo "EVEN MORE WARNING: Constraining your submodule list with an oompf womp will leave certain modules not checked out / initialized."
				echo "It can also leave it hard to womp back your old modules without doing an oompf womp"
			fi
		fi
		echo "Are you sure you want to continue? [Y/n]"
		read choice
		case "$choice" in
			Y|y)
				;;
			*)
				die "Aborting"
				;;
		esac
	fi

	# Now do it, including top-level
	cmd_foreach --top-level $foreach_flags womp_iter
}

command=
while test $# != 0 && test -z "$command"
do
	case "$1" in
	foreach | resync | womp | branch)
		command=$1
		;;
	-q|--quiet)
		GIT_QUIET=1
		;;
	--)
		break
		;;
	-*)
		usage
		;;
	*)
		break
		;;
	esac
	shift
done
test -z "$command" && usage

"cmd_$command" "$@"