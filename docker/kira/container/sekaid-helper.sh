#!/bin/bash
source $SELF_SCRIPTS/utils.sh
# QUICK EDIT: FILE="$SELF_CONTAINER/sekaid-helper.sh" && rm $FILE && nano $FILE && chmod 555 $FILE

function txAwait() {
    START_TIME="$(date -u +%s)"

    if (! $(isTxHash "$1")) ; then
        RAW=$(cat)
        TIMEOUT=$1
    else
        RAW=$1
        TIMEOUT=$2
    fi

    (! $(isNaturalNumber $TIMEOUT)) && TIMEOUT=0
    [[ $TIMEOUT -le 0 ]] && MAX_TIME="∞" || MAX_TIME="$TIMEOUT"

    if (! $(isTxHash "$RAW")) ; then
        # INPUT example: {"height":"0","txhash":"DF8BFCC9730FDBD33AEA184EC3D6C37B4311BC1C0E2296893BC020E4638A0D6F","codespace":"","code":0,"data":"","raw_log":"","logs":[],"info":"","gas_wanted":"0","gas_used":"0","tx":null,"timestamp":""}
        VAL=$(echo $RAW | jsonParse "" 2> /dev/null || echo "")
        if [ -z "$VAL" ] ; then
            echoErr "ERROR: Failed to propagate transaction:"
            echoErr "$RAW"
            return 1
        fi

        TXHASH=$(echo $VAL | jsonQuickParse "txhash" 2> /dev/null || echo "")
        if [ -z "$VAL" ] ; then
            echoErr "ERROR: Transaction hash 'txhash' was NOT found in the tx propagation response:"
            echoErr "$RAW"
            return 1
        fi
    else
        TXHASH="${RAW^^}"
    fi

    echoInfo "INFO: Transaction hash '$TXHASH' was found!"
    echoInfo "INFO: Please wait for tx confirmation, timeout will occur in $MAX_TIME seconds ..."

    while : ; do
        ELAPSED=$(($(date -u +%s) - $START_TIME))
        OUT=$(sekaid query tx $TXHASH --output=json 2> /dev/null | jsonParse "" 2> /dev/null || echo -n "")
        if [ ! -z "$OUT" ] ; then
            echoInfo "INFO: Transaction query response received received:"
            echo $OUT | jq

            CODE=$(echo $OUT | jsonQuickParse "code" 2> /dev/null || echo -n "")
            if [ "$CODE" == "0" ] ; then
                echoInfo "INFO: Transaction was confirmed sucessfully!"
                return 0
            else
                echoErr "ERROR: Transaction failed with exit code '$CODE'"
                return 1
            fi
        else
            echoWarn "WAITING: Transaction is NOT confirmed yet, elapsed ${ELAPSED}/${MAX_TIME} s"
        fi

        if [[ $TIMEOUT -gt 0 ]] && [[ $ELAPSED -gt $TIMEOUT ]] ; then
            echoInfo "INFO: Transaction query response was NOT received:"
            echo $RAW | jq 2> /dev/null || echoErr "$RAW"
            echoErr "ERROR: Timeout, failed to confirm tx hash '$TXHASH' within ${TIMEOUT} s limit"
            return 1
        else
            sleep 5
        fi
    done
}

function tryGetValidator() {
    VAL_ADDR="${1,,}"
    if [[ $VAL_ADDR == kiravaloper* ]] ; then
        VAL_STATUS=$(sekaid query validator --val-addr="$VAL_ADDR" --output=json 2> /dev/null | jsonParse 2> /dev/null || echo -n "")
    elif [[ $VAL_ADDR == kira* ]] ; then
        VAL_STATUS=$(sekaid query validator --addr="$VAL_ADDR" --output=json 2> /dev/null | jsonParse 2> /dev/null || echo -n "") 
    else
        VAL_STATUS=""
    fi
    echo $VAL_STATUS
}

function whitelistValidator() {
    ADDR="$1"
    VAL_STATUS=$(tryGetValidator $ADDR)
    if [ ! -z "$VAL_STATUS" ] ; then
        echoInfo "INFO: Validator $ADDR was already added to the set"
        return 1
    fi

    echoInfo "INFO: Adding validator $ADDR to the validator set"
    echoInfo "INFO: Fueling address $ADDR with funds"
    sekaid tx bank send validator $ADDR "954321ukex" --keyring-backend=test --chain-id=$NETWORK_NAME --fees 100ukex --yes --log_format=json --gas=1000000 --broadcast-mode=async | txAwait

    echoInfo "INFO: Assigning PermClaimValidator ($PermClaimValidator) permission"
    sekaid tx customgov proposal assign-permission $PermClaimValidator --addr=$ADDR --from=validator --keyring-backend=test --chain-id=$NETWORK_NAME --description="Adding Testnet Validator $ADDR" --fees=100ukex --yes --log_format=json --gas=1000000 --broadcast-mode=async | txAwait 

    echoInfo "INFO: Searching for the last proposal submitted on-chain"
    LAST_PROPOSAL=$(sekaid query customgov proposals --output json | jq -cr '.proposals | last | .proposal_id') 

    echoInfo "INFO: Voting YES (1) on proposal $LAST_PROPOSAL"
    sekaid tx customgov proposal vote $LAST_PROPOSAL 1 --from=validator --chain-id=$NETWORK_NAME --keyring-backend=test  --fees=100ukex --yes --log_format=json --gas=1000000 --broadcast-mode=async | txAwait

    echoInfo "INFO: Listing proposal $LAST_PROPOSAL status"
    sekaid query customgov votes $LAST_PROPOSAL --output json | jq && sekaid query customgov proposal $LAST_PROPOSAL --output json | jq
    echo "Time now: $(date '+%Y-%m-%dT%H:%M:%S')"
    echoInfo "INFO: Validator $ADDR will be added to the set after proposal $LAST_PROPOSAL passes"
}