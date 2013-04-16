#!/bin/sh
#
# git-sfe.sh: submodule foreach with option to include supermodule
#
# Lots of things copied and pasted from git-submodule.sh

# Can't get something this to work: `git fer git commit -m "Some long message"` -- need to figure this out

dashless=$(basename "$0" | sed -e 's/-/ /')
USAGE="[-c | --constrain] [-t | --top-level] [-r | --recursive] [-p | --post-order] <command>"
OPTIONS_SPEC=
. git-sh-setup
. git-sh-i18n
. git-parse-remote
require_work_tree

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

# TODO Match with updates to git-submodule-foreach
cmd_foreach()
{
	# parse $args after "submodule ... foreach".
	recursive=
	post_order=
	include_super=
	constrain=
	while test $# -ne 0
	do
		case "$1" in
		-q|--quiet)
			GIT_QUIET=1
			;;
		-r|--recursive)
			recursive=1
			;;
		-p|--post-order)
			post_order=1
			;;
		-c|--constrain)
			constrain=1
			;;
		-t|--top-level)
			include_super=1
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
	path=$toplevel

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

	recurse_flags=""
	focus_group=
	if test -n "$constrain"
	then
		focus_group=$(git config scm.focusGroup)
		recurse_flags="$recurse_flags --constrain"
	fi

	test -n "$post_order" && recurse_flags="$recurse_flags --post-order"
	test -n "$recursive" && recurse_flags="$recurse_flags --recursive"

	module_list $focus_group |
	while read mode sha1 stage sm_path
	do
		die_if_unmatched "$mode"
		if test -e "$sm_path"/.git
		then
			enter_msg="$(eval_gettext "Entering '\$prefix\$sm_path'")"
			exit_msg="$(eval_gettext "Leaving '\$prefix\$sm_path'")"
			die_msg="$(eval_gettext "Stopping at '\$sm_path'; script returned non-zero status.")"
			(
				name=$(module_name "$sm_path")
				prefix="$prefix$sm_path/"
				clear_local_git_env
				# we make $path available to scripts ...
				path=$sm_path
				cd "$sm_path" &&
				if test -z "$post_order"
				then
					say "$enter_msg"
					eval "$@" || die "$die_msg"
				fi &&
				if test -n "$recursive"
				then
					cmd_foreach $recurse_flags "$@"
				fi &&
				if test -n "$post_order"
				then
					say "$exit_msg" &&
					eval "$@" || die "$die_msg"
				fi
			) <&3 3<&- ||
			die "$die_msg"
		fi
	done

	if test -n "$include_super" -a -n "$post_order"
	then
		super_eval Leaving "$@"
	fi
}

cmd_foreach "$@"