#!/bin/bash
#---------------------------------------------
# Copyright Phoenix Contact GmbH & Co. KG
#---------------------------------------------
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

#Check if includes are executeable
for file in "${DIR}/includes"/*.sh; do
    if [[ -f "$file" && ! -x "$file" ]]; then
        echo "ERROR" 
        echo "File $file is not executable."
        exit 1
    fi
done
source "${DIR}/includes/colorcoding.sh"

# Initialize variables
IMAGE=""
COMPOSE_FILE="${DIR}/container-compose.yml"
APPARMOR_PROFILE="vplcnextcontrol.profile"
# Parse command line options
OPTIONS=$(getopt -o "c:i:" --long image:,compose: -- "$@")
if [ $? -ne 0 ]; then
  wrap_bad "ERROR" "Invalid options provided"
  exit 1
fi
eval set -- "$OPTIONS"
while true; do
  case "$1" in
    -i|--image)
      IMAGE="$2"
      shift 2
      ;;
    -c|--compose)
      COMPOSE_FILE="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      wrap_bad "ERROR" "Invalid option: $1"
      exit 1
      ;;
  esac
done
if [ -z "$COMPOSE_FILE" ]; then
    COMPOSE_FILE="${DIR}/container-compose.yml"
fi

if [[ "$(whoami)" == "root" ]]; then
  if [[ "${COMPOSE_FILE}" != "" ]]; then
      if [ -f "${COMPOSE_FILE}" ]; then
          if [[ "${COMPOSE_FILE}" != /* && "${COMPOSE_FILE}" != ./* ]]; then
              COMPOSE_FILE="$(pwd)/${COMPOSE_FILE}"
          fi
      elif [ -f "${DIR}/${COMPOSE_FILE}" ]; then
          COMPOSE_FILE="${DIR}/${COMPOSE_FILE}"
      else
          wrap_bad "ERROR" "compose file not found"
          exit 1;
      fi
  else
      COMPOSE_FILE="${DIR}/container-compose.yml"
  fi
    # Apparmor load    
    wrap_color "Setting up AppArmor Profile" magenta
    mkdir -p /etc/apparmor.d/containers/
    cp "${DIR}/${APPARMOR_PROFILE}" /etc/apparmor.d/containers/
    apparmor_parser -r -W "/etc/apparmor.d/containers/${APPARMOR_PROFILE}"
    if [ $? -eq 0 ]; then
      wrap_good "SUCCESS" "Loaded Apparmor Profile"
    else
      wrap_bad "Loading Appamor" "Operating system does NOT support AppArmor profile. src/vplcnextcontrol.profile"
    fi

    # Podman image Load # if no Image is specified its not loaded and podman compose will try to pull.
    if [ -n "$IMAGE" ]; then    
      if [ -f "$IMAGE" ]; then
        wrap_color "Loading OCI-Image" magenta
        image_name=$(podman load -i $IMAGE | grep -oP '(?<=Loaded image: ).*')
        wrap_good "SUCCESS" "Image name: $image_name"
        sed -i "s|\( *image: \)\".*\"|\1\"$image_name\"|" "${COMPOSE_FILE}"
        else
        wrap_bad "ERROR" "Not Found: $IMAGE"
      fi
    fi
    
    # Setup Network and Create container according to compose file.
    IDs=( $(podman-compose -f "${COMPOSE_FILE}" up --no-start ) ) 
    if [ $? -eq 0 ]; then
      wrap_color "Begin Setting up Container" magenta
    else
      wrap_bad "ERROR" "${IDs[@]}" && exit 1
      wrap_bad "ERROR" "${IDs[@]}" && exit 1
    fi

    for ID in "${IDs[@]}"; do
      if  eval podman container exists "$ID"; then
        CONTAINER_NAME="$(podman container inspect -f '{{.Name}}' ${ID})"
        CID="$(podman container inspect -f '{{.Id}}' ${ID})"
        Networks="$(podman container inspect -f '{{.NetworkSettings.Networks}}' ${ID})"
        container_found=true
        wrap_good "Name" "${CONTAINER_NAME}"
        wrap_good "Container ID" "${CID}"
        wrap_good "Networks " "${Networks}"
        break
      fi      
    done
    if ! $container_found; then
      wrap_bad "ERROR" "Container not created." >&2
      wrap_bad "ERROR" "I:${#IDs[@]} : N:${IDs[@]}" >&2
      exit 1
    fi
   
    ## Initialize Container/Volumes
    output=$(podman container init "${CID}" 2>&1)
    status=$?
    if [ $status -eq 0 ]; then
       wrap_good "Initialized" "$output"
    else
       wrap_bad "ERROR" "Could not initialize: $output" 
       exit 1
    fi

  #  echo "Update Volumes"
  #  "${DIR}/includes/updateVolumes.sh" "${CID}" || exit 1

    echo "Setting ACLs"
    # Volume ACLs fix after init
    "${DIR}/includes/setACLs.sh" "${CID}" || exit 1

    # Generate Service File
    mkdir -p /usr/local/lib/systemd/system/
    # If podman compose > 1.3.0 or == 1.3.0
    minVersion="1.3.0"
    current_version=$(podman-compose --version | grep podman-compose | awk '{print $3}')
    if [ "$(printf '%s\n' "$current_version" "$minVersion" | sort -V | head -n1)" = "$minVersion" ]; then
      if [ "$current_version" = "$minVersion" ]; then
        echo "Using template-compose.service"
        ##podman-compose -f "${COMPOSE_FILE}" down -t 0
        path_podmanCompose="$(which podman-compose)"
        sed "s|<COMPOSE_FILE>|${COMPOSE_FILE}|g" "${DIR}/includes/template-compose.service" > "/usr/local/lib/systemd/system/${CONTAINER_NAME}.service"
        chmod +x "/usr/local/lib/systemd/system/${CONTAINER_NAME}.service"
        sed -i -e "s|<COMPOSE>|${path_podmanCompose}|g" "/usr/local/lib/systemd/system/${CONTAINER_NAME}.service"
        sed -i -e "s|<CONTAINER_NAME>|${CONTAINER_NAME}|g" "/usr/local/lib/systemd/system/${CONTAINER_NAME}.service" 
      else
        echo "Using template.service"
        sed "s|<CONTAINER_NAME>|${CONTAINER_NAME}|g" "${DIR}/includes/template.service" > "/usr/local/lib/systemd/system/${CONTAINER_NAME}.service"
      fi
    else
      wrap_bad "podman-compose version" "${current_version} < Minimal Version ${minVersion}"
      exit 1
    fi
    sed -i -e "s|<APPARMOR_PROFILE>|${APPARMOR_PROFILE}|g" "/usr/local/lib/systemd/system/${CONTAINER_NAME}.service"


    
    #Enable service for autostart at boot.
    echo "Enable SystemD Service: ${CONTAINER_NAME}.service"
    systemctl daemon-reload
    output=$(systemctl enable "${CONTAINER_NAME}.service" 2>&1)
    status=$?
    if [ $status -eq 0 ]; then
       wrap_good "Enable Service SUCCESS" "$output"
    else
       wrap_bad "Enable Service ERROR" "$output" 
       exit 1
    fi

    # Container start
    output=$(systemctl start "${CONTAINER_NAME}.service" &2>&1)
    status=$?
    if [ $status -eq 0 ]; then
      systemctl status "${CONTAINER_NAME}.service"  --no-pager
    else
       wrap_bad "Starting Container ERROR" "$output" 
       exit 1
    fi
else
    wrap_bad "ERROR" "execute as root / sudo!"
    exit 1
fi
