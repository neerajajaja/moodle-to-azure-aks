set -e
ARM_TEMPLATE="https://raw.githubusercontent.com/neerajajaja/moodle-to-azure-aks/master/moodle-arm-templates/storagedeploy.json"
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
    --parameters-file)
    ARM_PARAMETERS_FILE="$2"
    check_empty_argument "$ARM_PARAMETERS_FILE"
    shift # past argument
    shift # past value
    ;;
    -r | --resource-group)
    RESOURCE_GROUP="$2"
    check_empty_argument $RESOURCE_GROUP
    shift # past argument
    shift # past value
    ;;
    -l | --location)
    LOCATION="$2"
    check_empty_argument $LOCATION
    shift # past argument
    shift # past value
    ;;
    --arm-output-file)
    ARM_OUTPUT_FILE="$2"
    check_empty_argument "$ARM_OUTPUT_FILE"
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

function start_arm_deployment(){
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
    deployment_name="moodle-migration-afs-$(openssl rand -hex 12)"
    az deployment group create \
      --name $deployment_name \
      --resource-group "$RESOURCE_GROUP" \
      --template-uri "$ARM_TEMPLATE" \
      --parameters @"$ARM_PARAMETERS_FILE" \
      --verbose
    
    az deployment group show \
      --name "$deployment_name" \
      --resource-group $RESOURCE_GROUP \
      --query properties.outputs > "$ARM_OUTPUT_FILE"
      
}

function main(){
    start_arm_deployment 
    echo "finished" > "$SUCCESS_FILE_PATH"
}

main