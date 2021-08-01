#!/bin/bash

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

function tryGetPermissions() {
    ADDR=$1
    [[ $ADDR == kira* ]] && echo $(sekaid query customgov permissions $ADDR --output=json 2> /dev/null | jsonParse 2> /dev/null || echo -n "") && echo -n ""
}

function isPermBlacklisted() {
    ADDR=$1
    PERM=$2
    if (! $(isNaturalNumber $PERM)) || [[ $ADDR != kira* ]] ; then
        echo "false"
    else
        INDEX=$(tryGetPermissions $ADDR 2> /dev/null | jq ".blacklist | index($PERM)" 2> /dev/null || echo -n "")
        ($(isNaturalNumber $INDEX)) && echo "true" || echo "false"
    fi
}

function isPermWhitelisted() {
    ADDR=$1
    PERM=$2
    if (! $(isNaturalNumber $PERM)) || [[ $ADDR != kira* ]] ; then
        echo "false"
    else
        INDEX=$(tryGetPermissions $ADDR 2> /dev/null | jq ".whitelist | index($PERM)" 2> /dev/null || echo -n "")
        if ($(isNaturalNumber $INDEX)) && (! $(isPermBlacklisted $ADDR $PERM)) ; then
            echo "true" 
        else
            echo "false"
        fi
    fi
}

# e.g. tryGetValidator kiraXXXXXXXXXXX
# e.g. tryGetValidator kiravaloperXXXXXXXXXXX
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

function lastProposal() {
    PROPOSALS=$(sekaid query customgov proposals --limit=1 --output json 2> /dev/null || echo "")
    [ -z "$PROPOSALS" ] && echo 0 && return 1
    LAST_PROPOSAL=$(echo $PROPOSALS | jq -cr '.proposals | last | .proposal_id' 2> /dev/null || echo "") 
    (! $(isNaturalNumber $LAST_PROPOSAL)) && echo 0 && return 2
    [[ $LAST_PROPOSAL -le 0 ]] && echo 0 && return 3
    echo $LAST_PROPOSAL
    return 0
}

# voteYes $(lastProposal) validator
function voteYes() {
    PROPOSAL=$1
    ACCOUNT=$2
    YES=1
    echoInfo "INFO: Voting YES on proposal $PROPOSAL with account $ACCOUNT"
    sekaid tx customgov proposal vote $PROPOSAL $YES --from=$ACCOUNT --chain-id=$NETWORK_NAME --keyring-backend=test  --fees=100ukex --yes --log_format=json --broadcast-mode=async | txAwait
}

function networkProperties() {
    NETWORK_PROPERTIES=$(sekaid query customgov network-properties --output=json 2> /dev/null || echo "" | jq -rc 2> /dev/null || echo "")
    [ -z "$NETWORK_PROPERTIES" ] && echo -n "" && return 1
    echo $NETWORK_PROPERTIES
    return 0
}

# showVotes $(lastProposal) 
function showVotes() {
    sekaid query customgov votes $1 --output json | jsonParse
}

# showProposal $(lastProposal) 
function showProposal() {
    sekaid query customgov proposal $1 --output json | jsonParse
}

function showProposals() {
    sekaid query customgov proposals --limit=999999999 --output json | jsonParse
}

# propAwait $(lastProposal) 
function propAwait() {
    START_TIME="$(date -u +%s)"
    if (! $(isNaturalNumber "$1")) ; then
        ID=$(cat) && STATUS=$1 && TIMEOUT=$2
    else
        ID=$1 && STATUS=$2 && TIMEOUT=$3
    fi
    
    PROP=$(showProposal $ID 2> /dev/null || echo -n "")
    if [ -z "$PROP" ] ; then
        echoErr "ERROR: Proposal $ID was NOT found"
    else
        echoInfo "INFO: Waiting for proposal $ID to be finalized"
        (! $(isNaturalNumber $TIMEOUT)) && TIMEOUT=0
        [[ $TIMEOUT -le 0 ]] && MAX_TIME="∞" || MAX_TIME="$TIMEOUT"
        while : ; do
            ELAPSED=$(($(date -u +%s) - $START_TIME))
            RESULT=$(showProposal $ID 2> /dev/null | jq ".result" 2> /dev/null | xargs 2> /dev/null || echo -n "")
            [ -z "$STATUS" ] && ( [ "${RESULT,,}" == "vote_pending" ] || [ "${RESULT,,}" == "vote_result_enactment" ] ) && break
            [ ! -z "$STATUS" ] && [ "${RESULT,,}" == "${STATUS,,}" ] && break
            if [[ $TIMEOUT -gt 0 ]] && [[ $ELAPSED -gt $TIMEOUT ]] ; then
                echoErr "ERROR: Timeout, failed to finalize proposal '$ID' within ${TIMEOUT} s limit"
                return 1
            else
                sleep 1
            fi
        done
        echoInfo "INFO: Proposal was finalized ($RESULT)"
    fi
}

# e.g. whitelistValidator validator kiraXXXXXXXXXXX
function whitelistValidator() {
    ACC="$1"
    ADDR="$2"
    ($(isNullOrEmpty $ACC)) && echoErr "ERROR: Account name was not defined " && return 1
    ($(isNullOrEmpty $ADDR)) && echoErr "ERROR: Validator address was not defined " && return 1
    if ($(isPermWhitelisted $ADDR $PermClaimValidator)) ; then
        echoWarn "WARNING: Address $ADDR was already whitelisted as validator"
    else
        echoInfo "INFO: Adding $ADDR to the validator set"
        echoInfo "INFO: Fueling address $ADDR with funds from $ACC"
        sekaid tx bank send $ACC $ADDR "954321ukex" --keyring-backend=test --chain-id=$NETWORK_NAME --fees 100ukex --yes --log_format=json --broadcast-mode=async | txAwait

        echoInfo "INFO: Assigning PermClaimValidator ($PermClaimValidator) permission"
        sekaid tx customgov proposal assign-permission $PermClaimValidator --addr=$ADDR --from=$ACC --keyring-backend=test --chain-id=$NETWORK_NAME --description="Adding Testnet Validator $ADDR" --fees=100ukex --yes --log_format=json --broadcast-mode=async | txAwait 

        echoInfo "INFO: Searching for the last proposal submitted on-chain and voting YES"
        LAST_PROPOSAL=$(lastProposal) 
        voteYes $LAST_PROPOSAL validator

        echoInfo "INFO: Showing proposal $LAST_PROPOSAL votes"
        showVotes $LAST_PROPOSAL | jq

        echoInfo "INFO: Showing proposal $LAST_PROPOSAL status"
        showProposal $LAST_PROPOSAL | jq

        echoErr "Date Time Now: $(date '+%Y-%m-%dT%H:%M:%S')"
        echoInfo "INFO: Validator $ADDR will be added to the set after proposal $LAST_PROPOSAL passes"
        #proposalAwait $(lastProposal)
    fi
}

# whitelistValidators <account> <file-name>
# e.g.: whitelistValidators validator ./whitelist
function whitelistValidators() {
    ACCOUNT=$1
    WHITELIST=$2
    if [ -f "$WHITELIST" ] ; then 
        echoInfo "INFO: List of validators was found ($WHITELIST)"
        while read key ; do
            key=$(echo "$key" | xargs || echo -n "")
            if [ -z "$key" ] ; then
                echoWarn "INFO: Invalid key $key"
                continue
            fi
            echoInfo "INFO: Whitelisting '$key' using account '$ACCOUNT'"
            whitelistValidator validator $key || echoErr "ERROR: Failed to whitelist $key"
        done < $WHITELIST
    else
        echoErr "ERROR: List of validators was NOT found ($WHITELIST)"
    fi
}

# claimValidatorSeat <account> <moniker> <timeout-seconds>
# e.g.: claimValidatorSeat validator "BOB's NODE" 180
function claimValidatorSeat() {
    ACCOUNT=$1
    MONIKER=$2
    TIMEOUT=$3
    ($(isNullOrEmpty $ACCOUNT)) && echoInfo "INFO: Account name was not defined " && return 1
    ($(isNullOrEmpty $MONIKER)) && MONIKER=$(openssl rand -hex 16)
    (! $(isNaturalNumber $TIMEOUT)) && TIMEOUT=180
    sekaid tx customstaking claim-validator-seat --from "$ACCOUNT" --keyring-backend=test --home=$SEKAID_HOME --moniker="$MONIKER" --chain-id=$NETWORK_NAME --broadcast-mode=async --fees=100ukex --yes | txAwait $TIMEOUT
}

# e.g. showAddress validator
function showAddress() {
    echo $(sekaid keys show "$1" --keyring-backend=test --output json 2> /dev/null | jsonParse "address" 2> /dev/null || echo -n "")
}

# e.g. showBalance validator
function showBalance() {
    ADDR=$1
    if [[ $ADDR != kira* ]] ; then
        ADDR=$(showAddress $ADDR)
    fi

    if [ ! -z "$ADDR" ] ; then
        echo $(sekaid query bank balances "$ADDR" --output json 2> /dev/null | jsonParse 2> /dev/null || echo -n "")
    fi
}

function updateCommitTimeout {
    echoInfo "INFO: Updating commit timeout..."
    VALOPERS_FILE="$COMMON_READ/valopers"
    ACTIVE_VALIDATORS=$(jsonQuickParse "active_validators" $VALOPERS_FILE || echo "0")
    if ($(isNaturalNumber "$ACTIVE_VALIDATORS")) ; then
        echoInfo "INFO: Discovered $ACTIVE_VALIDATORS active validators, calculating timeout..."
        TIMEOUT_COMMIT=$(echo "scale=3; ((( 5 / ( $ACTIVE_VALIDATORS + 1 ) ) * 1000 ) + 1000) " | bc)
        TIMEOUT_COMMIT=$(echo "scale=0; ( $TIMEOUT_COMMIT / 1 ) " | bc)
        (! $(isNaturalNumber "$TIMEOUT_COMMIT")) && TIMEOUT_COMMIT="5000"
        TIMEOUT_COMMIT="${TIMEOUT_COMMIT}ms"

        if [ "${TIMEOUT_COMMIT}" != "$CFG_timeout_commit" ] ; then
            echoInfo "INFO: Commit timeout will be changed to $TIMEOUT_COMMIT"
            CDHelper text lineswap --insert="CFG_timeout_commit=${TIMEOUT_COMMIT}" --prefix="CFG_timeout_commit=" --path=$ETC_PROFILE --append-if-found-not=True
            CDHelper text lineswap --insert="timeout_commit = \"${TIMEOUT_COMMIT}\"" --prefix="timeout_commit =" --path=$CFG
        else
            echoInfo "INFO: Commit timout ($TIMEOUT_COMMIT) will not be changed"
        fi
    else
        echoInfo "WARNING: Unknown validator cound, could not calculate timeout commit."
    fi
}

# e.g. showStatus -> { ... }
function showStatus() {
    echo $(sekaid status 2>&1 | jsonParse "" 2>/dev/null || echo -n "")
}

# e.g. showBlockHeight -> 123
function showBlockHeight() {
    SH_LATEST_BLOCK_HEIGHT=$(showStatus | jsonParse "SyncInfo.latest_block_height" 2>/dev/null || echo -n "")
    ($(isNaturalNumber "$SH_LATEST_BLOCK_HEIGHT")) && echo $SH_LATEST_BLOCK_HEIGHT || echo ""
}

# awaitBlocks <number-of-blocks> <timeout-seconds>
# e.g. awaitBlocks 5
function awaitBlocks() {
    BLOCKS=$1
    (! $(isNaturalNumber $BLOCKS)) && echoErr "ERROR: Number of blocks to await was NOT defined" && return 1
    SH_START_BLOCK=""
    while : ; do
        SH_NEW_BLOCK=$(showBlockHeight)
        (! $(isNaturalNumber $SH_NEW_BLOCK)) && sleep 1 && continue
        [ -z "$SH_START_BLOCK" ] && SH_START_BLOCK=$SH_NEW_BLOCK
        SH_DELTA=$(($SH_NEW_BLOCK - $SH_START_BLOCK))
        [ $SH_DELTA -gt $BLOCKS ] && break
        sleep 1
    done
}

# e.g. showCatchingUp -> false
function showCatchingUp() {
    SH_CATCHING_UP=$(showStatus | jsonParse "SyncInfo.catching_up" 2>/dev/null || echo -n "")
    ($(isBoolean "$SH_CATCHING_UP")) && echo "${SH_CATCHING_UP,,}" || echo ""
}

# activateValidator <account> <timeout-seconds>
# e.g. activateValidator validator 180
function activateValidator() {
    ACCOUNT=$1
    TIMEOUT=$2
    (! $(isNaturalNumber $TIMEOUT)) && TIMEOUT=180
    ($(isNullOrEmpty $ACCOUNT)) && echoInfo "INFO: Account name was not defined " && return 1
    sekaid tx customslashing activate --from "$ACCOUNT" --chain-id=$NETWORK_NAME --keyring-backend=test --home=$SEKAID_HOME --fees 1000ukex --yes --broadcast-mode=async --log_format=json | txAwait $TIMEOUT
}

# pauseValidator <account> <timeout-seconds>
# e.g. pauseValidator validator 180
function pauseValidator() {
    ACCOUNT=$1
    TIMEOUT=$2
    (! $(isNaturalNumber $TIMEOUT)) && TIMEOUT=180
    ($(isNullOrEmpty $ACCOUNT)) && echoInfo "INFO: Account name was not defined " && return 1
    sekaid tx customslashing pause --from "$ACCOUNT" --chain-id=$NETWORK_NAME --keyring-backend=test --home=$SEKAID_HOME --fees 100ukex --yes --broadcast-mode=async --log_format=json | txAwait $TIMEOUT
}

# unpauseValidator <account> <timeout-seconds>
# e.g. unpauseValidator validator 180
function unpauseValidator() {
    ACCOUNT=$1
    TIMEOUT=$2
    (! $(isNaturalNumber $TIMEOUT)) && TIMEOUT=180
    ($(isNullOrEmpty $ACCOUNT)) && echoInfo "INFO: Account name was not defined " && return 1
    sekaid tx customslashing unpause --from "$ACCOUNT" --chain-id=$NETWORK_NAME --keyring-backend=test --home=$SEKAID_HOME --fees 100ukex --yes --broadcast-mode=async --log_format=json | txAwait $TIMEOUT
}
