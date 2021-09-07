#!/bin/bash
set +e && source "/etc/profile" &>/dev/null && set -e
source $KIRA_MANAGER/utils.sh
# quick edit: FILE="$KIRA_MANAGER/kira/monitor-containers.sh" && rm $FILE && nano $FILE && chmod 555 $FILE
# systemctl restart kirascan && journalctl -u kirascan -f --output cat
set -x

echo "INFO: Started kira network contianers monitor..."

timerStart MONITOR_CONTAINERS
STATUS_SCAN_PATH="$KIRA_SCAN/status"
SCAN_LOGS="$KIRA_SCAN/logs"
LATEST_STATUS_SCAN_PATH="$KIRA_SCAN/latest_status"
NETWORKS=$(globGet NETWORKS)
CONTAINERS=$(globGet CONTAINERS)

UPGRADE_NAME=$(globGet UPGRADE_NAME)
UPGRADE_TIME=$(globGet UPGRADE_TIME)
UPGRADE_PLAN=$(globGet UPGRADE_PLAN)
NEW_UPGRADE_PLAN=""

set +x
echoWarn "------------------------------------------------"
echoWarn "|        STARTING: KIRA CONTAINER SCAN $KIRA_SETUP_VER"
echoWarn "|-----------------------------------------------"
echoWarn "|        KIRA SCAN: $KIRA_SCAN"
echoWarn "|       CONTAINERS: $CONTAINERS"
echoWarn "|         NETWORKS: $NETWORKS"
echoWarn "| OLD UPGRADE NAME: $UPGRADE_NAME"
echoWarn "|  INTERX REF. DIR: $INTERX_REFERENCE_DIR"
echoWarn "------------------------------------------------"
sleep 1
set -x

[ -z "$(globGet LATEST_BLOCK)" ] && globSet LATEST_BLOCK "0"
[ ! -f "$LATEST_STATUS_SCAN_PATH" ] && echo -n "" > $LATEST_STATUS_SCAN_PATH

mkdir -p "$INTERX_REFERENCE_DIR"

for name in $CONTAINERS; do
    echoInfo "INFO: Processing container $name"
    mkdir -p "$DOCKER_COMMON/$name"

    PIDX=$(globGet "${name}_STATUS_PID")

    if kill -0 "$PIDX" 2>/dev/null; then
        echoInfo "INFO: $name container status check is still running, see logs '$SCAN_LOGS/${name}-status.error.log' ..."
        continue
    fi

    # cat "$SCAN_LOGS/seed-status.error.log"
    timerStart "${name}_SCAN" 
    globSet "${name}_SCAN_DONE" "false"
    $KIRA_MANAGER/kira/container-status.sh "$name" "$NETWORKS" &> "$SCAN_LOGS/${name}-status.error.log" &
    globSet "${name}_STATUS_PID" "$!"

    if [[ "${name,,}" =~ ^(validator|sentry|snapshot|seed)$ ]] ; then
        echoInfo "INFO: Fetching sekai status..."
        RPC_PORT="KIRA_${name^^}_RPC_PORT" && RPC_PORT="${!RPC_PORT}"
        echo $(timeout 3 curl --fail 0.0.0.0:$RPC_PORT/status 2>/dev/null | jsonParse "result" 2>/dev/null || echo -n "") | globSet "${name}_SEKAID_STATUS"
        # TODO: REMOVE DOCKER
        echoInfo "INFO: Fetching upgrade plan..."
        TMP_UPGRADE_PLAN=$(docker exec -i $name bash -c "source /etc/profile && showUpgradePlan" | jsonParse "" || echo "")
        (! $(isNullOrEmpty "$TMP_UPGRADE_PLAN")) && [ "$UPGRADE_PLAN" != "$TMP_UPGRADE_PLAN" ] && NEW_UPGRADE_PLAN=$TMP_UPGRADE_PLAN
    elif [ "${name,,}" == "interx" ] ; then
        echoInfo "INFO: Fetching sekai & interx status..."
        echo $(timeout 3 curl --fail 0.0.0.0:$KIRA_INTERX_PORT/api/kira/status 2>/dev/null || echo -n "") | globSet "${name}_SEKAID_STATUS"
        echo $(timeout 3 curl --fail 0.0.0.0:$KIRA_INTERX_PORT/api/status 2>/dev/null || echo -n "") | globSet "${name}_INTERX_STATUS"
    fi
done

if (! $(isNullOrEmpty "$NEW_UPGRADE_PLAN")) ; then
    echoInfo "INFO: New upgrade plan is available!"
    TMP_UPGRADE_NAME=$(echo "$NEW_UPGRADE_PLAN" | jsonParse "plan.name" || echo "")
    TMP_UPGRADE_TIME=$(echo "$NEW_UPGRADE_PLAN" | jsonParse "plan.min_upgrade_time" || echo "")
    TMP_UPGRADE_INSTATE=$(echo "$NEW_UPGRADE_PLAN" | jsonParse "plan.instate_upgrade" || echo "")
    if [ "$UPGRADE_NAME" != "$TMP_UPGRADE_NAME" ] && ($(isNaturalNumber "$TMP_UPGRADE_TIME")) && (! $(isNullOrEmpty "$TMP_UPGRADE_NAME")) && (! $(isNullOrEmpty "$TMP_UPGRADE_INSTATE")) ; then
        echoInfo "INFO: New upgrade plan was found! $TMP_UPGRADE_NAME -> $TMP_UPGRADE_NAME"
        globSet "UPGRADE_NAME" "$TMP_UPGRADE_NAME"
        globSet "UPGRADE_TIME" "$TMP_UPGRADE_TIME"
        globSet "UPGRADE_INSTATE" "$TMP_UPGRADE_INSTATE"
        globSet "UPGRADE_PLAN" "$NEW_UPGRADE_PLAN"
        globSet "UPDATE_FAIL_COUNTER" "0"
        globSet "PLAN_DONE" "false"
        globSet "PLAN_FAIL" "false"
        globSet "PLAN_FAIL_COUNT" "0"
        globSet "UPGRADE_DONE" "false"
        globSet "UPGRADE_REPOS_DONE" "false"
        globSet "UPGRADE_PAUSE_ATTEMPTED" "false"
        globSet "UPGRADE_UNPAUSE_ATTEMPTED" "false"
        globSet PLAN_START_DT "$(date +'%Y-%m-%d %H:%M:%S')"
        globSet PLAN_END_DT ""
        
        rm -fv $KIRA_DUMP/kiraplan-done.log.txt || echoInfo "INFO: plan log dump could not be wipred before plan service start"
        systemctl start kiraplan
    else
        echoWarn "WARNING: Upgrade plan is invalid"
    fi
else
    echoInfo "INFO: No new upgrade plans were found!"
fi

NEW_LATEST_BLOCK=0
NEW_LATEST_BLOCK_TIME=$(globGet LATEST_BLOCK_TIME) && (! $(isNaturalNumber "$LATEST_BLOCK_TIME")) && NEW_LATEST_BLOCK_TIME=0
NEW_LATEST_STATUS=0
for name in $CONTAINERS; do
    echoInfo "INFO: Waiting for '$name' scan processes to finalize"
    PIDX=$(globGet "${name}_STATUS_PID")

    set +x
    while : ; do
        SCAN_SPAN=$(timerSpan "${name}_SCAN")
        SCAN_DONE=$(globGet "${name}_SCAN_DONE")
        [ "${SCAN_DONE}" == "true" ] && break
        echoInfo "INFO: Waiting for $name scan (PID $PIDX) to finlize, elapsed $SCAN_SPAN/60 seconds ..."
        [[ $SCAN_SPAN -gt 60 ]] && echoErr "ERROR: Timeout failed to scan $name container, see error logs '$SCAN_LOGS/${name}-status.error.log'" && exit 1
        if ! kill -0 "$PIDX" 2>/dev/null ; then
            [ "$(globSet ${name}_SCAN_DONE)" != "true" ] && \
                echoErr "ERROR: Background PID $PIDX failed for the $name container. See error logs: '$SCAN_LOGS/${name}-status.error.log'" && exit 1
        fi
        sleep 1
    done
    set -x

    STATUS_PATH=$(globFile "${name}_SEKAID_STATUS")
    if (! $(isFileEmpty "$STATUS_PATH")) ; then
        LATEST_BLOCK=$(jsonQuickParse "latest_block_height" $STATUS_PATH || echo "0")
        LATEST_BLOCK_TIME=$(jsonParse "sync_info.latest_block_time" $STATUS_PATH || echo "1970-01-01T00:00:00.000000000Z")
        # convert time to unix timestamp
        LATEST_BLOCK_TIME=$(date -d "$LATEST_BLOCK_TIME" +"%s")
        
        (! $(isNaturalNumber "$LATEST_BLOCK")) && LATEST_BLOCK=0
        (! $(isNaturalNumber "$LATEST_BLOCK_TIME")) && LATEST_BLOCK_TIME=0
        
        CATCHING_UP=$(jsonQuickParse "catching_up" $STATUS_PATH || echo "false")
        ($(isNullOrEmpty "$CATCHING_UP")) && CATCHING_UP=false
        if [[ "${name,,}" =~ ^(sentry|seed|validator)$ ]] ; then
            NODE_ID=$(jsonQuickParse "id" $STATUS_PATH 2> /dev/null  || echo "false")
            ($(isNodeId "$NODE_ID")) && echo "$NODE_ID" > "$INTERX_REFERENCE_DIR/${name,,}_node_id"
        fi

        if [[ $NEW_LATEST_BLOCK -lt $LATEST_BLOCK ]] && [[ $NEW_LATEST_BLOCK_TIME -lt $LATEST_BLOCK_TIME ]] && [[ "${name,,}" =~ ^(sentry|seed|validator|interx)$ ]] ; then
            NEW_LATEST_BLOCK="$LATEST_BLOCK"
            NEW_LATEST_BLOCK_TIME="$LATEST_BLOCK_TIME"
            NEW_LATEST_STATUS="$(tryCat $STATUS_PATH)"
        fi
    else
        LATEST_BLOCK="0"
        CATCHING_UP="false"
    fi
    
    echoInfo "INFO: Saving status props..."
    PREVIOUS_BLOCK=$(globGet "${name}_BLOCK")
    globSet "${name}_BLOCK" "$LATEST_BLOCK"
    globSet "${name}_SYNCING" "$CATCHING_UP"
done

# save latest known block height
if [ "$NEW_LATEST_BLOCK" != "0" ] && [ "$NEW_LATEST_BLOCK_TIME" != "0"  ] ; then
    echoInfo "INFO: Block height chaned to $LATEST_BLOCK ($NEW_LATEST_BLOCK_TIME)"
    globSet INTERNAL_BLOCK $NEW_LATEST_BLOCK
    globSet LATEST_BLOCK $NEW_LATEST_BLOCK
    globSet LATEST_BLOCK_TIME $NEW_LATEST_BLOCK_TIME
    globSet latest_block_height "$NEW_LATEST_BLOCK" "$GLOBAL_COMMON_RO"

    OLD_MIN_HEIGHT=$(globGet MIN_HEIGHT) && (! $(isNaturalNumber "$OLD_MIN_HEIGHT")) && OLD_MIN_HEIGHT=0
    if [[ $OLD_MIN_HEIGHT -lt $NEW_LATEST_BLOCK ]] ; then
        globSet MIN_HEIGHT $NEW_LATEST_BLOCK
        globSet MIN_HEIGHT $NEW_LATEST_BLOCK $GLOBAL_COMMON_RO
    fi
fi
# save latest known status
(! $(isNullOrEmpty "$NEW_LATEST_STATUS")) && echo "$NEW_LATEST_STATUS" > $LATEST_STATUS_SCAN_PATH

set +x
echoWarn "------------------------------------------------"
echoWarn "| FINISHED: CONTAINERS MONITOR                 |"
echoWarn "|  ELAPSED: $(timerSpan MONITOR_CONTAINERS) seconds"
echoWarn "------------------------------------------------"
sleep 1
set -x