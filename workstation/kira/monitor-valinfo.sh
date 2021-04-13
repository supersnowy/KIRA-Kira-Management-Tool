#!/bin/bash
set +e && source "/etc/profile" &>/dev/null && set -e
source $KIRA_MANAGER/utils.sh
# quick edit: FILE="$KIRA_MANAGER/kira/monitor-valinfo.sh" && rm $FILE && nano $FILE && chmod 555 $FILE
set -x

SCRIPT_START_TIME="$(date -u +%s)"
SCAN_DIR="$KIRA_HOME/kirascan"
VALADDR_SCAN_PATH="$SCAN_DIR/valaddr"
VALOPERS_SCAN_PATH="$SCAN_DIR/valopers"
VALIDATORS64_SCAN_PATH="$SCAN_DIR/validators64"
VALSTATUS_SCAN_PATH="$SCAN_DIR/valstatus"
VALINFO_SCAN_PATH="$SCAN_DIR/valinfo"
CONSENSUS_SCAN_PATH="$SCAN_DIR/consensus"

set +x
echoWarn "------------------------------------------------"
echoWarn "|       STARTING KIRA VALIDATORS SCAN v0.2.2.4 |"
echoWarn "|-----------------------------------------------"
echoWarn "|   VALINFO_SCAN_PATH: $VALINFO_SCAN_PATH"
echoWarn "| VALSTATUS_SCAN_PATH: $VALSTATUS_SCAN_PATH"
echoWarn "|  VALOPERS_SCAN_PATH: $VALOPERS_SCAN_PATH"
echoWarn "|   VALADDR_SCAN_PATH: $VALADDR_SCAN_PATH"
echoWarn "| CONSENSUS_SCAN_PATH: $CONSENSUS_SCAN_PATH"
echoWarn "------------------------------------------------"
set -x

touch "$VALADDR_SCAN_PATH" "$VALSTATUS_SCAN_PATH" "$VALOPERS_SCAN_PATH" "$VALINFO_SCAN_PATH"

echo "INFO: Saving valopers info..."
(timeout 60 curl "0.0.0.0:$KIRA_INTERX_PORT/api/valopers?all=true" | jq -rc '.' || echo -n "") > $VALOPERS_SCAN_PATH
(timeout 60 curl "0.0.0.0:$KIRA_INTERX_PORT/api/consensus" | jq -rc '.' || echo -n "") > $CONSENSUS_SCAN_PATH

# let containers know the validators info
cp -afv "$VALOPERS_SCAN_PATH" "$DOCKER_COMMON_RO/valopers"
cp -afv "$CONSENSUS_SCAN_PATH" > "$DOCKER_COMMON_RO/consensus"

if [[ "${INFRA_MODE,,}" =~ ^(validator|local)$ ]] ; then
    echo "INFO: Validator info will the scanned..."
else
    echo -n "" > $VALINFO_SCAN_PATH
    echo -n "" > $VALADDR_SCAN_PATH
    echo -n "" > $VALSTATUS_SCAN_PATH
    exit 0
fi

VALSTATUS=""
VALADDR=$(docker exec -i validator sekaid keys show validator -a --keyring-backend=test || echo -n "")
if [ ! -z "$VALADDR" ] && [[ $VALADDR == kira* ]] ; then
    echo "$VALADDR" > $VALADDR_SCAN_PATH
else
    VALADDR=$(cat $VALADDR_SCAN_PATH || echo -n "")
fi

if [ ! -z "$VALADDR" ] && [[ $VALADDR == kira* ]] ; then
    VALSTATUS=$(docker exec -i validator sekaid query validator --addr=$VALADDR --output=json | jq -rc '.' || echo -n "")
else
    VALSTATUS=""
fi

if [ -z "$VALSTATUS" ] ; then
    echoErr "ERROR: Validator address or status was not found"
    WAITING=$(jq '.waiting' $VALOPERS_SCAN_PATH || echo -n "" )
    if [ ! -z "$VALADDR" ] && [ ! -z "$WAITING" ] && [[ $WAITING =~ "$VALADDR" ]]; then
        echo "{ \"status\": \"WAITING\" }" > $VALSTATUS_SCAN_PATH
    else
        echo -n "" > $VALSTATUS_SCAN_PATH
    fi
else
    echo "$VALSTATUS" > $VALSTATUS_SCAN_PATH
fi

VALOPER_FOUND="false"
(jq -rc '.validators | .[] | @base64' $VALOPERS_SCAN_PATH 2> /dev/null || echo -n "") > $VALIDATORS64_SCAN_PATH
if ($(isFileEmpty "$VALIDATORS64_SCAN_PATH")) ; then
    echoWarn "WARNING: Failed to querry velopers info"
    echo -n "" > $VALINFO_SCAN_PATH
else
    while IFS="" read -r row || [ -n "$row" ] ; do
    sleep 0.1
        vobj=$(echo ${row} | base64 --decode 2> /dev/null 2> /dev/null || echo -n "")
        vaddr=$(echo "$vobj" | grep -Eo '"address"[^,]*' | grep -Eo '[^:]*$' | xargs 2> /dev/null || echo -n "")
        if [ "$VALADDR" == "$vaddr" ] ; then
            echo "$vobj" > $VALINFO_SCAN_PATH
            VALOPER_FOUND="true"
            break
        fi
    done < $VALIDATORS64_SCAN_PATH
fi

if [ "${VALOPER_FOUND,,}" != "true" ] ; then
    echoInfo "INFO: Validator '$VALADDR' was not found in the valopers querry"
    echo -n "" > $VALINFO_SCAN_PATH
    exit 0
fi

sleep 5

set +x
echoWarn "------------------------------------------------"
echoWarn "| FINISHED: VALIDATORS MONITOR                 |"
echoWarn "|  ELAPSED: $(($(date -u +%s) - $SCRIPT_START_TIME)) seconds"
echoWarn "------------------------------------------------"
set -x
