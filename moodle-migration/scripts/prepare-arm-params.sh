set -e
WORKING_DIRECTORY=$(dirname "$0")
. "$WORKING_DIRECTORY/helper-functions.sh"    #import helper functions

POSITIONAL=()

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -s | --successfilepath)
    SUCCESS_FILE_PATH="$2"
    check_empty_argument "$SUCCESS_FILE_PATH"
  	shift # past argument
  	shift # past value
    ;;
    -f | --failurefilepath)
    FAILURE_FILE_PATH="$2"
    check_empty_argument "$FAILURE_FILE_PATH"
  	shift # past argument
  	shift # past value
  	;;
    -p | --progressstatusfilepath)
    PROGRESS_FILE_PATH="$2"
    check_empty_argument "$PROGRESS_FILE_PATH"
    shift # past argument
    shift # past value
    ;;
    -d | --discovery-config-file)
    DISCOVERY_CONFIG_FILE="$2"
    check_empty_argument "$DISCOVERY_CONFIG_FILE"
    shift # past argument
    shift # past value
    ;;
    --infra-parameters-output-file)
    INFRA_ARM_TEMPLATE_PARAMS_FILE="$2"
    check_empty_argument "$INFRA_ARM_TEMPLATE_PARAMS_FILE"
  	shift # past argument
  	shift # past value
    ;;
    --afs-parameters-output-file)
    AFS_ARM_TEMPLATE_PARAMS_FILE="$2"
    check_empty_argument "$AFS_ARM_TEMPLATE_PARAMS_FILE"
  	shift # past argument
  	shift # past value
    ;;
    --ssh-key-output-path)
    SSH_KEY_PRIVATE_FILE="$2"
    check_empty_argument "$SSH_KEY_PRIVATE_FILE"
  	shift # past argument
  	shift # past value
    ;;
    -l | --location)
    LOCATION="$2"
    check_empty_argument "$LOCATION"
    shift # past argument
  	shift # past value
    ;;
    *)
    shift
    shift
    ;;
  esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters
DISCOVERY_CONFIG="$(cat "$DISCOVERY_CONFIG_FILE")"

function get_params_file_prefix(){
    cat << EOF
{
    "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
EOF
}

function get_params_file_suffix(){
    cat << EOF
    
    }
}
EOF
}

function write_param_to_afs_file(){
    cat << EOF >> "$AFS_ARM_TEMPLATE_PARAMS_FILE"
        "$1": {
            "value": $2
        },
EOF
}

function write_param_to_arm_file(){
    cat << EOF >> "$INFRA_ARM_TEMPLATE_PARAMS_FILE"
        "$1": {
            "value": $2
        },
EOF
}

function write_afs_params_to_file(){
    get_params_file_prefix > "$AFS_ARM_TEMPLATE_PARAMS_FILE"
    write_param_to_afs_file fileServerDiskSize \"$fileServerDiskSize\"
    truncate -s-2 "$AFS_ARM_TEMPLATE_PARAMS_FILE"       # removes last 2 characters i.e. new line and comma from the file
    get_params_file_suffix >> "$AFS_ARM_TEMPLATE_PARAMS_FILE"
}

function read_discovery_key(){
    read_json_key "$DISCOVERY_CONFIG" $1
}

function populate_sshPublicKey(){
    if [[ -f "$SSH_KEY_PRIVATE_FILE" ]]; then rm "$SSH_KEY_PRIVATE_FILE" "$SSH_KEY_PRIVATE_FILE.pub" ; fi
    ssh-keygen -t rsa -b 4096 -C "" -P "" -f "$SSH_KEY_PRIVATE_FILE" -q <<< y
    sshPublicKey="$(cat "$SSH_KEY_PRIVATE_FILE.pub")"
}

function populate_siteUrl(){
    siteURL=$(read_discovery_key siteProfile.siteURL)
    siteURL=${siteURL#*//}                              #removes https:// or http://
    local changeUrl=""
    while [[ $changeUrl != 'y' && $changeUrl != 'n' ]]; do
        read -p "Site url is configured to '$siteURL'. Do you want this to be changed in azure? (y/n): " changeUrl
        if [[ $changeUrl == 'y' ]]; then
            read -p "Enter new site url: " siteURL
        elif [[ $changeUrl != 'n' ]]; then 
            echo "ERR: expected y/n, received '$changeUrl'"
        fi
    done

    echo "Site to be configured is '$siteURL'"
}

function prepare_params(){
    applyScriptsSwitch=true
    populate_sshPublicKey
    phpVersion=$(read_discovery_key phpProfile.phpVersion)
    SQLDBName=$(read_discovery_key dbServerProfile.dbName)
    mysqlPgresStgSizeGB=$(read_discovery_key dbServerProfile.dbSizeInGB)
    fileServerDiskSize=$(read_discovery_key fileServerProfile.fileShareSizeInGB)
}

function write_infra_params_to_file(){
    
    get_params_file_prefix > "$INFRA_ARM_TEMPLATE_PARAMS_FILE"
    write_param_to_arm_file sshPublicKey \""$sshPublicKey"\"
    write_param_to_arm_file phpVersion \"$phpVersion\"
    write_param_to_arm_file SQLDBName \"$SQLDBName\"
    write_param_to_arm_file mysqlPgresStgSizeGB \"$mysqlPgresStgSizeGB\"
    write_param_to_arm_file applyScriptsSwitch $applyScriptsSwitch
    write_param_to_arm_file fileServerDiskSize \"$fileServerDiskSize\"
    
    truncate -s-2 "$INFRA_ARM_TEMPLATE_PARAMS_FILE"      # removes last 2 characters i.e. new line and comma from the file
    get_params_file_suffix >> "$INFRA_ARM_TEMPLATE_PARAMS_FILE"
}

function set_failure(){
    echo "exiting process"
    echo "failed" > "$FAILURE_FILE_PATH"
    exit -1
}

function main(){
    set_python_version || set_failure
    prepare_params || set_failure
    write_afs_params_to_file || set_failure
    write_infra_params_to_file || set_failure
    echo "succeeded" > "$SUCCESS_FILE_PATH"
}

main