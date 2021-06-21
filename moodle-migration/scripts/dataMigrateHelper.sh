log(){
  echo "$1" >> "$LOG_FILE"
}

handle_error(){
    echo "$1" >> "$FAILURE_FILE_PATH"
    exit $2
}

clear_output_path(){
  if [ -d "$OUTPUT_FILE_PATH" ]; then rm -rf "$OUTPUT_FILE_PATH"; fi
  mkdir -p "$OUTPUT_FILE_PATH"
  if [ -f "$FAILURE_FILE_PATH" ]; then rm -f "$FAILURE_FILE_PATH"; fi
  if [ -f "$PROGRESS_FILE_PATH" ]; then rm -f "$PROGRESS_FILE_PATH"; fi
  if [ -f "$SUCCESS_FILE_PATH" ]; then rm -f "$SUCCESS_FILE_PATH"; fi
  log "Clearing output path"
}

validate_prerequisite(){
  log "Validating prerequisites"
  log "Verifying if tar is present"
  if tar --version >/dev/null; then
    log "tar present"
  else
    echo "tar package missing. Please install tar and retry" >> "${FAILURE_FILE_PATH}"
    #exit with precondition failed error code
    exit 41
  fi
  log "Verifying if azcopy is present"
  if "$AZ_COPY_PATH/azcopy" --version >/dev/null 2>&1 ; then
    log "azcopy present"
  else
    log "Calling download_azcopy"
    download_azcopy
  fi
  log "Verifying db connection"
  execute_mysql_query "connection_check"
}

download_azcopy(){
  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  if [ ! -d "$OUTPUT_FILE_PATH" ]; then mkdir -p "$AZ_COPY_PATH"; fi

  #URL reference from : https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10
  AZ_COPY_URL="https://aka.ms/downloadazcopy-v10-linux"

  if [ "$(uname)" == "Darwin" ]; then
    AZ_COPY_URL="https://aka.ms/downloadazcopy-v10-mac"
  fi

  # Some Linux machines will have curl, some will have wget; Some will have neither
  # Check which is available make download using the same
  if ! command -v wget &> /dev/null
  then
      log "Could not find wget; Trying with curl"

      if ! command -v curl &> /dev/null
      then
        echo "No wget or curl found; Cannot download azcopy" >> "${FAILURE_FILE_PATH}"
        echo "ERROR Migration failed" >> "${FAILURE_FILE_PATH}"
        exit
      else
        #important: always use -L to follow redirects; else curl will not download the file
        curl -L "${AZ_COPY_URL}" -o "${OUTPUT_FILE_PATH}/azcopy.tar.gz"
      fi
  else
      log "Found wget"
      wget "${AZ_COPY_URL}" -O "${OUTPUT_FILE_PATH}/azcopy.tar.gz"
  fi

  mkdir "${OUTPUT_FILE_PATH}/azcopy"
  tar -xzvf "${OUTPUT_FILE_PATH}/azcopy.tar.gz" --directory "${OUTPUT_FILE_PATH}/azcopy"

  cd "${OUTPUT_FILE_PATH}/azcopy"
  cd azcopy*

  AZ_COPY_PATH="$(pwd)"
  log "Setting Azcopy log location to ${AZ_COPY_PATH}"
  export AZCOPY_LOG_LOCATION=$AZ_COPY_PATH
  log "Setting Azcopy plan location to ${AZ_COPY_PATH}"
  export AZCOPY_JOB_PLAN_LOCATION=$AZ_COPY_PATH

  cd "${DIR}"
}

upload_file_to_azure(){
  source_path="$1"
  file_name="$2"
  excluded_paths="$3"

  AZ_FILE_SAS_URI="${AZ_FILE_SHARE_URL}${file_name}${AZ_SAS_TOKEN}"
  log "Uploading file to azure"
  #If upload fails, then exit with error code 81
  "$AZ_COPY_PATH/azcopy" copy "$source_path" "${AZ_FILE_SAS_URI}" --recursive --overwrite=ifSourceNewer --exclude-path "$excluded_paths" | tee -a "$LOG_FILE" || handle_error "AZCopyFailed" 81
}

get_webserver_config_path(){
if command -v apache2 >/dev/null ; then
  echo "$(locate apache2.conf | head -n 1 )"
fi
}

create_config_folder(){
  log "Creating folder"
  config_dir="${OUTPUT_FILE_PATH}/moodle-migration-config"
  mkdir "$config_dir"
  log "Adding config files"
  phpConfig=$(php -i | grep 'Loaded Configuration File' | sed 's/.*> //g')
  webConfig=$(get_webserver_config_path)
  scp "$phpConfig" "$config_dir"
  php -m > "$config_dir/php_modules.txt"
  scp "$webConfig" "$config_dir"
  echo "$config_dir"
}

archive(){
  log "Archival started"
  source="$1"
  archive_name="$2"
  archive_name+='.tar.gz'
  local source_dir="$(dirname "$source")"
  local source_file="$(basename "$source")"
  tar -C "$source_dir" -zcf "$archive_name" "$source_file"
  log "Archival completed"
  echo "$archive_name"
}

execute_mysql_query(){
  execution_flag="$1"
  dump_file_name="$2"

  local dbName=$(grep  'dbname' $MOODLE_CONFIG_PATH | sed 's/.*= //g' | sed "s/[';]//g")
  local dbUser=$(grep  'dbuser' $MOODLE_CONFIG_PATH | sed 's/.*= //g' | sed "s/[';]//g")
  local dbPass=$(grep  'dbpass' $MOODLE_CONFIG_PATH | sed 's/.*= //g' | sed "s/[';]//g")
  local dbHostFqdn=$(grep  'dbhost' $MOODLE_CONFIG_PATH | sed 's/.*= //g' | sed "s/[';]//g")

  if [[ "$1" == "connection_check" ]]; then
    if mysql  --user="$dbUser" --password="$dbPass" --host="$dbHostFqdn" -e "use $dbName" 2>/dev/null; then
      log "Connection successful"
    else
      log "Connection failed"
    fi
  elif [[ "$1" == "database_dump" ]]; then
    #Try to do a db dump, if it fails exit with error code 91
    mysqldump --single-transaction --user="$dbUser" --password="$dbPass" --host="$dbHostFqdn" $dbName > "$dump_file_name" || handle_error "db dump failed" 91
  fi
}

create_db_dump(){
  log "Creating db dump"
  execute_mysql_query "database_dump" "$DB_DUMP_PATH"
  echo "$DB_DUMP_PATH"
}

check_moodle_enabled_on_webserver(){
    moodleEnabled=$(locate sites-enabled/moodle)
    if [[ "$moodleEnabled" == *"apache2"* ]]; then
        echo "apache2"
    else
        echo "Moodle site is not enabled on webserver. Please check sites-enabled location of webserver" > "$FAILURE_FILE_PATH"
        #Exit with unsupported webserver type
        exit 41
    fi
}

get_cert_location(){
    webServerType=""

    if command -v apache2 >/dev/null ; then
        webServerType="apache2"
    else
        echo "Invalid Web Server type." > "$FAILURE_FILE_PATH"
        #Exit with unsupported webserver type
        exit 41
    fi

    webServerConfigPath=$(get_webserver_config_path)
    if [ "$webServerType" = "apache2" ]; then
        cert_location="$(grep "SSLCertificateFile" $webServerConfigPath | sed 's/SSLCertificateFile//')"
    fi
    echo "$cert_location"
}