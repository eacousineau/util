#!/bin/bash --posix
#
# git-submodule-ext.sh: submodule extensions
#
# Lots of things copied and pasted from git-submodule.sh
# TODO Add in other updates to git-submodule-foreach

# TODO I think subshells are preventing things from properly dying on error. Need to fix
# Yep, they're definitely not dying...

# TODO git `sube refresh --reset` was not resetting to the correct sha. Need a submodule-level 'update' command, or a 'git sube rev-parse' command.

# NOTE: Need to research `update --remote` to look into more functionality
# Follow up - I think the update --remote does what this intended to do. Need to delete this function if it surely does so.
# Use git_submodule_config to ease use of 'branch'
# Transition from '--list LIST' to 'command opts -- LIST' - even in the case of foreach, refresh, etc (will be better than current system of trying to pass var)

shopt -s xpg_echo

dashless=$(basename "$0" | sed -e 's/-/ /')
USAGE="foreach  <command>
	or: $dashless branch [FOREACH_FLAGS] [write | checkout]
	or: $dashless set-url [FOREACH_FLAGS] [--remote REMOTE] [repo | config | base]
	or: $dashless refresh [FOREACH_FLAGS] [--remote REMOTE] [--force] [--clear] [--no-sync] [--no-track] [-N | --no-fetch] [-T | --no-top-level-merge] <branch>
	or: $dashless config-sync [FOREACH_FLAGS]"
OPTIONS_SPEC=

USAGE='[list | branch | set-url | refresh | config-sync]'
LONG_USAGE="\
$dashless list [-c | --constrain]
    list staged submodules in current repo.

$dashless foreach [options] command
    iterate through submodules, using eval subshell (bash) in current process
variables: \$name, \$path, \$sm_ptah, \$toplevel, \$is_top.
be wary of escaping!
    -c, --constrain            Use git-config 'scm.focusGroup' to constrain iteration
    -t, --top-level            Include top-level
    -r, --recursive            Iterate recursively
    -p, --post-order           Do post-order traversal (default is pre-order, top-level first)
    -i, --include-staged       Include staged-only submodules (TODO Make --cached only)
    -k, --keep-going           Keep going if a submodule encounters an error (robust option)
    --no-cd                    Do not cd to submodules directory (TODO Remove)
    --cd-orig                  cd to original repo (if git-new-workdir was used). \
Not applied recursively. Can also specify git-config 'scm.cdOrig'

$dashless set-url [options] [foreach-options] [repo | config | super]
    url synchronization utilities (TODO Add [modules] to the end)
    --remote REMOTE            Use specified remote to retrieve url. Otherwise use default.
    subcommands
      repo                     Read GIT_CONFIG => Set repo's url
        -g, --use-gitmodules   Read .gitmodules instead => Set repo's url and GIT_CONFIG
        -S, --no-sync          With --use-gitmodules, do not copy to GIT_CONFIG
      config                   Read repo's url => Set config's url
        -g, --set-gitmodules   Set url in .gitmodules as well
      super                    Read super url => Set submodule url to \$super/\$path (TODO Deprecate and remove?)

$dashless refresh [options] [foreach-options]
    general purpose updating utility. By default, this will update the supermodules, \
synchronize urls, checkout branches specified in .gitmodules, and attempt to merge \
changes from \$remote's branch of same name.
    -b, --branch BRANCH        Use specificed branch (or commit).
    --remote REMOTE            Use specified remote, default if unspecified
    -f, --force                Use force checkout
    --clear                    Delete all unhidden files of worktree of supermodule and reinitialize submodules. \
Preserves local history if your gitdir's are in \$toplevel/.git/modules, destructive \
otherwise.
    --reset                    Instead of --force / --clear, will update submodule to staged \
SHA1, and reset branch name (if specified) to that SHA.
    --no-sync                  Do not synchronize urls
    --no-track                 Do not set branches to track
    -T, --no-top-level-merge   Do not merge supermodule's remote branch
    -N, --no-fetch             Do not fetch from \$remote
    -n, --dry-run              (Semi-supported) Don't do anythnig, just print

$dashless branch [foreach-options] [write | checkout]
    useful branch operations
    subcommands
      write                    Record submodules branches to .gitmodules. If detached head, will \
delete branch config entry.
      checkout [checkout-options]
                               Checkout branch (if) specified in .gitmodules 

$dashless config-sync
    will go through and add worktree submodules to .gitmodules, writing each one's name, path, \
and url. Useful for making sure submodules added via direct clone or git-new-workdir are properly mapped.

See https://github.com/eacousineau/util/blob/master/SUBMODULES.md for some tips on using."

OPTIONS_SPEC=

export PATH=$PATH:$(git --exec-path) # Put git libexec on path

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

foreach_read_constrained() {
	if test -n "$constrain"
	then
		if test -z "$foreach_list"
		then
			# Ensure that if this command fails, it still returns zero status
			foreach_list=$(git config scm.focusGroup || :)
		else
			echo "Note: List set for parent, only constraining on submodules"
		fi
	fi
}

cmd_list()
{
	# No use for --recursive option right now
	constrain=
	raw=
	# Show only those in working tree?
	while test $# -ne 0
	do
		case "$1" in
		-c|--constrain) constrain=1;;
		--raw) raw=1;;
		*) usage;;
		esac
		shift
	done

	foreach_list=
	if test -n "$constrain"
	then
		foreach_list=$(git config scm.focusGroup || :)
	fi

	module_list $foreach_list |
	while read mode sha1 stage sm_path
	do
		if test -z "$raw"
		then
			echo $sm_path
		else
			echo $mode $sha1 $stage "$sm_path"
		fi
	done
}

# Hack (for now) to pass lists in to foreach
foreach_list=

cmd_foreach()
{
	# parse $args after "submodule ... foreach".
	recursive=
	post_order=
	include_super=
	constrain=
	recurse_flags=--not-top
	is_top=1
	# Change this to '--cached'
	include_staged=
	no_cd=
	cd_orig=$(git config scm.cdOrig || :)
	keep_going=

	while test $# -ne 0
	do
		case "$1" in
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
		--no-cd)
			no_cd=1
			recurse_flags="$recurse_flags $1"
			;;
		-l|--list)
			if test -n "$foreach_list"
			then
				die '$foreach_list supplied but --list was supplied also'
			fi
			foreach_list=$2
			shift
			;;
		--not-top)
			# Less hacky way?
			is_top=
			;;
		-i|--include-staged)
			# Add staged-only flag?
			include_staged=1
			;;
		-k|--keep-going)
			keep_going=1
			recurse_flags="$recurse_flags $1"
			;;
		--cd-orig)
			cd_orig=1
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
	test -z "${prefix+D}" && prefix=
	path=$toplevel

	is_worktree=1

	maybe_die()
	{
		if test -z "$keep_going"
		then
			die Stopping "$@"
		else
			echo Error "$@" Continuing 1>&2
		fi
	}

	super_eval()
	{
		verb=$1
		shift
		say "$(eval_gettext "$verb supermodule '$name'")"
		( eval "$@" ) || maybe_die "at supermodule; script returned non-zero status."
	}

	if test -n "$include_super" -a -z "$post_order"
	then
		super_eval Entering "$@"
	fi
	
	foreach_read_constrained

	module_list $foreach_list |
	while read mode sha1 stage sm_path
	do
		die_if_unmatched "$mode"

		enter_msg="$(eval_gettext "Entering '\$prefix\$sm_path'")"
		staged_msg="$(eval_gettext "Entering staged '\$prefix\$sm_path'")"
		exit_msg="$(eval_gettext "Leaving '\$prefix\$sm_path'")"
		die_msg="$(eval_gettext "at '\$sm_path'; script returned non-zero status.")"
		
		(
			is_top=
			name=$(module_name "$sm_path")
			prefix="$prefix$sm_path/"
			clear_local_git_env
			# we make $path available to scripts ...
			path=$sm_path

			foreach_list=
			if test -e "$sm_path"/.git
			then
				
				is_worktree=1
				if test -z "$no_cd"
				then
					cd "$sm_path"
					if test -n "$cd_orig"
					then
						orig_path="$(git-new-workdir --show-orig . 2> /dev/null)"
						test -n "$orig_path" && cd "$orig_path"
					fi
				fi
				# Contain so things don't spill to post_order
				if test -z "$post_order"
				then
					say "$enter_msg"
					( eval "$@" ) || exit 1
				fi

				if test -n "$recursive"
				then
					(
						test -n "$no_cd" && cd "$sm_path"
						cmd_foreach $recurse_flags "$@"
					) || exit 1
				fi
				
				if test -n "$post_order"
				then
					say "$exit_msg"
					( eval "$@" ) || exit 1
				fi
			elif test -n "$include_staged"
			then
				say "$staged_msg"
				is_worktree=
				is_top=
				( eval "$@" ) || exit 1
			fi
		) <&3 3<&- || maybe_die "$die_msg"
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

branch_remote_checkout() { (
	branch="$1"
	if test -z "${remote+D}"
	then
		remote="$(get_default_remote || :)"
	fi
	if git show-branch $branch > /dev/null 2>&1
	then
		git checkout $branch
	else
		git checkout -t -b $branch "$remote/$branch"
	fi
) }

branch_iter_write() {
	branch=$(branch_get)
	file="$toplevel/.gitmodules"
	var="submodule.$name.branch"
	if ! test "$branch" = "HEAD"
	then
		git config -f $file $var $branch
	else
		# Delete config option
		git config -f $file --unset $var
	fi
	return 0
}
branch_iter_get()
{
	branch="$(git config -f $toplevel/.gitmodules submodule.$name.branch 2>/dev/null)"
}
branch_iter_checkout() {
	if branch_iter_get
	then
		branch_remote_checkout "$branch"
	fi
}

cmd_branch()
{
	# Flags before or after?
	foreach_flags= command=
	while test $# -gt 0
	do
		case $1 in
			-c|-r)
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

cmd_refresh()
{
	# How to get current remote?
	remote=origin track=1 sync=1
	force= clear= no_fetch= recursive= force= foreach_list= constrain=
	reset=
	branch=
	foreach_flags=
	update_flags=--checkout
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
			--clear|--oompf)
				force=1
				clear=1
				;;
			--reset)
				reset=1
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
				update_flags="$update_flags -N"
				;;
			-c|--constrain)
				constrain=1
				;;
			-c|-r)
				foreach_flags="$foreach_flags $1"
				;;
			-n|--dry-run)
				dry_run=1
				;;
			-h|--help|--*)
				usage
				;;
			-b|--branch)
				shift
				branch=$1
				;;
			*)
				break
				;;
		esac
		shift
	done

	if test $# -gt 0
	then
		die "Invalid number of arguments specified"
	fi

	# For update, either need to a) update only the submodules not changed or
	# b) do a post-order update... Or the submodule can decide

	# Can do something like `cd $toplevel; git submodule update $update_flags -- $path`

	refresh_iter() {
		if test -z "$no_fetch"
		then
			say "Fetching $prefix"
			test -z "$dry_run" && git fetch --no-recurse-submodules $remote
		fi

		if test -z "$is_top"
		then
			# Show branch if it's a dry run?
			if test -z "$dry_run"
			then
				if branch_iter_get
				then
					if test -n "$reset"
					then
						# Assuming that submodule is already on update'd sha
						echo "\tOld sha for $branch: $(git rev-parse --short $branch)"
						echo "\tResetting to current sha: $(git rev-parse --short HEAD)"
						git checkout -B "$branch"
					else
						branch_remote_checkout "$branch"
					fi
				fi
			fi
		elif test -n "$branch"
		then
			if test -z "$dry_run"
			then
				if test -n "$force"
				then
					# TODO This is redundant here. Make sure it works well with code down below.
					say "Force checkout"
					test -z "$dry_run" && git checkout -fB $branch $remote/$branch
				else
					# TODO Errors out if branch is ambiguous due to multiple origins
					git checkout $branch
				fi
			fi
		fi
		branch=$(branch_get)

		if test "$branch" = "HEAD"
		then
			echo "$name is in a detached head state. Can't refresh, skipping"
		elif test -z "$is_top" -o -z "$no_top_level_merge"
		then
			if test -n "$force"
			then
				if test -n "$clear" -a -n "$is_top"
				then
					# This does not need to applied recursively
					# Add an option to skip ignored files? How? Remove everything except for .git? How to do that?
					say "Removing files"
					test -z "$dry_run" && rm -rf ./*
				fi
				say "Force checkout"
				test -z "$dry_run" && git checkout -fB $branch $remote/$branch
			elif test -z "$reset" -o -n "$is_top"
			then
				say "Merge $remote/$branch"
				test -z "$dry_run" && git merge $remote/$branch
			fi
		fi

		# Do supermodule things
		# TODO Need more elegant logic here
		# 'recursive' is set by foreach
		if test -e .gitmodules -a \( -n "$is_top" -o -n "$recursive" \)
		then
			# NOTE: $foreach_list comes from cmd_foreach
			say "Submodule initialization, sync, and update"
			if test -z "$dry_run"
			then
				git submodule init -- $foreach_list
				test -n "$sync" && git submodule sync -- $foreach_list
				git submodule update $update_flags -- $foreach_list || echo "Update failed... Still continuing"
			fi
		fi
	}

	foreach_read_constrained

	ask=
	if test -n "$force"
	then
		echo "WARNING: A force refresh will do a HARD RESET on all of your branches to your remote's branch."
		if test -n "$clear"
		then
			echo "MORE WARNING: An clear refresh will remove all files before the reset."
			if test -n "$foreach_list"
			then
				echo "EVEN MORE WARNING: Constraining your submodule list with an clear refresh will leave certain modules not checked out / initialized."
				echo "It can also leave it hard to refresh back your old modules without doing an clear refresh"
			fi
		fi
		ask=1
	fi
	if test -n "$reset"
	then
		test -z "$force" || die "Cannot --reset and --force"
		echo "CAUTION: A reset refresh will RESET the branch name specified in .gitmodules to the commits pointed to by the supermodule."
		echo "This will CHANGE what your local branch points to."
		ask=1
	fi

	if test -n "$ask"
	then
		echo "Are you sure you want to continue? [y/N]"
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
	cmd_foreach --top-level $foreach_flags refresh_iter
}

# TODO Add below functionality, for syncing with other computers via git-daemon
# git sfer 'echo $(cd $toplevel && cd $(git rev-parse --git-dir) && pwd)/modules/$path'

# Add 'write' / 'sub' to write submodule's url to .gitmodules
# Good words for doing that?

cmd_set_url()
{
	remote=
	foreach_flags="--include-staged --no-cd"

	while test $# -ne 0
	do
		case $1 in
			-r|--recursive|-c|--constrain)
				foreach_flags="$foreach_flags $1"
				;;
			-l|--list)
				foreach_list="$2"
				shift
				;;
			--remote)
				remote=$2
				shift
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

	test $# -eq 0 && usage

	case $1 in
		repo | config | super)
			command=$1
			shift
			;;
		base)
			command=super
			shift
			;;
		*)
			usage
			;;
	esac
	
	# --include-staged option is somehting to be wary of...
	set_url_${command}_setup "$@"
	cmd_foreach $foreach_flags set_url_${command}_iter
}

set_url_iter() {
	if test -z "$remote"
	then
		if test -n "$is_worktree"
		then
			# Allow submodules to have different default remotes?
			remote=$(cd "$sm_path" && get_default_remote || :) # Does not return successful at times?
		else
			remote=origin
		fi
	fi
}

set_url_config_setup() {
	set_gitmodules=
	while test $# -gt 0
	do
		case $1 in
		-g|--set-gitmodules)
			set_gitmodules=1
			;;
		*)
			break
			;;
		esac
		shift
	done
}
set_url_config_iter() {
	set_url_iter
	if test -n "$is_worktree"
	then
		sm_url=$(cd "$sm_path" && git config "remote.$remote.url")
		set_module_config_url
	fi
}

set_url_super_setup() {
	# Same options
	set_url_config_setup
}
set_url_super_iter() {
	set_url_iter
	# Redundant :/
	topurl=$(git config remote."$remote".url)
	sm_url=$topurl/$path
	
	set_module_config_url
	noun="toplevel"
	set_module_url_if_worktree
}

set_url_repo_setup() {
	use_gitmodules=
	no_sync=
	while test $# -gt 0
	do
		case $1 in
		-g|--use-gitmodules)
			use_gitmodules=1
			;;
		-S|--no-sync)
			no_sync=1
			;;
		*)
			break
			;;
		esac
		shift
	done
}
set_url_repo_iter() {
	set_url_iter
	key="submodule.$name.url"
	if test -n "$use_gitmodules"
	then
		sm_url=$(git config -f .gitmodules "$key")
		noun=".gitmodules"
		if test -z "$no_sync"
		then
			git config "$key" "$sm_url"
			say "Synced .git/config url to '$sm_url' (from .gitmodules)"
		fi
	else
		sm_url=$(cd $toplevel && git config "$key")
		noun=".git/config"
	fi
	set_module_url_if_worktree
}

# set_url_sync_setup() { }
# set_url_sync_iter() {
# 	set_url_iter
# 	# Copy and paste :/
# 	key="submodule.$name.url"
# 	sm_url=$(git config -f .gitmodules "$key")
# 	git config "$key" "$sm_url"
# 	say "Synced .git/config url to '$sm_url' (from .gitmodules)"
# }

set_module_url_if_worktree() {
	if test -n "$is_worktree"
	then
		cd "$sm_path"
		if git config remote."$remote".url > /dev/null
		then
			say "Set remote '$remote' url to '$sm_url' (from $noun)"
			git remote set-url "$remote" "$sm_url"
		else
			say "Adding remote '$remote' with url '$sm_url' (from $noun)"
			git remote add "$remote" "$sm_url"
		fi
	fi
}

set_module_config_url() {
	# Add check to see if mapping exists?

	key="submodule.$name.url"
	git config "$key" "$sm_url"
	nouns=".git/config"

	if test -n "$set_gitmodules"
	then
		nouns="$nouns and .gitmodules"
		git config -f .gitmodules "$key" "$sm_url"
	fi
	say "Set $nouns url to '$sm_url'"
}

cmd_config_sync() {
	remote=
	foreach_flags=""

	echo "Updating entires in .gitmodules..."
	# TODO Will have to iterate using custom iteration. This will not work yet (since submodule has no mapping)
	#die "Not yet implemented"

	while test $# -ne 0
	do
		case $1 in
			-r|--recursive|-c|--constrain)
				foreach_flags="$foreach_flags $1"
				;;
			--remote)
				remote=$2
				shift
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
	
	# --include-staged option is somehting to be wary of...
	GIT_QUIET=1 cmd_foreach $foreach_flags config_sync_iter
}

config_sync_iter() {
	# Just overwrite everything in .gitmodules
	test -z "$remote" && remote=$(get_default_remote || :)
	name=$(basename $PWD)
	echo "Adding $name"
	branch=$(git bg)
	url=$(git config remote.$remote.url)
	cd $toplevel
	cmd="git config -f .gitmodules submodule.$name"
	${cmd}.path $name
	${cmd}.url $url
}

command=
while test $# != 0 && test -z "$command"
do
	case "$1" in
	foreach | refresh | branch | list)
		command=$1
		;;
	set-url)
		command="set_url"
		;;
	womp)
		command="refresh" # Compatibility
		;;
	config-sync)
		command="config_sync"
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