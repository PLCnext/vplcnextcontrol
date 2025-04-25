#!/bin/bash
#---------------------------------------------
# Copyright Phoenix Contact GmbH & Co. KG
#---------------------------------------------
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${DIR}/colorcoding.sh"

##ContainerName
container_id="$1"
LOGLEVEL="error"

# Get the list of mounted volumes
volumes=$(podman inspect $container_id --format '{{ range .Mounts }}{{ .Name }}:{{ .Destination }} {{ end }}')

path="$(pwd)"
container_mnt="$(podman mount --log-level="${LOGLEVEL}" "${container_id}")"

function checkVolumeChanges(){
    local full_container_path="$1"
    local volume_mnt="$2"
    # Run rsync with --dry-run and --itemize-changes
    rsync -avzi --dry-run --itemize-changes --ignore-existing "$full_container_path/" "$volume_mnt/" \
        > "${DIR}/tmp.changes" || wrap_bad  "ERROR" "Compare Volume and Image"
    exec {fd}< "${DIR}/tmp.changes"
    # Process the rsync output
    while IFS= read -u $fd line; do
        change_type=$(echo "$line" | cut -c 1)
        file_path=$(echo "$line" | awk '{print $2}')
        # Decide what to keep and what to overwrite
        if [[ "$change_type" == ">" ]]; then
            echo "Files differ: ${file_path}"
            echo "diff \"File in Image\"   \"File in Volume\""             
            diff "$full_container_path/$file_path" "$volume_mnt/$file_path"
            read -r -p  "Select file to keep [merge, volume, image] :"  trigger
            case "$trigger" in
                m|merge)
                    nano "$volume_mnt/$file_path"
                    break
                ;;
                
                v|volume)
                    echo "Keeping volume file"
                    break
                ;;
                
                i|image)
                    echo "Restoring file from image"
                    cp --preserve=all \
                        "$full_container_path/$file_path" "$volume_mnt/$file_path"
                ;;
                
                *)
                break;
                ;;
            esac
            echo "####"            
        fi
    done

    exec {fd}<&-    
    rm "${DIR}/tmp.changes"
}

# Loop through each volume
for volume in $volumes; do
    oldIFS=$IFS
    IFS=':' read -r volume_name container_path <<< "$volume"
    IFS=$oldIFS
    volume_name="${volume_name%%:*}"
    volume_mnt="$(podman volume mount $volume_name)"
    checkVolumeChanges "${container_mnt}${container_path}" "${volume_mnt}" 
    podman volume unmount $volume_name
done
podman unmount $container_id
cd "$path" || exit 1

