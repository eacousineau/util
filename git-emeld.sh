#!/bin/sh

# Variant of git-meld that uses git-new-workdir to compare so you can edit and commit changes on those branchs
# TODO Three-way merge?

bin_path=$0
bin=$(basename $bin_path)

usage()
{
	echo "Usage: $bin [-t|--tool TOOL] [-d|--dir DIR] [-r|--remove] [-v|--verbose] REPO REV_A REV_B"
	exit $1
}

die()
{
	echo $1 >&2
	exit 1
}

tool=meld
stdout=/dev/null
stderr=/dev/stderr
remove=
dir=

while [ $# -gt 0 ]
do
	case $1 in
		-t|--tool)
			tool=$2
			shift
			;;
		-v|--verbose)
			stdout=/dev/stdout
			;;
		-h|--help)
			usage 0
			;;
		-r|--remove)
			remove=1
			;;
		-d|--dir)
			dir=$2
			shift
			;;
		*)
			break
			;;
	esac
	shift
done

repo=$1
rev_a=$2
rev_b=$3

# Need a way to resolve
rev_label_resolve()
{
	# NOTE: Changes directory
	cd $1
	ref=$(git rev-parse --abbrev-ref $2)
	if test "$ref" = "HEAD" -o -z "$ref"
	then
		# Use hash
		ref=$(git rev-parse --short $2)
	fi
	echo $ref
}

rev_label_a=$(rev_label_resolve $repo $rev_a)
rev_label_b=$(rev_label_resolve $repo $rev_b)

if test "$rev_label_a" = "$rev_label_b"
then
	echo "Both commits are the same ($rev_label_a). Aborting."
	usage 1
fi

repo_setup()
{
	new=$1
	branch=$2
	# Make leading structure for slashy branches
	mkdir -p $(dirname $new)
	git-new-workdir $repo $new $branch > $stdout 2> $stderr || die "Error with git-new-workdir"
}

if test -z "$dir"
then
	# Create temporary directory
	template="/tmp/git-emeld.XXXXX"
	dir=$(mktemp -d $template)
fi
repo_a=$dir/$rev_label_a
repo_b=$dir/$rev_label_b

echo "A ($rev_label_a)\n\t$repo_a"
echo "B ($rev_label_b)\n\t$repo_b"

repo_setup $repo_a $rev_a
repo_setup $repo_b $rev_b

$tool $repo_a $repo_b

if test -n "$remove"
then
	echo "Removing directory: $dir"
	rm -rf $dir
else
	echo "Keeping directory: $dir"
fi