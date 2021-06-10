#!/bin/bash
#
# Bitnami persistence library
# Used for bringing persistence capabilities to applications that don't have clear separation of data and logic

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/bitnami/scripts/libfs.sh
. /opt/bitnami/scripts/libos.sh
. /opt/bitnami/scripts/liblog.sh
. /opt/bitnami/scripts/libversion.sh

########################
# Check if an application directory was already persisted
# Globals:
#   BITNAMI_VOLUME_DIR
# Arguments:
#   $1 - App folder name
# Returns:
#   true if all steps succeeded, false otherwise
#########################
is_app_initialized() {
    local -r app="${1:?missing app}"
    local -r persist_dir="${BITNAMI_VOLUME_DIR}/${app}"
    if ! is_mounted_dir_empty "$persist_dir"; then
        true
    else
        false
    fi
}
