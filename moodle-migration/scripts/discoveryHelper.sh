#!/bin/bash
configPath="$1"

check_moodle_enabled_on_webserver(){
    moodleEnabled=$(locate sites-enabled/moodle)
    if [[ "$moodleEnabled" == *"apache2"* ]]; then
        echo "apache2"
    else
        echo "Moodle site is not enabled on webserver. Please check sites-enabled location of webserver" > $FAILURE_FILE_PATH
        #Exit with unsupported webserver type
        exit 41
    fi
}

get_cert_location(){
    if [ "$webServerType" = "apache2" ]; then
        cert_location="$(grep "SSLCertificateFile" $webServerConfigPath | sed 's/SSLCertificateFile//')"
    fi
    echo $cert_location
}

get_site_profile(){
    webServerType=""
    isApache2Present=$(command -v apache2 > /dev/null)
    if [[ ! -z "$isApache2Present" ]]]; then
        webServerType=$(check_moodle_enabled_on_webserver)
    fi
    if command -v apache2 > /dev/null ; then
        webServerType="apache2"
    else
        echo "Invalid Web Server type." > $FAILURE_FILE_PATH
        #Exit with unsupported webserver type
        exit 41
    fi

    if [ "$webServerType" = "apache2" ]; then
        webServerVersion=$($webServerType -v | head -n 1 | sed 's/[^0-9.]*//g')
        webServerConfigPath=$(locate $webServerType.conf | head -n 1 )
    fi

    siteUrl=$(grep  'wwwroot' "$configPath" | sed 's/.*= //g' | sed "s/[';]//g")

    #According to Moodle documentation, wwwroot should specify https extention if ssl is configured.
    sslEnabled=$(echo "$siteUrl" | grep 'https')
    if [ -z "$sslEnabled" ]; then
        httpsTermination="None"
    else   
        #sed 's/[//].*$//g' would eliminate any line commented out using // 
        #According to Moodle best practice, sslproxy should be enabled if a load balancer is used.
        sslProxy=$(grep  'sslproxy' "$configPath" | sed 's/[//].*$//g')
        if [ -n  "$sslProxy" ]; then
            httpsTermination="VMSS"     #we will set https termination to VMSS since AppGw is not supported as of now.
        else
            httpsTermination="VMSS"
            caCertLocation=$(get_cert_location)
            sslCertLocation=$(dirname "$caCertLocation")
        fi
    fi

    #ARM template expects 'apache' if server type is 'apache2'. Make that change.
    local webserverTypeForOutput="$webServerType"
    if [[ $webserverTypeForOutput == "apache2" ]]; then
        webserverTypeForOutput="apache"
    fi

    echo '"siteProfile": {
            "webServerType": "'$webserverTypeForOutput'",
            "webServerVersion": "'$webServerVersion'",
            "webServerConfigPath": "'$webServerConfigPath'",
            "siteURL": "'$siteUrl'",
            "httpsTermination": "'$httpsTermination'",
            "sslCertLocation": "'$sslCertLocation'",
            "caCertLocation": "'$caCertLocation'",
            "extraModules": []
        },'
}

get_moodle_profile(){
    versionPath=$(echo "$configPath" | sed 's/config.php/version.php/')
    moodleVersion=$(grep  'Human-friendly version' $versionPath | sed 's/[^0-9.+]//g' | sed 's/[+].*//')
    codePath=$(echo "$configPath" | sed 's/config.php//')
    cache=$(grep  'cachedir' "$configPath" | sed 's/[//].*$//g')
    if [ -n  "$cache" ]; then
        cacheEnabled=true
    else
        cacheEnabled=false
    fi

    local moodleVersionForOutput=""
    if [[ $moodleVersion == 3.8* ]]; then
        moodleVersionForOutput="MOODLE_38_STABLE"
    elif [[ $moodleVersion == 3.9* ]]; then 
        moodleVersionForOutput="MOODLE_39_STABLE"
    elif [[ $moodleVersion == 3.10* ]]; then 
        moodleVersionForOutput="MOODLE_310_STABLE"
    else
        echo "Moodle version '$moodleVersion' is not supported. Only 3.8.x, 3.9.x and 3.10.x are supported."
        exit -1
    fi

    echo '"moodleProfile": {
            "version": "'$moodleVersionForOutput'",
            "codePath": "'$codePath'",
            "cacheEnabled": '$cacheEnabled',
            "searchEnabled": false,
            "extraModules": []
        },'
}

get_db_profile(){
    dbType=$(grep  'dbtype' "$configPath" | sed 's/.*= //g' | sed "s/[';]//g")
        if [[ "$dbType" -eq "mysqli" ]]; then 
        dbType="mysql"  #db type needs to be mysql in case of mysqli discovery
    fi

    dbName=$(grep  'dbname' "$configPath" | sed 's/.*= //g' | sed "s/[';]//g")
    dbUser=$(grep  'dbuser' "$configPath" | sed 's/.*= //g' | sed "s/[';]//g")
    dbPass=$(grep  'dbpass' "$configPath" | sed 's/.*= //g' | sed "s/[';]//g")
    dbHostFqdn=$(grep  'dbhost' "$configPath" | sed 's/.*= //g' | sed "s/[';]//g")
    #This query is mysql specific and doesnt work on other db languages
    dbSizeQuery="SELECT ROUND(SUM(data_length + index_length)/1073741824, 2) FROM information_schema.TABLES where table_schema = '$dbName';"
    dbVersionQuery="SELECT VERSION();"
    dbSize=$(mysql  --user="$dbUser" --password="$dbPass" --host="$dbHostFqdn" -sNe "$dbSizeQuery" 2> /dev/null)
    dbSize=$(get_ceiling_of_number $dbSize)
    #Trimming last 3 charecters using sed command since mysql version is returned as X.X.XX and ARM template expects as X.X
    dbVersion=$(mysql  --user="$dbUser" --password="$dbPass" --host="$dbHostFqdn" -sNe "$dbVersionQuery" 2> /dev/null | cut -c1-3 )
    #minimum size of db is 5 GB
    if [[ $dbSize -lt 5 ]]; then 
        dbSize=5 
    fi 
    dbCollation=$(grep  'collation' "$configPath" | sed 's/.*=> //g' | sed "s/[',]//g")
    echo '"dbServerProfile": {
            "type": "'$dbType'",
            "dbName": "'$dbName'",
            "dbUser": "'$dbUser'",
            "dbHostFqdn": "'$dbHostFqdn'",
            "dbSizeInGB": "'$dbSize'",
            "version": "'$dbVersion'",
            "dbSettings": {
                "collation": "'$dbCollation'"
            },
            "extraModules": []
        },'
}

get_file_server_profile(){
    dataPath=$(grep  'dataroot' "$configPath" | sed 's/.*= //g' | sed "s/[';]//g")
    fileShareSize=$(ls -l --block-size=GB "$dataPath" | head -n 1 | sed 's/[^0-9]//g')
    fileShareSize=$(get_ceiling_of_number $fileShareSize)
    #minimum size of fileshare is 100 GB
    if [[ $fileShareSize -lt 100 ]]; then 
        fileShareSize=100 
    fi 
    echo '"fileServerProfile": {
            "dataPath": "'$dataPath'",
            "fileShareSizeInGB": "'${fileShareSize}'"
        },'
}

get_php_profile(){
    phpVersion=$(php -v | head -n 1 | sed 's/[-].*$//g' | sed 's/[^0-9.]*//g')
    phpVersion=$(echo "$phpVersion" | cut -d "." -f 1-2) # Only major.minor version is needed. i.e. 7.2 is needed from 7.2.3

    phpModules=$(php -m | awk 'NF' | tr '\n' ',' |sed 's/.$//' | sed 's/[^,]*/"&"/g')
    phpConfigPath=$(php -i | grep 'Loaded Configuration File' | sed 's/.*> //g')

    echo '"phpProfile": {
            "phpVersion": "'$phpVersion'",
            "phpConfigPath": "'$phpConfigPath'",
            "extraModules": [ '${phpModules[@]}' ]
        }'
}

get_ceiling_of_number(){
    echo $(bc <<< "if ($1 % 1) ($1 / 1)+1 else ($1 / 1)")
}