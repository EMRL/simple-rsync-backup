#!/bin/bash
export TERM=${TERM:-dumb}
TODAY="$(date +%Y-%m-%d)"
START_TIME="$(date +%s)"

################################ USER SETINGS #################################

# Name this backup
BACKUP_NAME="Web Backup"

# Root path of all backup
ROOT_BACKUP_PATH="/path/to/backup/root"

# Directories within ROOT_BACKUP_PATH to recursively backup
# format is (directory directory directory)
BACKUP_SOURCE=(directory directory directory)

# Destination location for backup archives
BACKUP_DESTINATION="/backup/path"

# Comma seperated list of emails to receive notification - leave blank 
# to disable
NOTIFICATION_EMAIL="you@email.com"

# Email the notificatios will be sent from
NOTIFICATION_FROM_EMAIL="your-backup@email.com"

# Notification label, usually something like [BACKUP] - this is pre-pended to 
# the subject line
NOTIFICTION_LABEL="[BACKUP]"

# Slack (See https://YOURTEAMNAME.slack.com/apps/manage/custom-integration to 
# learn how to get started) - leave this blank to disable 
NOTIFICATION_SLACK="https://hooks.slack.com/services/#########/#########/########################"

# If using tar, set the below value to TRUE
# USE_TAR="TRUE"

####################### NO NEED TO EDIT BELOW THIS LINE #######################

# Main application
function main() {
    get_fullpath        # Make sure we have what we need to run
    backup              # Run the backup and upload
    filecount           # Count number of backup files 
    email_notify        # Build and send email
    slack_notify        # Build and send Slack webhook
    cleanup             # Clean up leftovers
}

function get_fullpath() {
    # Get absolute paths to critical commands
    var=(sendmail curl wget	tar	rsync)
    for i in "${var[@]}" ; do
        read -r "${i}_cmd" <<< ""
        echo "${i}_cmd" > /dev/null
        if [[ -x "$(command -v ${i})" ]]; then
            eval "${i}_cmd=\"$(which ${i})\""
        fi
    done
}

function backup() {	
    # Loops through the variables
    for i in "${BACKUP_SOURCE[@]}" ; do
        if [[ "${USE_TAR}" == "TRUE" ]]; then
            TAR_FILE="${i}-${TODAY}.tgz"
            make_tarball
        else
            rsync_files
        fi
    done
}

function make_tarball() {
    echo "Creating ${TAR_FILE}..."
    "${tar_cmd}" cfz "/tmp/${TAR_FILE}" "${ROOT_BACKUP_PATH}/${i}" 2> /dev/null & spinner $!
    echo "Archiving ${TAR_FILE}..."
    cp -Rpv "/tmp/${TAR_FILE}" "${BACKUP_DESTINATION}" 2> /dev/null & spinner $!

    # Cleanup and log
    [[ -w "${ROOT_BACKUP_PATH}/${i}" ]] && rm -f "/tmp/${TAR_FILE}"
    echo "   ${TAR_FILE}" >> /tmp/bu.log
}

function rsync_files() {
    # Rsync files and generate upload manifest
    echo "Backing up ${i}..."
    # Strip our extra rsync garabage and remove lines with trailing slash
    (rsync -ai "${ROOT_BACKUP_PATH}"/"${i}" "${BACKUP_DESTINATION}" | sed 's/............//') >> /tmp/bu.log
    awk '!/\/$/' /tmp/bu.log > "/tmp/.tmp" && mv "/tmp/.tmp" "/tmp/bu.log"
}

function filecount() {
    FILES=$(wc -l < "/tmp/bu.log")
    
    # Build the correct text string
    if [[ "${FILES}" -eq "0" ]]; then
        FILES_SUMMARY="Nothing to backup"
        return
    else
        if [[ "${FILES}" -ne "1" ]]; then
            FILES_LABEL="files"
        else
            FILES_LABEL="file"
        fi
        FILES_SUMMARY="${FILES} ${FILES_LABEL} backed up"
        PAYLOAD="$(</tmp/bu.log)"
    fi
    
    # How long did the operation take?
    END_TIME="$(date +%s)"
    if [[ "$((END_TIME-START_TIME))" -ne "0" ]]; then
        DURATION_TIME="in $((END_TIME-START_TIME)) seconds"
    fi
    echo "${FILES_SUMMARY} ${DURATION_TIME}"
}

function email_notify() {
    if [[ -n "${NOTIFICATION_EMAIL}" ]] && [[ "${FILES}" -ne "0" ]]; then
        (
        echo "From: ${NOTIFICATION_FROM_EMAIL} <${NOTIFICATION_FROM_EMAIL}>"
        echo "To: ${NOTIFICATION_EMAIL}"
        echo "Subject: ${NOTIFICTION_LABEL} ${BACKUP_NAME}"
        echo "Content-Type: text/plain"
        echo
        echo "${BACKUP_NAME}"
        echo "---------------------"
        echo "${PAYLOAD}"
        echo
        echo -e "${FILES_SUMMARY} ${DURATION_TIME}"
        ) | "${sendmail_cmd}" -t
    fi
}

function slack_notify() {
    if [[ -n "${NOTIFICATION_SLACK}" ]] && [[ -n "${FILES}" ]]; then
        # Someday icon  may change if an error check is added
        SLACK_ICON=":closed_lock_with_key:"
        SLACK_MESSAGE="*${BACKUP_NAME}*: ${FILES_SUMMARY} ${DURATION_TIME}"
        "${curl_cmd}" -s -X POST --data "payload={\"text\": \"${SLACK_ICON} ${SLACK_MESSAGE}\"}" "${NOTIFICATION_SLACK}" > /dev/null
    fi
}

# Progress spinner; we'll see if this works
function spinner() {
    if [[ "${QUIET}" != "1" ]]; then
        local pid=$1
        local delay=0.15
        local spinstr='|/-\'
        tput civis;	
        while [[ "$(ps a | awk '{print $1}' | grep ${pid})" ]]; do
              local temp=${spinstr#?}
              printf "Working... %c  " "$spinstr"
              local spinstr=$temp${spinstr%"$temp"}
              sleep $delay
              printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\b"
        done
        printf "            \b\b\b\b\b\b\b\b\b\b\b\b"
        tput cnorm;
      fi
}

function cleanup() {
    # Cleanup
    [[ -w "/tmp/bu.log" ]] && rm -f "/tmp/bu.log"
}

# Run the app
main
