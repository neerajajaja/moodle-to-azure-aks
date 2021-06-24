#!/bin/bash

#install rsync and copy files from azure file share to azure disk if not already copied

FILE=success.txt
if [[ ! -f "$FILE" ]]; then
    install_packages rsync
    mkdir -p "/bitnami/moodle" "/bitnami/moodledata" "/afs/moodle" "/afs/moodledata"
    rsync -avz /afs/moodle /bitnami
    rsync -avz /afs/moodledata /bitnami
    echo "Data copied from afs to azure disk successfully!" > "$FILE"
fi
