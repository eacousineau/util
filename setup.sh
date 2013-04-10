#!/bin/bash

# Too lazy for sh

test $# -eq 0 && echo "Need to supply directory (absolute path) to put this stuff in." && exit 0

path=$(dirname $BASH_SOURCE)

cd $path

dir=$1
shift

linkerade()
{
	new=$(basename $1 .sh)
	src=~+/$1
	dest=$dir/$new
	echo "Linking $src -> $dest"
	ln -s $src $dest
}

if test $# -eq 0
then
	# Get all shell scripts (except for setup)
	for script in $(dir *.sh)
	do
		test "$script" = "setup.sh" && continue
		linkerade $script
	done
else
	for script in $@
	do
		linkerade $script
	done
fi
