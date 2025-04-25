#!/bin/bash
#---------------------------------------------
# Copyright Phoenix Contact GmbH & Co. KG
#---------------------------------------------
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Iterate through all files in the directory
for file in "${DIR}/includes"/*; do
    if [[ -f "$file" && ! -x "$file" ]]; then
        echo "ERROR" 
        echo "File $file is not executable."
        exit 1
    fi
done

# Version 1.3
EXITCODE=0

# bits of this were adapted from lxc-checkconfig
# see also https://github.com/lxc/lxc/blob/lxc-1.0.2/src/lxc/lxc-checkconfig.in

possibleConfigs="
	/proc/config.gz
	/boot/config-$(uname -r)
	/usr/src/linux-$(uname -r)/.config
	/usr/src/linux/.config
"

if [ $# -gt 0 ]; then
	CONFIG="$1"
else
	: "${CONFIG:=/proc/config.gz}"
fi

if ! command -v zgrep > /dev/null 2>&1; then
	zgrep() {
		zcat "$2" | grep "$1"
	}
fi

source "${DIR}/includes/colorcoding.sh"

kernelVersion="$(uname -r)"
kernelMajor="${kernelVersion%%.*}"
kernelMinor="${kernelVersion#$kernelMajor.}"
kernelMinor="${kernelMinor%%.*}"

is_set() {
	zgrep "CONFIG_$1=[y|m]" "$CONFIG" > /dev/null
}
is_set_in_kernel() {
	zgrep "CONFIG_$1=y" "$CONFIG" > /dev/null
}
is_set_as_module() {
	zgrep "CONFIG_$1=m" "$CONFIG" > /dev/null
}

check_flag() {
	if is_set_in_kernel "$1"; then
		wrap_good "CONFIG_$1" 'enabled'
	elif is_set_as_module "$1"; then
		wrap_good "CONFIG_$1" 'enabled (as module)'
	else
		wrap_bad "CONFIG_$1" 'missing'
		EXITCODE=1
	fi
}

check_flags() {
	for flag in "$@"; do
		printf -- '- '
		check_flag "$flag"
	done
}

check_command() {
	if command -v "$1" > /dev/null 2>&1; then
		wrap_good "$1 command" 'available'
	else
		wrap_bad "$1 command" 'missing'
		EXITCODE=1
	fi
}

check_device() {
	if [ -c "$1" ]; then
		wrap_good "$1" 'present'
	else
		wrap_bad "$1" 'missing'
		EXITCODE=1
	fi
}

config() {


	if [ ! -e "$CONFIG" ]; then
		wrap_warning "warning: $CONFIG does not exist, searching other paths for kernel config ..."
		for tryConfig in $possibleConfigs; do
			if [ -e "$tryConfig" ]; then
				CONFIG="$tryConfig"
				break
			fi
		done
		if [ ! -e "$CONFIG" ]; then
			wrap_warning "error: cannot find kernel config"
			wrap_warning "  try running this script again, specifying the kernel config:"
			wrap_warning "    CONFIG=/path/to/kernel/.config $0 or $0 /path/to/kernel/.config"
			exit 1
		fi
	fi
	echo "-------------------------------------------------------------"
	wrap_color "Checking kernel configuration for PLCnext Virtual Control" yellow
	echo "-------------------------------------------------------------"
	echo
	wrap_color "info: reading kernel config from $CONFIG ..." white
	echo

	echo 'Generally Necessary:'
	
	echo
	
	echo  "Necessary Tools: "  
	if which iptables >/dev/null 2>&1; then
    	echo -n "  - iptables: "  
		wrap_color  "installed." green
	else
		echo -n "  - iptables: "  
    	wrap_color "not installed." red
	fi

	if which getfacl >/dev/null 2>&1; then
    	echo -n "  - acl: "  
		wrap_color  "installed." green
	else
		echo -n "  - acl: "  
    	wrap_color "not installed." red
	fi

	if [ "$(cat /sys/module/apparmor/parameters/enabled 2> /dev/null)" = 'Y' ]; then
		printf -- '  - '
		if command -v apparmor_parser > /dev/null 2>&1; then
			wrap_good 'apparmor' 'enabled and tools installed'
		else
			wrap_bad 'apparmor' 'enabled, but apparmor_parser missing'
			printf '    '
			if command -v apt-get > /dev/null 2>&1; then
				wrap_color '(use "apt-get install apparmor" to fix this)'
			elif command -v yum > /dev/null 2>&1; then
				wrap_color '(your best bet is "yum install apparmor-parser")'
			else
				wrap_color '(look for an "apparmor" package for your distribution)'
			fi
			EXITCODE=1
		fi
	fi

    echo

	echo 'Network Drivers:'
	echo '  Optional (for encrypted networks):'
	check_flags CRYPTO CRYPTO_ALGAPI CRYPTO_AEAD CRYPTO_HASH CRYPTO_RNG CRYPTO_GCM CRYPTO_SEQIV CRYPTO_GHASH CRYPTO_CBC CRYPTO_CTR CRYPTO_ECB CRYPTO_MD4 CRYPTO_MD5 CRYPTO_SHA256 CRYPTO_SHA512 CRYPTO_LIB_SHA256 CRYPTO_AES | sed 's/^/  /'
    if [ "$kernelMajor" -lt 5 ] || [ "$kernelMajor" -eq 5 -a "$kernelMinor" -le 3 ]; then 
		check_flags INET_XFRM_MODE_TRANSPORT | sed 's/^/      /'
	fi
	echo "  - \"$(wrap_color 'macvlan' yellow)\":"
	check_flags MACVLAN | sed 's/^/    /'

	# only fail if no storage drivers available
	CODE=${EXITCODE}
	EXITCODE=0
	STORAGE=1

	echo '- Storage Drivers:'

	echo "  - \"$(wrap_color 'overlay' yellow)\":"
	check_flags OVERLAY_FS | sed 's/^/    /'
	[ "$EXITCODE" = 0 ] && STORAGE=0
	EXITCODE=0

	echo

	printf -- '- '
	if [ "$(stat -f -c %t /sys/fs/cgroup 2> /dev/null)" = '63677270' ]; then
		wrap_good 'cgroup hierarchy' 'cgroupv2'
		cgroupv2ControllerFile='/sys/fs/cgroup/cgroup.controllers'
		if [ -f "$cgroupv2ControllerFile" ]; then
			echo '  Controllers:'
			for controller in cpu cpuset io memory pids; do
				if grep -qE '(^| )'"$controller"'($| )' "$cgroupv2ControllerFile"; then
					echo "  - $(wrap_good "$controller" 'available')"
				else
					echo "  - $(wrap_bad "$controller" 'missing')"
				fi
			done
		else
			wrap_bad "$cgroupv2ControllerFile" 'nonexistent??'
		fi
		# TODO find an efficient way to check if cgroup.freeze exists in subdir
	else
		cgroupSubsystemDir="$(sed -rne '/^[^ ]+ ([^ ]+) cgroup ([^ ]*,)?(cpu|cpuacct|cpuset|devices|freezer|memory)[, ].*$/ { s//\1/p; q }' /proc/mounts)"
		cgroupDir="$(dirname "$cgroupSubsystemDir")"
		if [ -d "$cgroupDir/cpu" ] || [ -d "$cgroupDir/cpuacct" ] || [ -d "$cgroupDir/cpuset" ] || [ -d "$cgroupDir/devices" ] || [ -d "$cgroupDir/freezer" ] || [ -d "$cgroupDir/memory" ]; then
			echo "$(wrap_good 'cgroup hierarchy' 'properly mounted') [$cgroupDir]"
			echo $(wrap_color "Using cgroupv1, but must use cgroupv2 and systemd for Virtual PLCnext Control" bold red)
			echo $(wrap_color "Using cgroupv1, but must use cgroupv2 and systemd for Virtual PLCnext Control" bold red)
			echo $(wrap_color "Using cgroupv1, but must use cgroupv2 and systemd for Virtual PLCnext Control" bold red)
		else
			if [ "$cgroupSubsystemDir" ]; then
				echo "$(wrap_bad 'cgroup hierarchy' 'single mountpoint!') [$cgroupSubsystemDir]"
			else
				wrap_bad 'cgroup hierarchy' 'nonexistent??'
				wrap_bad "Virtual PLCnext Control needs cgroupv2 and systemd."
			fi
			EXITCODE=1
			echo "    $(wrap_color '(see https://github.com/tianon/cgroupfs-mount)' yellow)"
		fi
	fi

	echo " $(wrap_color '( cpu will be missing when CONFIG_CGROUP_SCHED is DISABLED )' bold blue)."

	echo

	check_flags \
		NAMESPACES NET_NS PID_NS IPC_NS UTS_NS USER_NS USER_NS 
	
	echo 

	if ! is_set EXT4_USE_FOR_EXT2; then
		check_flags EXT3_FS EXT3_FS_POSIX_ACL EXT3_FS_SECURITY
		if ! is_set EXT3_FS || ! is_set EXT3_FS_XATTR || ! is_set EXT3_FS_POSIX_ACL || ! is_set EXT3_FS_SECURITY; then
			echo "    $(wrap_color '(enable these ext3 configs if you are using ext3 as backing filesystem)' bold black)"
		fi
	fi

	check_flags EXT4_FS EXT4_FS_POSIX_ACL EXT4_FS_SECURITY
	if ! is_set EXT4_FS || ! is_set EXT4_FS_POSIX_ACL || ! is_set EXT4_FS_SECURITY; then
		if is_set EXT4_USE_FOR_EXT2; then
			echo "    $(wrap_color 'enable these ext4 configs if you are using ext3 or ext4 as backing filesystem' bold black)"
		else
			echo "    $(wrap_color 'enable these ext4 configs if you are using ext4 as backing filesystem' bold black)"
		fi
	fi

	echo

	check_flags \
		CGROUPS CGROUP_CPUACCT CGROUP_DEVICE CGROUP_FREEZER CPUSETS MEMCG \
		KEYS \
		VETH \
		FUSE_FS \
        NET_PTP_CLASSIFY \
		SECCOMP \
		SECCOMP_FILTER \
		HUGETLB_PAGE \
		CGROUP_HUGETLB
	
	check_flag CGROUP_SCHED

	echo " $(wrap_color '( CONFIG_CGROUP_SCHED can be DISABLED to enhance realtime)' bold blue)."

	echo

	check_flags \
        IP_SET IP_SET_BITMAP_IP IP_SET_BITMAP_IPMAC IP_SET_BITMAP_PORT IP_SET_HASH_IP IP_SET_HASH_IPPORT IP_SET_HASH_IPPORTNET IP_SET_HASH_NET \
        IP_SET_HASH_NETPORT IP_SET_LIST_SET 

	echo

	check_flags \
		SECURITY_APPARMOR SECURITY_APPARMOR_HASH SECURITY_APPARMOR_HASH_DEFAULT DEFAULT_SECURITY_APPARMOR
	
	echo
	
	check_flags	POSIX_MQUEUE
	# (POSIX_MQUEUE is required for bind-mounting /dev/mqueue into containers)

	if [ "$kernelMajor" -lt 4 ] || ([ "$kernelMajor" -eq 4 ] && [ "$kernelMinor" -lt 8 ]); then
		check_flags DEVPTS_MULTIPLE_INSTANCES
	fi

	if [ "$kernelMajor" -lt 5 ] || [ "$kernelMajor" -eq 5 -a "$kernelMinor" -le 1 ]; then
		check_flags NF_NAT_IPV4
	fi

	if [ "$kernelMajor" -lt 5 ] || [ "$kernelMajor" -eq 5 -a "$kernelMinor" -le 2 ]; then
		check_flags NF_NAT_NEEDED
	fi
	# check availability of BPF_CGROUP_DEVICE support
	if [ "$kernelMajor" -ge 5 ] || ([ "$kernelMajor" -eq 4 ] && [ "$kernelMinor" -ge 15 ]); then
		check_flags CGROUP_BPF
	fi

	EXITCODE=0

	echo

	check_flags PREEMPT_RT 
	if [ "$EXITCODE" -eq 1 ]; then
		echo " $(wrap_color '(PREEMPT_RT is not enabled and possibly affects SCHED_FIFO as well as SCHED_RR )' bold red)."
	fi
	echo " $(wrap_color '( CONFIG_RT_GROUP_SCHED must be DISABLED)' bold blue)."
	echo

    echo '- Networking options:'
    check_flags NET NET_INGRESS SKB_EXTENSIONS PACKET UNIX UNIX_SCM \
        INET IP_MULTICAST IP_ADVANCED_ROUTER IP_MULTIPLE_TABLES IP_ROUTE_MULTIPATH \
        IP_ROUTE_CLASSID NET_IPIP NET_IP_TUNNEL IP_MROUTE_COMMON IP_MROUTE SYN_COOKIES \
        NET_UDP_TUNNEL NET_FOU NET_FOU_IP_TUNNELS INET_TUNNEL TCP_CONG_CUBIC \
        IPV6 INET6_TUNNEL \
        IPV6_TUNNEL IPV6_FOU IPV6_FOU_TUNNEL IPV6_MULTIPLE_TABLES \
        NET_PTP_CLASSIFY NETWORK_PHY_TIMESTAMPING NETFILTER NETFILTER_ADVANCED BRIDGE_NETFILTER | sed 's/^/  /'
    echo
	echo '- Xtables targets:'
    check_flags NETFILTER_XT_MATCH_BPF NETFILTER_XT_TARGET_CONNMARK NETFILTER_XT_NAT NETFILTER_XT_TARGET_RATEEST \
        NETFILTER_XT_TARGET_REDIRECT NETFILTER_XT_TARGET_MASQUERADE NETFILTER_XT_TARGET_TEE NETFILTER_XT_TARGET_TPROXY NETFILTER_XT_TARGET_TCPMSS | sed 's/^/  /'
	echo
    echo '- Xtables matches:'
    check_flags NETFILTER_XT_MATCH_ADDRTYPE NETFILTER_XT_MATCH_BPF NETFILTER_XT_MATCH_CGROUP NETFILTER_XT_MATCH_COMMENT \
        NETFILTER_XT_MATCH_CONNLIMIT NETFILTER_XT_MATCH_CONNMARK NETFILTER_XT_MATCH_CONNTRACK NETFILTER_XT_MATCH_CPU \
        NETFILTER_XT_MATCH_DEVGROUP NETFILTER_XT_MATCH_DSCP NETFILTER_XT_MATCH_ECN NETFILTER_XT_MATCH_ESP NETFILTER_XT_MATCH_HELPER \
        NETFILTER_XT_MATCH_IPRANGE NETFILTER_XT_MATCH_L2TP NETFILTER_XT_MATCH_LENGTH NETFILTER_XT_MATCH_LIMIT NETFILTER_XT_MATCH_MAC NETFILTER_XT_MATCH_MARK \
        NETFILTER_XT_MATCH_MULTIPORT NETFILTER_XT_MATCH_NFACCT NETFILTER_XT_MATCH_OWNER NETFILTER_XT_MATCH_PHYSDEV NETFILTER_XT_MATCH_PKTTYPE \
        NETFILTER_XT_MATCH_RATEEST NETFILTER_XT_MATCH_REALM NETFILTER_XT_MATCH_RECENT NETFILTER_XT_MATCH_SOCKET \
        NETFILTER_XT_MATCH_STATE NETFILTER_XT_MATCH_STATISTIC NETFILTER_XT_MATCH_STRING | sed 's/^/  /'
	echo 
    echo '- Core Netfilter Configuration:'
    check_flags  NETFILTER_INGRESS NETFILTER_NETLINK NETFILTER_FAMILY_BRIDGE NETFILTER_FAMILY_ARP NETFILTER_NETLINK_ACCT NETFILTER_NETLINK_QUEUE \
        NETFILTER_NETLINK_OSF NF_CONNTRACK NETFILTER_CONNCOUNT NF_CONNTRACK_MARK NF_CONNTRACK_EVENTS \
        NF_CONNTRACK_TIMESTAMP NF_CONNTRACK_LABELS NF_CT_PROTO_UDPLITE NF_CONNTRACK_FTP \
        NF_CONNTRACK_BROADCAST NF_CONNTRACK_NETBIOS_NS NF_CONNTRACK_SANE NF_CONNTRACK_SIP NF_CT_NETLINK NF_NAT \
        NF_NAT_FTP NF_NAT_SIP NF_NAT_REDIRECT NF_NAT_MASQUERADE NETFILTER_SYNPROXY NF_TABLES NF_TABLES_INET NF_TABLES_NETDEV \
        NFT_CT NFT_LOG NFT_LIMIT NFT_MASQ NFT_REDIR NFT_NAT NFT_TUNNEL NFT_QUEUE NFT_REJECT NFT_REJECT_INET NFT_COMPAT NFT_HASH \
        NFT_FIB NFT_SOCKET NFT_OSF NFT_TPROXY NFT_SYNPROXY NF_DUP_NETDEV NFT_DUP_NETDEV NFT_FWD_NETDEV NF_FLOW_TABLE_INET NF_FLOW_TABLE NETFILTER_XTABLES \
        NETFILTER_XT_MARK NETFILTER_XT_CONNMARK NETFILTER_XT_SET | sed 's/^/  /'
    echo
    echo '- IP: Netfilter Configuration:'
    check_flags NF_DEFRAG_IPV4 NF_TABLES_IPV4 NFT_REJECT_IPV4 NF_TABLES_ARP NF_REJECT_IPV4 \
        NF_NAT_SNMP_BASIC IP_NF_IPTABLES IP_NF_MATCH_AH IP_NF_MATCH_ECN IP_NF_MATCH_RPFILTER IP_NF_FILTER IP_NF_TARGET_REJECT \
        IP_NF_NAT IP_NF_TARGET_MASQUERADE IP_NF_TARGET_NETMAP IP_NF_TARGET_REDIRECT IP_NF_MANGLE IP_NF_TARGET_ECN IP_NF_TARGET_TTL IP_NF_RAW IP_NF_ARPTABLES \
        IP_NF_ARPFILTER IP_NF_ARP_MANGLE | sed 's/^/  /'
    echo
    echo '- IPv6: Netfilter Configuration:'
    check_flags NF_TABLES_IPV6 NFT_REJECT_IPV6 NF_REJECT_IPV6 IP6_NF_IPTABLES \
        IP6_NF_MATCH_EUI64 IP6_NF_MATCH_FRAG IP6_NF_MATCH_OPTS IP6_NF_MATCH_IPV6HEADER IP6_NF_MATCH_RT IP6_NF_FILTER \
        IP6_NF_MANGLE IP6_NF_RAW NF_DEFRAG_IPV6 | sed 's/^/  /'
    echo
    echo '- Bridge Configuration:'
    check_flags NF_TABLES_BRIDGE BRIDGE_NF_EBTABLES \
        STP BRIDGE BRIDGE_IGMP_SNOOPING VLAN_8021Q LLC | sed 's/^/  /'
	echo

    echo 'Optional Features:'
	{
		check_flags CGROUP_PIDS
	}
	{
		check_flags MEMCG_SWAP
		# Kernel v5.8+ removes MEMCG_SWAP_ENABLED.
		if [ "$kernelMajor" -lt 5 ] || [ "$kernelMajor" -eq 5 -a "$kernelMinor" -le 8 ]; then
			CODE=${EXITCODE}
			check_flags MEMCG_SWAP_ENABLED
			# FIXME this check is cgroupv1-specific
			if [ -e /sys/fs/cgroup/memory/memory.memsw.limit_in_bytes ]; then
				echo "    $(wrap_color '(cgroup swap accounting is currently enabled)' bold black)"
				EXITCODE=${CODE}
			elif is_set MEMCG_SWAP && ! is_set MEMCG_SWAP_ENABLED; then
				echo "    $(wrap_color '(cgroup swap accounting is currently not enabled, you can enable it by setting boot option "swapaccount=1")' bold black)"
			fi
		else
			# Kernel v5.8+ enables swap accounting by default.
			echo "    $(wrap_color '(cgroup swap accounting is currently enabled)' bold black)"
		fi
	}
	{
		if is_set LEGACY_VSYSCALL_NATIVE; then
			printf -- '- '
			wrap_bad "CONFIG_LEGACY_VSYSCALL_NATIVE" 'enabled'
			echo "    $(wrap_color '(dangerous, provides an ASLR-bypassing target with usable ROP gadgets.)' bold black)"
		elif is_set LEGACY_VSYSCALL_EMULATE; then
			printf -- '- '
			wrap_good "CONFIG_LEGACY_VSYSCALL_EMULATE" 'enabled'
		fi
	}

	if [ "$kernelMajor" -lt 4 ] || ([ "$kernelMajor" -eq 4 ] && [ "$kernelMinor" -le 5 ]); then
		check_flags MEMCG_KMEM
	fi

	if [ "$kernelMajor" -lt 3 ] || ([ "$kernelMajor" -eq 3 ] && [ "$kernelMinor" -le 18 ]); then
		check_flags RESOURCE_COUNTERS
	fi

	if [ "$kernelMajor" -lt 5 ]; then
		check_flags IOSCHED_CFQ CFQ_GROUP_IOSCHED
	fi

	echo

	check_limit_over() {
		if [ "$(cat "$1")" -le "$2" ]; then
			wrap_bad "- $1" "$(cat "$1")"
			wrap_color "    This should be set to at least $2, for example set: sysctl -w kernel/keys/root_maxkeys=1000000" bold black
			EXITCODE=1
		else
			wrap_good "- $1" "$(cat "$1")"
		fi
	}

	echo 'Limits:'
	check_limit_over /proc/sys/kernel/keys/root_maxkeys 10000
	echo

	function command_check(){
		cmd="$1"
		minVersion="$2"
		if command -v $cmd; then
			current_version=$($cmd --version | grep $cmd | awk '{print $3}')			
			if [ "$(printf '%s\n' "$current_version" "$minVersion" | sort -V | head -n1)" = "$minVersion" ]; then
				if [ "$current_version" = "$minVersion" ]; then
					echo "$(wrap_color "$cmd version" white): $(wrap_color "$current_version" yellow)"
				else
					wrap_good "$cmd version" "${current_version}"
				fi
			else
				wrap_bad "$cmd Version" "${current_version} < ${minVersion}"
			fi
		else
			wrap_bad "$cmd" "Not installed!"
		fi
	}

	echo
	command_check podman "4.6.0"
	echo
	command_check podman-compose "1.3.0"
    echo
	command_check crun "1.14.0"
    echo

    echo "AppArmor Enabled:"
	if command -v aa-enabled; then
    	aa-enabled

	else
		wrap_bad "AppArmor" "Not installed!"
	fi
	echo
	command_check apparmor_parser "4.0.0"
	echo
	
	exit $EXITCODE
}


echo "#"
config
