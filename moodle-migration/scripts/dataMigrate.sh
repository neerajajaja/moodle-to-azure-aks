#!/bin/bash
set -eo pipefail
WORKING_DIRECTORY="$(dirname "$0")"

. "$WORKING_DIRECTORY/dataMigrateHelper.sh"

if [[ $# -eq 0 ]] ; then
  echo "No Arugments Passed
  Usage: $0 -t "..." -u "..." -S "..." -F "..." -P "..."
  Mandatory arguments to long options are mandatory for short options too.
    -t, --sastoken          azure SAS token
    -u, --azurefileshareuri azure account url
    -S, --successfilepath           Success file path to record discovery output
    -F, --failurefilepath           File path to record failures(if any)
    -P, --progressstatusfilepath    File path to record the progress status"
  exit 40
fi

PARAMS=$@

check_empty_argument(){
  if [ -z "$1" ] ; then
      echo "Empty Arugment Passed"
      exit 40
  fi
}
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -t | --sastoken)
    AZ_SAS_TOKEN="$2"
    check_empty_argument "$AZ_SAS_TOKEN"
    shift # past argument
    shift # past value
    ;;
    -u | --azurefileshareuri)
    AZ_FILE_SHARE_URL="$2"
    check_empty_argument "$AZ_FILE_SHARE_URL"
    shift # past argument
    shift # past value
    ;;
    -S | --successfilepath)
    SUCCESS_FILE_PATH="$2"
    check_empty_argument "$SUCCESS_FILE_PATH"
  	shift # past argument
  	shift # past value
    ;;
    -F | --failurefilepath)
    FAILURE_FILE_PATH="$2"
    check_empty_argument "$FAILURE_FILE_PATH"
  	shift # past argument
  	shift # past value
  	;;
    -P | --progressstatusfilepath)
    PROGRESS_FILE_PATH="$2"
    check_empty_argument "$PROGRESS_FILE_PATH"
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

TOTAL_STAGES=7
OUTPUT_FILE_PATH="$(cd "$(dirname "$PROGRESS_FILE_PATH")" && pwd)/data-migration-output"
AZ_COPY_PATH="${OUTPUT_FILE_PATH}/azcopy"
LOG_FILE="$OUTPUT_FILE_PATH/log.txt"
DB_DUMP_PATH="$OUTPUT_FILE_PATH/migration-db-moodle.sql"

if [ ! -d "$OUTPUT_FILE_PATH" ]; then mkdir "$OUTPUT_FILE_PATH"; fi
if [ ! -f "$LOG_FILE" ]; then echo " " > "$LOG_FILE"; fi

MOODLE_CONFIG_PATH="$(locate moodle/config.php | head -n 1)"

stagesCompleted=-1

update() {
  echo '{
  "CurrentStageCompletionPercentage": "'$1'",
  "CurrentStageName": "'$2'",
  "NumberOfStagesCompleted": "'$stagesCompleted'",
  "TotalNumberOfStages": "'$TOTAL_STAGES'"
  }' > "$PROGRESS_FILE_PATH"
}

upload_certs(){
  siteUrl=$(grep  'wwwroot' "$MOODLE_CONFIG_PATH" | sed 's/.*= //g' | sed "s/[';]//g")
  if [ siteUrl == https* ]; then
    log "Uploading certs folder"
    log "Calling upload_blob_to_azure with path to certs folder as argument"
    SSL_CERT_PATH="$(get_cert_location)"
    upload_file_to_azure "$SSL_CERT_PATH" "/certs"
  else
    log "ssl not enabled. Skipping Upload certs"
  fi
  stagesCompleted=$(( stagesCompleted+1 ))
  update 100 "Uploading ssl certificate folder"
}

upload_moodle_code(){
  log "Uploading moodle code"
  moodleCodePath=$(echo "$MOODLE_CONFIG_PATH" | sed 's/config.php//')
  update 50 "Uploading moodle code"
  log "Calling upload_blob_to_azure with path to moodle code as argument"
  upload_file_to_azure "$moodleCodePath" ""
  stagesCompleted=$(( stagesCompleted+1 ))
  update 100 "Uploading moodle code"
}

upload_moodle_data(){
  log "Uploading moodle data"
  moodleDataPath=$(grep  'dataroot' "$MOODLE_CONFIG_PATH" | sed 's/.*= //g' | sed "s/[';]//g")
  update 50 "Uploading moodle data"
  log "Calling upload_blob_to_azure with path to moodle data as argument"
  # Copying only contents of moodle data folder to moodledata folder in azure fileshare.
  # Details on folders that can be skipped are mentioned here - https://docs.moodle.org/310/en/Moodle_migration
  upload_file_to_azure "$moodleDataPath/*" "/moodledata" "cache;localcache;sessions;temp;trashdir"
  stagesCompleted=$(( stagesCompleted+1 ))
  update 100 "Uploading moodle data"
}

upload_config(){
  log "Uploading configurations"
  log "Calling create_config_folder and adding configurations to it"
  configFolderPath="$(create_config_folder)"
  log "Calling archive with config folder as argument"
  configArchive="$(archive "$configFolderPath" "$OUTPUT_FILE_PATH/migration-config")"
  update 50 "Uploading moodle configurations"
  log "Calling upload_file_to_azure with config folder as argument"
  upload_file_to_azure "$configArchive"
  stagesCompleted=$(( stagesCompleted+1 ))
  update 100 "Uploading moodle configurations"
}

upload_db(){
  log "Uploading db"
  log "Calling create_db_dump"
  dbDumpPath="$(create_db_dump)"
  update 33 "Uploading data base"
  log "Calling archive with db_dump as argument"
  dumpArchive="$(archive "$dbDumpPath" "$OUTPUT_FILE_PATH/migration-db-moodle.sql")"
  update 66 "Uploading data base"
  log "Calling upload_file_to_azure with tar.gz file as argument"
  upload_file_to_azure "$dumpArchive"
  stagesCompleted=$(( stagesCompleted+1 ))
  update 100 "Uploading data base"
}

main(){
  stagesCompleted=$(( stagesCompleted+1 ))
  clear_output_path
  stagesCompleted=$(( stagesCompleted+1 ))
  update 100 "Clearing output path"
  validate_prerequisite
  stagesCompleted=$(( stagesCompleted+1 ))
  update 100 "Validating prerequisites"
  upload_certs
  upload_moodle_code
  upload_moodle_data
  upload_config
  upload_db
  echo "Data migration completed successfully" > "$SUCCESS_FILE_PATH"
}
main
