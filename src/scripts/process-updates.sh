#!/bin/sh

SCRIPT_DIRECTORY=$(dirname $0)
BASE_DIRECTORY=$(dirname $(dirname $SCRIPT_DIRECTORY))

PRINTER_MODEL_CODES="K2P K3 K3M K3V2 KS1"
#PRINTER_MODEL_CODES="KS1"

get_printer_model_name() {
    case "$1" in
        "K2P") echo "Kobra 2 Pro" ;;
        "K3") echo "Kobra 3" ;;
        "K3M") echo "Kobra 3 Max" ;;
        "K3V2") echo "Kobra 3 V2" ;;
        "KS1") echo "Kobra S1" ;;
    esac
}

for PRINTER_MODEL_CODE in $PRINTER_MODEL_CODES; do
    PRINTER_MODEL_NAME=$(get_printer_model_name $PRINTER_MODEL_CODE)

    echo "Processing ${PRINTER_MODEL_NAME} (${PRINTER_MODEL_CODE})..."

    MANIFEST_PATH=manifests/manifest-$(echo ${PRINTER_MODEL_CODE} | tr '[:upper:]' '[:lower:]').json
    MANIFEST_VERSIONS=$(cat $MANIFEST_PATH | jq -r '.firmwares[] | .version')
    MANIFEST_LAST_VERSION=$(cat $MANIFEST_PATH | jq -r '.firmwares | last | .version')

    MANIFEST_MIRROR_PATH=manifests/manifest-$(echo ${PRINTER_MODEL_CODE} | tr '[:upper:]' '[:lower:]')-mirror.json
    MANIFEST_MIRROR_VERSIONS=$(cat $MANIFEST_PATH | jq -r '.firmwares[] | .version')
    MANIFEST_MIRROR_LAST_VERSION=$(cat $MANIFEST_PATH | jq -r '.firmwares | last | .version')

    echo "  Last version: $MANIFEST_LAST_VERSION"

    export MODEL_CODE=$PRINTER_MODEL_CODE
    export CURRENT_VERSION=$MANIFEST_LAST_VERSION

    [ -f .secrets/device.ini ] && export CERTS_DEVICE_INI=$(cat .secrets/device.ini)
    [ -f .secrets/caCrt ] && export CERTS_CACRT=$(cat .secrets/caCrt)
    [ -f .secrets/deviceCrt ] && export CERTS_DEVICECRT=$(cat .secrets/deviceCrt)
    [ -f .secrets/devicePk ] && export CERTS_DEVICEPK=$(cat .secrets/devicePk)

    UPDATE=$(python $SCRIPT_DIRECTORY/check_updates.py)
    #UPDATE=$(cat .tmp/update-$(echo ${PRINTER_MODEL_CODE} | tr '[:upper:]' '[:lower:]').json 2> /dev/null)

    UPDATE_VERSION=$(echo "$UPDATE" | sed 's/$/\\n/' | tr -d '\n' | jq -r '.firmware_version' 2> /dev/null)
    UPDATE_URL=$(echo "$UPDATE" | sed 's/$/\\n/' | tr -d '\n' | jq -r '.firmware_url' 2> /dev/null)
    UPDATE_MD5=$(echo "$UPDATE" | sed 's/$/\\n/' | tr -d '\n' | jq -r '.firmware_md5' 2> /dev/null)
    UPDATE_DATE=$(echo "$UPDATE" | sed 's/$/\\n/' | tr -d '\n' | jq -r '.create_date' 2> /dev/null)
    UPDATE_CHANGES=$(echo "$UPDATE" | sed 's/$/\\n/' | tr -d '\n' | jq -r '.update_desc' 2> /dev/null)

    if [ -z "$UPDATE" ] || [ "$UPDATE_VERSION" = "$MANIFEST_LAST_VERSION" ]; then
        echo "  No update"
        continue
    fi

    echo "  Update: $UPDATE_VERSION"


    ################
    # Send a Discord notification

    echo "  Sending Discord notification..."

    [ -f .secrets/discord-env.sh ] && . .secrets/discord-env.sh

    DISCORD_MESSAGE="New firmware ${UPDATE_VERSION} available for ${PRINTER_MODEL_NAME}\n"
    DISCORD_MESSAGE=$DISCORD_MESSAGE'```'$(echo $UPDATE | jq -r | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')'```'

    curl -H "Content-Type: application/json" \
         -X POST \
         -d "{\"content\": \"$(echo $DISCORD_MESSAGE | sed 's/$/\\n/' | tr -d '\n')\"}" \
         $DISCORD_WEBHOOK_URL


    ################
    # Download the SWU update file

    UPDATE_PATH=.tmp/${PRINTER_MODEL_CODE}_${UPDATE_VERSION}.swu

    if [ ! -f $UPDATE_PATH ]; then
        echo "  Downloading $UPDATE_URL to $UPDATE_PATH..."
        curl -o $UPDATE_PATH $UPDATE_URL
    fi

    CALCULATED_MD5=$(md5sum $UPDATE_PATH | awk '{ print $1 }')

    if [ "$CALCULATED_MD5" != "$UPDATE_MD5" ]; then
        echo "  MD5 checksum mismatch for $UPDATE_PATH (expected $UPDATE_MD5 but got $CALCULATED_MD5)"
        break
    fi


    ################
    # Update the manifests

    UPLOAD_URL="https://cdn.meowcat285.com/rinkhals/${PRINTER_MODEL_NAME}/${PRINTER_MODEL_CODE}_${UPDATE_VERSION}.swu"
    UPLOAD_URL=$(echo $UPLOAD_URL | sed 's/ /%20/')

    cat $MANIFEST_PATH | jq -r ".firmwares += [{\"version\":\"$UPDATE_VERSION\",\"date\":$UPDATE_DATE,\"changes\":\"$UPDATE_CHANGES\",\"md5\":\"$UPDATE_MD5\",\"url\":\"$UPDATE_URL\",\"supported_models\":[\"$PRINTER_MODEL_CODE\"]}]" \
        > $MANIFEST_PATH

    cat $MANIFEST_MIRROR_PATH | jq -r ".firmwares += [{\"version\":\"$UPDATE_VERSION\",\"date\":$UPDATE_DATE,\"changes\":\"$UPDATE_CHANGES\",\"md5\":\"$UPDATE_MD5\",\"url\":\"$UPLOAD_URL\",\"supported_models\":[\"$PRINTER_MODEL_CODE\"]}]" \
        > $MANIFEST_MIRROR_PATH


    ################
    # Upload to the S3 bucket

    #echo "  Uploading to storage..."
    #set -x

    #[ -f .secrets/storage-env.sh ] && . .secrets/storage-env.sh
    #rclone copyto --ignore-existing $UPDATE_PATH "Storage:/${PRINTER_MODEL_NAME}/${PRINTER_MODEL_CODE}_${UPDATE_VERSION}.swu"
    #rclone copyto $MANIFEST_PATH "Storage:/${PRINTER_MODEL_NAME}/manifest.json"


    ################
    # TODO: Analyze the update compared to the previous one

    # TODO: Donwload previous release
    # TODO: Decompress it
    # TODO: WinMerge / Diff previous vs. current
    # TODO: Build a diff report


    ################
    # TODO: Make a PR in Rinkhals repo

    # TODO: Add release notes to the docs
    # TODO: Add compatibility to tools.sh
    # TODO: Adjust README compatibility table
    # TODO: Hash printer.cfg
    # TODO: Create a PR

done
