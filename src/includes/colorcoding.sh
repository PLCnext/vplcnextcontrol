#!/bin/bash
#---------------------------------------------
# Copyright Phoenix Contact GmbH & Co. KG
#---------------------------------------------
useColor=true
if [ "$NO_COLOR" = "1" ] || [ ! -t 1 ]; then
	useColor=false
fi

color() {
	# if stdout is not a terminal, then don't do color codes.
	if [ "$useColor" = "false" ]; then
		return 0
	fi
	codes=
	if [ "$1" = 'bold' ]; then
		codes='1'
		shift
	fi
	if [ "$#" -gt 0 ]; then
		code=
		case "$1" in
			# see https://en.wikipedia.org/wiki/ANSI_escape_code#Colors
			black) code=30 ;;
			red) code=31 ;;
			green) code=32 ;;
			yellow) code=33 ;;
			blue) code=34 ;;
			magenta) code=35 ;;
			cyan) code=36 ;;
			white) code=37 ;;
		esac
		if [ "$code" ]; then
			codes="${codes:+$codes;}$code"
		fi
	fi
	printf '\033[%sm' "$codes"
}

wrap_color() {
	text="$1"
	shift
	color "$@"
	printf '%s' "$text"
	color reset
	echo
}

wrap_good() {
	echo "$(wrap_color "$1" white): $(wrap_color "$2" green)"
}

wrap_bad() {
	echo "$(wrap_color "$1" bold): $(wrap_color "$2" bold red)"
}

wrap_warning() {
	wrap_color >&2 "$*" red
}