#!/bin/bash
set -e
WORKING_DIRECTORY=$(dirname "$0")

if [[ $# -eq 0 ]] ; then
  echo "No Arugments Passed
  Usage: script_name.sh -o DIRECTORY
  Mandatory arguments to long options are mandatory for short options too.
    -S, --successfilepath           Success file path to record discovery output
    -F, --failurefilepath           File path to record failures(if any)
    -P, --progressstatusfilepath    File path to record the progress status" > init_error.txt
  exit 40
fi

check_empty_argument(){
  if [ -z "$1" ] ; then
      echo "Empty Arugment Passed" > init_error.txt
      exit 40
  fi
}

PARAMS=$@

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
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

TOTAL_STAGES=5
stagesCompleted=-1
discoveryOutput="{"

get_moodle_config_path() {
    echo $(locate moodle/config.php | head -n 1 )
}

update() {
    echo '{
    "CurrentStageCompletionPercentage": "'$1'",
    "CurrentStageName": "'$2'",
    "NumberOfStagesCompleted": "'$stagesCompleted'",
    "TotalNumberOfStages": "'$TOTAL_STAGES'"
    }' > "$PROGRESS_FILE_PATH"
}
get_discovery_output(){

    moodleConfigPath=$(get_moodle_config_path)

    . "$WORKING_DIRECTORY/discoveryHelper.sh" $moodleConfigPath

    stagesCompleted=$(( stagesCompleted+1 ))
    discoveryOutput+=$( get_site_profile )
    stagesCompleted=$(( stagesCompleted+1 ))
    update 100 "Get web server profile"
    discoveryOutput+=$( get_moodle_profile )
    stagesCompleted=$(( stagesCompleted+1 ))
    update 100 "Get moodle profile"
    discoveryOutput+=$( get_db_profile )
    stagesCompleted=$(( stagesCompleted+1 ))
    update 100 "Get DB profile"
    discoveryOutput+=$( get_file_server_profile )
    stagesCompleted=$(( stagesCompleted+1 ))
    update 100 "Get file server profile"
    discoveryOutput+=$( get_php_profile )
    stagesCompleted=$(( stagesCompleted+1 ))
    update 100 "Get php profile"
    discoveryOutput+='
    }
    '
    echo "$discoveryOutput" > "$SUCCESS_FILE_PATH"
    
}

main(){
    $(rm -rf "$SUCCESS_FILE_PATH")
    $(rm -rf "$FAILURE_FILE_PATH")
    $(rm -rf "$PROGRESS_FILE_PATH")
    get_discovery_output
}
main
