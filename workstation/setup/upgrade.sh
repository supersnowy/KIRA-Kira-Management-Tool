#!/bin/bash
set +x
set +e && source "/etc/profile" &>/dev/null && set -e
# quick edit: FILE="$KIRA_MANAGER/setup/upgrade.sh" && rm $FILE && nano $FILE && chmod 555 $FILE

SCRIPT_START_TIME="$(date -u +%s)"

echoWarn "------------------------------------------------"
echoWarn "| STARTED: KIRA UPGRADE SCRIPT $KIRA_SETUP_VER"
echoWarn "|-----------------------------------------------"
echoWarn "| BASH SOURCE: ${BASH_SOURCE[0]}"
echoWarn "------------------------------------------------"

UPGRADE_PLAN_FILE=$(globFile UPGRADE_PLAN)
UPGRADE_PLAN_RES_FILE=$(globFile UPGRADE_PLAN_RES)
UPGRADE_PLAN_RES64_FILE=$(globFile UPGRADE_PLAN_RES64)
jsonParse "plan.resources" $UPGRADE_PLAN_FILE $UPGRADE_PLAN_RES_FILE
(jq -rc '.[] | @base64' $UPGRADE_PLAN_RES_FILE 2> /dev/null || echo -n "") > $UPGRADE_PLAN_RES64_FILE

if ($(isFileEmpty "$UPGRADE_PLAN_RES64_FILE")) ; then
    echoErr "ERROR: Failed to querry upgrade plan resources info"
    exit 1
fi

UPGRADE_INSTATE=$(globGet UPGRADE_INSTATE)
(! $(isBoolean "$UPGRADE_INSTATE")) && echoErr "ERROR: Invalid instate upgrade parameter, expected boolean but got '$UPGRADE_INSTATE'" && sleep 10 && exit 1

if [ "${INFRA_MODE,,}" == "validator" ] ; then
    UPGRADE_PAUSE_ATTEMPTED=$(globGet UPGRADE_PAUSE_ATTEMPTED)
    if [ "${INFRA_MODE,,}" == "validator" ] && [ "${UPGRADE_PAUSE_ATTEMPTED,,}" == "false" ] ; then
        echoInfo "INFO: Infra is running in the validator mode. Attempting to pause the validator in order to perform safe in-state upgrade!"
        globSet "UPGRADE_PAUSE_ATTEMPTED" "true"
        # NOTE: Pause disabled until safety min validators hotfix
        # VFAIL="false" && docker exec -i validator /bin/bash -c ". /etc/profile && pauseValidator validator" || VFAIL="true"
        VFAIL="false"
        
        [ "${VFAIL,,}" == "true" ] && echoWarn "WARNING: Failed to pause validator node" || echoInfo "INFO: Validator node was sucesfully paused"
    fi
fi

echoInfo "INFO: Halting and re-starting all containers..."
for name in $CONTAINERS; do
    [ "${name,,}" == "registry" ] && continue
    echoInfo "INFO: Halting and re-starting '$name' container..."
    
    $KIRA_MANAGER/kira/container-pkill.sh "$name" "true" "restart" "false"

    
    SNAP_STATUS="$KIRA_SNAP/status"
    echo "$SNAP_FILENAME" > "$SNAP_STATUS/latest"
done

MIN_BLOCK=$(globGet LATEST_BLOCK) && (! $(isNaturalNumber "$MIN_BLOCK")) && MIN_BLOCK="0"

if [[ "${INFRA_MODE,,}" =~ ^(validator|sentry|seed)$ ]]; then
    echoInfo "INFO: Starting cleanup before snapshoot is generated..."
    $KIRA_MANAGER/kira/cleanup.sh

    CONTAINER_NAME="${INFRA_MODE,,}"
    COMMON_PATH="$DOCKER_COMMON/${CONTAINER_NAME}"
    SNAP_FILENAME="${NETWORK_NAME}-$MAX_HEIGHT-$(date -u +%s).zip"
    ADDRBOOK_FILE="$COMMON_PATH/upgrade-addrbook.json"
    KIRA_SNAP_PATH="$KIRA_SNAP/$SNAP_FILENAME"

    rm -fv $ADDRBOOK_FILE $KIRA_SNAP_PATH

    docker exec -i $CONTAINER_NAME /bin/bash -c ". /etc/profile && \$SELF_CONTAINER/upgrade.sh $UPGRADE_INSTATE $MIN_BLOCK $SNAP_FILENAME"

    echoInfo "INFO: Starting cleanup after snapshoot was already generated..."
    $KIRA_MANAGER/kira/cleanup.sh

    [ ! -f "$ADDRBOOK_FILE" ] && echoErr "ERROR: Failed to create snapshoot file '$ADDRBOOK_FILE'" && sleep 10 && exit 1
    [ ! -f "$KIRA_SNAP_PATH" ] && echoErr "ERROR: Failed to create snapshoot file '$SNAP_FILE'" && sleep 10 && exit 1

    CDHelper text lineswap --insert="KIRA_SNAP_PATH=\"$KIRA_SNAP_PATH\"" --prefix="KIRA_SNAP_PATH=" --path=$ETC_PROFILE --append-if-found-not=True
    CDHelper text lineswap --insert="NEW_NETWORK=\"false\"" --prefix="NEW_NETWORK=" --path=$ETC_PROFILE --append-if-found-not=True

    echoInfo "INFO: Recovering public & private seed nodes..."
    SEEDS_DUMP="/tmp/seedsdump"
    ADDR_DUMP="/tmp/addrdump"
    ADDR_DUMP_ARR="/tmp/addrdumparr"
    ADDR_DUMP_BASE64="/tmp/addrdump64"
    rm -fv $ADDR_DUMP $ADDR_DUMP_ARR $ADDR_DUMP_BASE64
    touch $ADDR_DUMP $SEEDS_DUMP $PUBLIC_SEEDS
    jsonParse "addrs" $ADDRBOOK_FILE $ADDR_DUMP_ARR
    (jq -rc '.[] | @base64' $ADDR_DUMP_ARR 2> /dev/null || echo -n "") > $ADDR_DUMP_BASE64

    while IFS="" read -r row || [ -n "$row" ] ; do
        jobj=$(echo ${row} | base64 --decode 2> /dev/null 2> /dev/null || echo -n "")
        last_success=$(echo "$jobj" | jsonParse "last_success" 2> /dev/null || echo -n "") && last_success=$(delWhitespaces $last_success | tr -d '"' || "")
        ( [ -z "$last_success" ] || [ "$last_success" == "0001-01-01T00:00:00Z" ] ) && echoInfo "INFO: Skipping address, connection was never establised." && continue
        nodeId=$(echo "$jobj" | jsonQuickParse "id" 2> /dev/null || echo -n "") && nodeId=$(delWhitespaces $nodeId | tr -d '"' || "")
        (! $(isNodeId "$nodeId")) && echoInfo "INFO: Skipping address, node id '$nodeId' is invalid." && continue
        ip=$(echo "$jobj" | jsonQuickParse "ip" 2> /dev/null || echo -n "") && ip=$(delWhitespaces $ip | tr -d '"' || "")
        (! $(isIp "$ip")) && echoInfo "INFO: Skipping address, node ip '$ip' is NOT a valid IPv4." && continue
        port=$(echo "$jobj" | jsonQuickParse "port" 2> /dev/null || echo -n "") && port=$(delWhitespaces $port | tr -d '"' || "")
        (! $(isPort "$port")) && echoInfo "INFO: Skipping address, '$port' is NOT a valid port." && continue
        if grep -q "$nodeId" "$SEEDS_DUMP" || grep -q "$ip:$port" "$SEEDS_DUMP" || grep -q "$nodeId" "$PUBLIC_SEEDS" || grep -q "$ip:$port" "$PUBLIC_SEEDS" ; then
            echoWarn "WARNING: Address '$nodeId@$ip:$port' is already present in the seeds list or invalid, last conn ($last_success)"
        else
            echoInfo "INFO: Success, found new node addess '$nodeId@$ip:$port', last conn ($last_success)"
            echo "$nodeId@$ip:$port" >> $SEEDS_DUMP
        fi
    done < $ADDR_DUMP_BASE64

    if (! $(isFileEmpty $SEEDS_DUMP)) ; then
        echoInfo "INFO: New public seed nodes were found in the address book. Saving addressess to PUBLIC_SEEDS '$PUBLIC_SEEDS'..."
        cat $SEEDS_DUMP >> $PUBLIC_SEEDS
    else
        echoWarn "WARNING: NO new public seed nodes were found in the address book!"
    fi
else
    echoErr "ERROR: Unsupported infra mode '$INFRA_MODE'" && sleep 10 && exit 1
fi

UPGRADE_REPOS_DONE=$(globGet UPGRADE_REPOS_DONE)
if [ "${UPGRADE_REPOS_DONE,,}" == "false" ] ; then

    while IFS="" read -r row || [ -n "$row" ] ; do
        jobj=$(echo ${row} | base64 --decode 2> /dev/null 2> /dev/null || echo -n "")
        joid=$(echo "$jobj" | jsonQuickParse "id" 2> /dev/null || echo -n "")
        ($(isNullOrWhitespaces "$joid")) && echoWarn "WARNING: Undefined plan id" && continue

        # kira repo is processed during plan setup, so ony other repost must be upgraded
        [ "$joid" == "kira" ] && echoInfo "INFO: Infra repo was already upgraded..." && continue

        repository=$(echo "$jobj" | jsonParse "git" 2> /dev/null || echo -n "")
        ($(isNullOrWhitespaces "$repository")) && echoErr "ERROR: Repository of the plan '$joid' was undefined" && sleep 10 && exit 1
        checkout=$(echo "$jobj" | jsonParse "checkout" 2> /dev/null || echo -n "")
        checksum=$(echo "$jobj" | jsonParse "checksum" 2> /dev/null || echo -n "")
        if ($(isNullOrWhitespaces "$checkout")) && ($(isNullOrWhitespaces "$checksum")) ; then
            echoErr "ERROR: Checkout ('$checkout') or Checksum ('$checksum') was undefined"
            sleep 10
            exit 1
        fi

        REPO_ZIP="/tmp/repo.zip"
        REPO_TMP="/tmp/repo"
        rm -fv $REPO_ZIP
        cd $HOME && rm -rfv $REPO_TMP
        mkdir -p $REPO_TMP && cd "$REPO_TMP"

        DOWNLOAD_SUCCESS="true"
        if (! $(isNullOrWhitespaces "$checkout")) ; then
            echoInfo "INFO: Fetching '$joid' repository from git..."
            $KIRA_SCRIPTS/git-pull.sh "$repository" "$checkout" "$REPO_TMP" 555 || DOWNLOAD_SUCCESS="false"
            [ "${DOWNLOAD_SUCCESS,,}" == "false" ] && echoErr "ERROR: Failed to pull '$repository' from  '$checkout' branch." && sleep 10 && exit 1
            echoInfo "INFO: Repo '$repository' pull from branch '$checkout' suceeded, navigating to '$REPO_TMP' and compressing source into '$REPO_ZIP'..."
            cd "$REPO_TMP" && zip -9 -r -v "$REPO_ZIP" .* || DOWNLOAD_SUCCESS="false"
        else
            echoInfo "INFO: Checkour branch was not found, downloading '$joid' repository from external file..."
            wget "$repository" -O $REPO_ZIP || DOWNLOAD_SUCCESS="false"
        fi

        if [ "$DOWNLOAD_SUCCESS" == "true" ] && [ -f "$REPO_ZIP" ]; then
            echoInfo "INFO: Download or Fetch of '$joid' repository suceeded"
            if (! $(isNullOrWhitespaces "$checksum")) ; then
                cd $HOME && rm -rfv $REPO_TMP && mkdir -p $REPO_TMP
                unzip -o -: $KM_ZIP -d $REPO_TMP
                chmod -R -v 555 $REPO_TMP
                REPO_HASH=$(CDHelper hash SHA256 -p="$REPO_TMP" -x=true -r=true --silent=true -i="$REPO_TMP/.git,$REPO_TMP/.gitignore")
                rm -rfv $REPO_TMP

                if [ "$REPO_HASH" != "$checksum" ] ; then
                    echoInfo "INFO: Checksum verification suceeded"
                else
                    echoErr "ERROR: Chcecksum verification failed, expected '$checksum', but got '$REPO_HASH'"
                    sleep 10
                    exit 1
                fi
            fi
        else
            echoErr "ERROR: Failed to download ($DOWNLOAD_SUCCESS) or package '$joid' repository" && sleep 10 && exit 1
        fi

        if ($(isLetters "$joid")) ; then
            CDHelper text lineswap --insert="${joid^^}_CHECKSUM=$checksum" --prefix="${joid^^}_CHECKSUM=" --path=$ETC_PROFILE --append-if-found-not=True
            CDHelper text lineswap --insert="${joid^^}_BRANCH=$checkout" --prefix="${joid^^}_BRANCH=" --path=$ETC_PROFILE --append-if-found-not=True
            CDHelper text lineswap --insert="${joid^^}_CHECKSUM=$checksum" --prefix="${joid^^}_CHECKSUM=" --path=$ETC_PROFILE --append-if-found-not=True
        else
            echoWarn "WARNING: Unknown plan id '$joid'"
        fi
    done < $UPGRADE_PLAN_RES64_FILE

    echoInfo "INFO: Starting update service..."
    globSet UPGRADE_REPOS_DONE "true"
    globSet UPDATE_FAIL_COUNTER "0"
    globSet UPDATE_DONE "false"
    globSet SETUP_REBOOT ""
    globSet SETUP_START_DT "$(date +'%Y-%m-%d %H:%M:%S')"
    globSet SETUP_END_DT ""
    systemctl daemon-reload
    systemctl start kiraup
fi

UPGRADE_REPOS_DONE=$(globGet UPGRADE_REPOS_DONE)
UPGRADE_UNPAUSE_ATTEMPTED=$(globGet UPGRADE_UNPAUSE_ATTEMPTED)
UPDATE_DONE=$(globGet UPDATE_DONE)
if [ "${UPDATE_DONE,,}" == "true" ] && [ "${UPGRADE_REPOS_DONE,,}" == "true" ] ; then
    echoInfo "INFO: Un-halting and re-starting all containers..."

    if [ "${INFRA_MODE,,}" == "validator" ] && [ "${UPGRADE_PAUSE_ATTEMPTED,,}" == "true" ]  && [ "${UPGRADE_UNPAUSE_ATTEMPTED,,}" == "true" ] ; then
        echoInfo "INFO: Infra is running in the validator mode. Attempting to unpause the validator in order to finalize a safe in-state upgrade!"
        globSet "UPGRADE_UNPAUSE_ATTEMPTED" "true"
        # NOTE: Pause disabled until safety min validators hotfix
        # VFAIL="false" && docker exec -i validator /bin/bash -c ". /etc/profile && unpauseValidator validator" || VFAIL="true"
        VFAIL="false"

        if [ "${VFAIL,,}" == "true" ] ; then
            echoWarn "WARNING: Failed to pause validator node"
        else
            echoInfo "INFO: Validator node was sucesfully unpaused"
            globSet UPGRADE_DONE "true"
            globSet PLAN_END_DT "$(date +'%Y-%m-%d %H:%M:%S')"
        fi
    else
        globSet UPGRADE_DONE "true"
        globSet PLAN_END_DT "$(date +'%Y-%m-%d %H:%M:%S')"
    fi
fi

echoWarn "------------------------------------------------"
echoWarn "| FINISHED: UPGRADE SCRIPT $KIRA_SETUP_VER"
echoWarn "|  ELAPSED: $(($(date -u +%s) - $SCRIPT_START_TIME)) seconds"
echoWarn "------------------------------------------------"

sleep 10