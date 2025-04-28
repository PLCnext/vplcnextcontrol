#!/bin/bash
#---------------------------------------------
# Copyright Phoenix Contact GmbH & Co. KG
#---------------------------------------------
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

for file in "${DIR}/includes"/*.sh; do
    if [[ -f "$file" && ! -x "$file" ]]; then
        echo "ERROR" 
        echo "File $file is not executable."
        exit 1
    fi
done
source "${DIR}/includes/colorcoding.sh"

CON_NAME=""
COMPOSE_FILE="${DIR}/container-compose.yml"

# Parse command line options
OPTIONS=$(getopt -o "n:c:" --long name:,compose: -- "$@")
if [ $? -ne 0 ]; then
  wrap_bad "ERROR" "Invalid options provided"
  exit 1
fi
eval set -- "$OPTIONS"
while true; do
  case "$1" in
    -n|--name)
      CON_NAME="$2"
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
      CON_NAME="$1"  
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

    if [[ "$CON_NAME" == "" ]]; then
        wrap_bad "ERROR" "No Container/Service specified to reset"
        exit 1
    else
        if ! eval "podman container exists ${CON_NAME}"; then
            wrap_warning "$CON_NAME" "Container does not exist."
        fi
    fi    
    volumes=$(podman inspect "$CON_NAME" --format '{{ range .Mounts }}{{ .Name }} {{ end }}')

    if systemctl list-unit-files --all | grep -Fq "${CON_NAME}.service"; then
        wrap_color "Disable: ${CON_NAME}.service" magenta    
        systemctl disable "${CON_NAME}.service"
        disablestatus="$(systemctl is-enabled "${CON_NAME}.service")"
        if [ "${disablestatus}" == "disabled" ]; then
            wrap_good "${CON_NAME}.service" "disabled"
        else
            systemctl status "${CON_NAME}.service"  --no-pager
            wrap_color "Disable service failure."  yellow
        fi

        wrap_color "Stopping: ${CON_NAME}.service" magenta    
        systemctl stop "${CON_NAME}.service"
        exitstatus="$(systemctl is-active "${CON_NAME}.service")"
        if [ "${exitstatus}" == "inactive" ]; then
            wrap_good "${CON_NAME}.service" "$exitstatus"
        elif [  "${exitstatus}" == "failed" ]; then
            systemctl status "${CON_NAME}.service"  --no-pager
            wrap_color "Exit status: $exitstatus."  yellow
            echo "Check for application crash or timeout during shutdown."
        else
            systemctl status "${CON_NAME}.service"  --no-pager
            wrap_bad "Exit status" "${exitstatus}"
        fi

        rm "/usr/local/lib/systemd/system/${CON_NAME}.service"
        systemctl daemon-reload
    else
        wrap_warning "$CON_NAME.service" "Service does not exist."
    fi
    
    if  eval podman container exists "${CON_NAME}"; then
        output=$(podman compose -f "${COMPOSE_FILE}" down)
        status=$?
        if [ $status -eq 0 ]; then
            wrap_good "Compose Down" "$output"
        else
            wrap_bad "Compose Down" "$output" 
            exit 1
        fi
    fi

    read -r -p "$(wrap_color "Remove Volumes? [Yes/No/All]: " yellow)" response        
    case "$response" in
        [yY][eE][sS]|[yY] )
            for volume in $volumes; do
                read -r -p "$(wrap_color "Remove Volume: $volume? [Yes/No]: " yellow)"  response       
                if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]] 
                then
                    podman volume rm $volume
                fi
            done
        ;;
        [aA][lL][lL]|[aA] )
            for volume in $volumes; do
                podman volume rm "$volume"
            done
        ;;
        *)
            echo "Skipped."
        ;;
    esac
    
else
    wrap_bad "ERROR" "execute as root / sudo!"
    exit 1
fi