#!/bin/bash
set +e && source $ETC_PROFILE &>/dev/null && set -e
source $SELF_SCRIPTS/utils.sh
exec 2>&1
set -x

echoInfo "INFO: Staring sentry setup..."

EXECUTED_CHECK="$COMMON_DIR/executed"
CFG_CHECK="${COMMON_DIR}/configuring"

SNAP_HEIGHT_FILE="$COMMON_DIR/snap_height"
SNAP_NAME_FILE="$COMMON_DIR/snap_name"

SNAP_DIR_INPUT="$COMMON_READ/snap"
SNAP_FILE_INPUT="$COMMON_READ/snap.zip"
SNAP_INFO="$SEKAID_HOME/data/snapinfo.json"

LIP_FILE="$COMMON_READ/local_ip"
PIP_FILE="$COMMON_READ/public_ip"
DATA_DIR="$SEKAID_HOME/data"
LOCAL_GENESIS="$SEKAID_HOME/config/genesis.json"
COMMON_GENESIS="$COMMON_READ/genesis.json"
DATA_GENESIS="$DATA_DIR/genesis.json"

echo "OFFLINE" > "$COMMON_DIR/external_address_status"
rm -fv $CFG_CHECK

while [ ! -f "$EXECUTED_CHECK" ] && ($(isFileEmpty "$SNAP_FILE_INPUT")) && ($(isDirEmpty "$SNAP_DIR_INPUT")) && ($(isFileEmpty "$COMMON_GENESIS")) ; do
    echoInfo "INFO: Waiting for genesis file to be provisioned... ($(date))"
    sleep 5
done

while ($(isFileEmpty "$LIP_FILE")) && [ "${NODE_TYPE,,}" == "priv_sentry" ] ; do
   echoInfo "INFO: Waiting for Local IP to be provisioned... ($(date))"
   sleep 5
done

while ($(isFileEmpty "$PIP_FILE")) && ( [ "${NODE_TYPE,,}" == "sentry" ] || [ "${NODE_TYPE,,}" == "seed" ] ); do
    echoInfo "INFO: Waiting for Public IP to be provisioned... ($(date))"
    sleep 5
done

SNAP_HEIGHT=$(cat $SNAP_HEIGHT_FILE || echo -n "")
SNAP_NAME=$(cat $SNAP_NAME_FILE || echo -n "")
SNAP_OUTPUT="/snap/$SNAP_NAME"

echoInfo "INFO: Sucess, genesis file was found!"
echoInfo "INFO: Snap Height: $SNAP_HEIGHT"
echoInfo "INFO:   Snap Name: $SNAP_NAME"

if [ ! -f "$EXECUTED_CHECK" ]; then
    rm -rfv $SEKAID_HOME
    mkdir -p $SEKAID_HOME/config/
  
    sekaid init --chain-id="$NETWORK_NAME" "KIRA SENTRY NODE" --home=$SEKAID_HOME
  
    rm -fv $SEKAID_HOME/config/node_key.json
    cp $COMMON_DIR/node_key.json $SEKAID_HOME/config/

    if (! $(isFileEmpty "$SNAP_FILE_INPUT")) || (! $(isDirEmpty "$SNAP_DIR_INPUT")) ; then
        echoInfo "INFO: Snap file was found, attepting integrity verification and data recovery..."
        if (! $(isFileEmpty "$SNAP_FILE_INPUT")) ; then 
            cd $DATA_DIR
            jar xvf $SNAP_FILE_INPUT
            cd $SEKAID_HOME
        elif (! $(isDirEmpty "$SNAP_DIR_INPUT")) ; then
            cp -rfv "$SNAP_DIR_INPUT/." "$DATA_DIR"
        else
            echoErr "ERROR: Snap file or directory was not found"
            exit 1
        fi
    
        if [ -f "$DATA_GENESIS" ] ; then
            echoInfo "INFO: Genesis file was found within the snapshot folder, attempting recovery..."
            SHA256_DATA_GENESIS=$(sha256sum $DATA_GENESIS | awk '{ print $1 }' | xargs || echo -n "")
            SHA256_COMMON_GENESIS=$(sha256sum $COMMON_GENESIS | awk '{ print $1 }' | xargs || echo -n "")
            if [ -z "$SHA256_DATA_GENESIS" ] || [ "$SHA256_DATA_GENESIS" != "$SHA256_COMMON_GENESIS" ] ; then
                echoErr "ERROR: Expected genesis checksum of the snapshot to be '$SHA256_DATA_GENESIS' but got '$SHA256_COMMON_GENESIS'"
                exit 1
            else
                echoInfo "INFO: Genesis checksum '$SHA256_DATA_GENESIS' was verified sucessfully!"
            fi
        fi
    fi
fi

echoInfo "INFO: Loading configuration..."
$SELF_CONTAINER/configure.sh
set +e && source "$ETC_PROFILE" &>/dev/null && set -e
touch $EXECUTED_CHECK

if ($(isNaturalNumber $SNAP_HEIGHT)) && [[ $SNAP_HEIGHT -gt 0 ]] && [ ! -z "$SNAP_NAME_FILE" ] ; then
    echoInfo "INFO: Snapshot was requested at height $SNAP_HEIGHT, executing..."
    rm -frv $SNAP_OUTPUT

    touch ./output.log
    LAST_SNAP_BLOCK=0
    TOP_SNAP_BLOCK=0
    PID1=""
    while :; do
        echoInfo "INFO: Checking node status..."
        SNAP_STATUS=$(sekaid status 2>&1 | jsonParse "" 2>/dev/null || echo -n "")
        SNAP_BLOCK=$(echo $SNAP_STATUS | jsonQuickParse "latest_block_height" 2>/dev/null || echo -n "")
        (! $(isNaturalNumber "$SNAP_BLOCK")) && SNAP_BLOCK="0"

        [[ $TOP_SNAP_BLOCK -lt $SNAP_BLOCK ]] && TOP_SNAP_BLOCK=$SNAP_BLOCK
        echoInfo "INFO: Latest Block Height: $TOP_SNAP_BLOCK"

        if ps -p "$PID1" >/dev/null; then
            echoInfo "INFO: Waiting for snapshot node to sync  $TOP_SNAP_BLOCK/$SNAP_HEIGHT"
        elif [ ! -z "$PID1" ]; then
            echoWarn "WARNING: Node finished running, starting tracking and checking final height..."
            kill -15 "$PID1" || echoInfo "INFO: Failed to kill sekai PID $PID1 gracefully P1"
            sleep 5
            kill -9 "$PID1" || echoInfo "INFO: Failed to kill sekai PID $PID1 gracefully P2"
            sleep 10
            kill -2 "$PID1" || echoInfo "INFO: Failed to kill sekai PID $PID1"
            # invalidate all possible connections
            echoInfo "INFO: Starting block sync..."
            sekaid start --home="$SEKAID_HOME" --grpc.address="$GRPC_ADDRESS" --trace  &>./output.log &
            PID1=$!
            sleep 30
        fi

        if [[ "$TOP_SNAP_BLOCK" -ge "$SNAP_HEIGHT" ]]; then
            echoInfo "INFO: Snap was compleated, height $TOP_SNAP_BLOCK was reached!"
            break
        elif [[ "$TOP_SNAP_BLOCK" -gt "$LAST_SNAP_BLOCK" ]]; then
            echoInfo "INFO: Success, block changed! ($LAST_SNAP_BLOCK -> $TOP_SNAP_BLOCK)"
            LAST_SNAP_BLOCK="$TOP_SNAP_BLOCK"
        else
            echoWarn "WARNING: Blocks are not changing..."
        fi
        sleep 30
    done

    kill -15 "$PID1" || echoInfo "INFO: Failed to kill sekai PID $PID1 gracefully P1"
    sleep 5
    kill -9 "$PID1" || echoInfo "INFO: Failed to kill sekai PID $PID1 gracefully P2"
    sleep 10
    kill -2 "$PID1" || echoInfo "INFO: Failed to kill sekai PID $PID1"

    echoInfo "INFO: Printing latest output log..."
    cat ./output.log | tail -n 100

    echoInfo "INFO: Creating backup package '$SNAP_OUTPUT' ..."
    # make sure healthcheck will not interrupt configuration
    touch $CFG_CHECK
    cp -afv "$LOCAL_GENESIS" $SEKAID_HOME/data
    echo "{\"height\":$SNAP_HEIGHT}" > "$SNAP_INFO"

    # to prevent appending root path we must zip all from within the target data folder
    cp -rfv "$SEKAID_HOME/data/." "$SNAP_OUTPUT"
    [ ! -d "$SNAP_OUTPUT" ] && echo "INFO: Failed to create snapshot, directory $SNAP_OUTPUT was not found" && exit 1
    rm -fv "$SNAP_HEIGHT_FILE" "$SNAP_NAME_FILE" "$CFG_CHECK"
fi

echoInfo "INFO: Starting sekaid..."
sekaid start --home=$SEKAID_HOME --grpc.address="$GRPC_ADDRESS" --trace 
