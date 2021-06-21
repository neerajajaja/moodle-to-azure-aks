#!/bin/bash
set -e
WORKING_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "$WORKING_DIRECTORY/scripts/helper-functions.sh"    #import helper functions

SCRIPTS_DIRECTORY="$WORKING_DIRECTORY/scripts"
OUTPUT_DIRECTORY="$WORKING_DIRECTORY/generated"
if [ -d "$OUTPUT_DIRECTORY" ]; then rm -Rf "$OUTPUT_DIRECTORY"; fi
mkdir "$OUTPUT_DIRECTORY"

SUCCESS_FILE_PATH="$OUTPUT_DIRECTORY/success.json"
FAILURE_FILE_PATH="$OUTPUT_DIRECTORY/failure.txt"
PROGRESS_FILE_PATH="$OUTPUT_DIRECTORY/progress.json"

DISCOVERY_SCRIPT="$SCRIPTS_DIRECTORY/discovery.sh"
PREPARE_PARAMS_SCRIPT="$SCRIPTS_DIRECTORY/prepare-arm-params.sh"
CREATE_FILE_SHARE_SCRIPT="$SCRIPTS_DIRECTORY/create-afs.sh"
DATA_MIGRATION_SCRIPT="$SCRIPTS_DIRECTORY/dataMigrate.sh"
CREATE_INFRA_SCRIPT="$SCRIPTS_DIRECTORY/create-infra.sh"

DISCOVERY_OUTPUT_FILE="$OUTPUT_DIRECTORY/deep-discovery-report.json"

AFS_ARM_PARAMETERS_FILE="$OUTPUT_DIRECTORY/afs-arm-params.json"
AFS_DEPLOYMENT_OUTPUT="$OUTPUT_DIRECTORY/afs-deployment-output.json"

INFRA_ARM_PARAMETERS_FILE="$OUTPUT_DIRECTORY/infra-arm-params.json"
INFRA_DEPLOYMENT_OUTPUT="$OUTPUT_DIRECTORY/infra-deployment-output.json"

SSH_KEY_PRIVATE_FILE="$WORKING_DIRECTORY/ssh.key"
SSH_KEY_PUBLIC_FILE="$WORKING_DIRECTORY/ssh.key.pub"

function clear_files(){
    $(rm -rf "$SUCCESS_FILE_PATH")
    $(rm -rf "$FAILURE_FILE_PATH")
    $(rm -rf "$PROGRESS_FILE_PATH")
}

function track-and-show-progress(){
    local return_value=0
    # while [[ ! -f "$SUCCESS_FILE_PATH" || ! -f "$FAILURE_FILE_PATH" ]]; do
    #     sleep 2
    #     echo "$1 progress:"
    #     echo "$(cat $PROGRESS_FILE_PATH)"
    # done

    # printf "\n"

    if [[ -f "$FAILURE_FILE_PATH" ]]; then
        echo "$1 failed"
        local return_value=1
    elif [[ -f "$SUCCESS_FILE_PATH" ]]; then 
        echo "$1 succeeded"
        local return_value=0
    else
        echo "$1 failed"
        local return_value=1
    fi

    return "$return_value" 
}

function deep_discovery(){
    clear_files
    "$DISCOVERY_SCRIPT" \
        --successfilepath "$SUCCESS_FILE_PATH" \
        --failurefilepath "$FAILURE_FILE_PATH" \
        --progressstatusfilepath "$PROGRESS_FILE_PATH"

    track-and-show-progress "discovery" || (echo "discovery failed" && exit -1)
    cp "$SUCCESS_FILE_PATH" "$DISCOVERY_OUTPUT_FILE"
}

function prepare_params(){
    clear_files
    "$PREPARE_PARAMS_SCRIPT" \
        --successfilepath "$SUCCESS_FILE_PATH" \
        --failurefilepath "$FAILURE_FILE_PATH" \
        --progressstatusfilepath "$PROGRESS_FILE_PATH" \
        --discovery-config-file "$DISCOVERY_OUTPUT_FILE" \
        --afs-parameters-output-file "$AFS_ARM_PARAMETERS_FILE" \
        --infra-parameters-output-file "$INFRA_ARM_PARAMETERS_FILE" \
        --ssh-key-output-path "$SSH_KEY_PRIVATE_FILE" \
        --location $LOCATION

    track-and-show-progress "creating ARM parameters" || (echo "failed" && exit -1)
}

function create_afs(){
    clear_files
    "$CREATE_FILE_SHARE_SCRIPT" \
        --successfilepath "$SUCCESS_FILE_PATH" \
        --failurefilepath "$FAILURE_FILE_PATH" \
        --progressstatusfilepath "$PROGRESS_FILE_PATH" \
        --parameters-file "$AFS_ARM_PARAMETERS_FILE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --arm-output-file "$AFS_DEPLOYMENT_OUTPUT"

    track-and-show-progress "creating azure file share" || (echo "failed" && exit -1)
}

function populate_afs_details(){
    afs_deployment_output_text="$(echo "$(cat "$AFS_DEPLOYMENT_OUTPUT")")"
    storage_account_name="$(read_json_key "$afs_deployment_output_text" storageAccountName.value)" 
    azure_file_share_uri="https://""$storage_account_name"".file.core.windows.net/aksshare"
    sas_end=`date -u -d "1 day" '+%Y-%m-%dT%H:%MZ'`
    afs_sas_token=`az storage share generate-sas -n aksshare --account-name "$storage_account_name" \
    --https-only --permissions dlrw --expiry "$sas_end" -o tsv`
}

function migrate_data(){
    clear_files
    populate_afs_details
    "$DATA_MIGRATION_SCRIPT" \
        --successfilepath "$SUCCESS_FILE_PATH" \
        --failurefilepath "$FAILURE_FILE_PATH" \
        --progressstatusfilepath "$PROGRESS_FILE_PATH" \
        --azurefileshareuri "$azure_file_share_uri" \
        --sastoken "?$afs_sas_token"

    track-and-show-progress "data migration" || (echo "data migration failed" && exit -1)
}

function create_arm_infra(){
    clear_files
    "$CREATE_INFRA_SCRIPT" \
        --successfilepath "$SUCCESS_FILE_PATH" \
        --failurefilepath "$FAILURE_FILE_PATH" \
        --progressstatusfilepath "$PROGRESS_FILE_PATH" \
        --parameters-file "$INFRA_ARM_PARAMETERS_FILE" \
        --resource-group "$RESOURCE_GROUP" \
        --arm-output-file "$INFRA_DEPLOYMENT_OUTPUT"
    
    track-and-show-progress "Azure infra creation" || (echo "infra creation failed" && exit -1)
}

function show_results()
{
    echo "migration completed"
    local infra_deployment_output="$(echo "$(cat "$INFRA_DEPLOYMENT_OUTPUT")")"

    local controllerInstanceIP="$(read_json_key "$infra_deployment_output" controllerInstanceIP.value)"
    
    printf "controller VM IP:\t $controllerInstanceIP\n"
    printf "ssh Username:\t\t azureadmin\n"
    printf "ssh private key file:\t $SSH_KEY_PRIVATE_FILE\n" 
    printf "ssh public key file:\t $SSH_KEY_PUBLIC_FILE\n" 
}

function main(){
    read -p "Enter resource group name: " RESOURCE_GROUP
    read -p "Enter resource group location: " LOCATION
    deep_discovery
    prepare_params
    create_afs
    migrate_data
    create_arm_infra
    show_results
    echo "done"
}

main