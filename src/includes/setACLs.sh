#!/bin/bash
#---------------------------------------------
# Copyright Phoenix Contact GmbH & Co. KG
#---------------------------------------------
container_id="$1"


LOGLEVEL="error"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${DIR}/colorcoding.sh"

if  eval "podman container exists ${container_id}"; then
    # Get the list of mounted volumes
    volumes=$(podman inspect $container_id --format '{{ range .Mounts }}{{ .Name }}:{{ .Destination }} {{ end }}')

    path="$(pwd)"
    container_mnt="$(podman mount --log-level="${LOGLEVEL}" "${container_id}")"  
    # Loop through each volume
    for volume in $volumes; do
        IFS=':' read -r volume_name container_path <<< "$volume"
        volume_name="${volume_name%%:*}"
        volume_mnt=$(podman volume mount $volume_name)

        #echo "Volume name: ${volume_name}, mount: ${volume_mnt}"
        #echo "Container path: ${container_path}"
        full_container_path="${container_mnt}${container_path}"

        ## Get ACLs from Image.
        cd "${full_container_path}" || exit 1
        acl_list=$(getfacl -pR ".")

        ## Restore ACLs at volume path
        if [ -f "${volume_mnt}" ]; then # Check if File or Path mount
            volume_mnt="$(dirname "${volume_mnt}")"
        fi
        cd "${volume_mnt}" || exit 1
        echo "$acl_list" | setfacl --restore=-

        podman volume unmount $volume_name &> /dev/null
    done
    podman unmount $container_id &> /dev/null
    cd "$path" || exit 1
else
    wrap_bad "Setting ACLs" "Container $container_id does not exists yet." 
fi