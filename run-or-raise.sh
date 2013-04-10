#!/bin/bash

# Adapted from: http://vickychijwani.github.com/2012/04/15/blazing-fast-application-switching-in-linux/

use_aliases=

while true
do
	case $1 in
		--use-aliases)
			# Much slower
			use_aliases=1
			;;
		*)
			break
			;;
	esac
	shift
done

# http://stackoverflow.com/a/1854031/170413
cmd=$1

while [ $# -gt 0 ]
do
	wmctrl -x -a $1 && exit 0
	shift
done

[ -n "$use_aliases" ] && source ~/.bash_aliases
eval $cmd