#!/bin/bash
set +e && source "/etc/profile" &>/dev/null && set -e
source $KIRA_MANAGER/utils.sh
# quick edit: FILE="$KIRA_MANAGER/kira/kira-networking.sh" && rm $FILE && nano $FILE && chmod 555 $FILE

# ports have 3 diffrent configuration states, public, disabled & custom
WHITESPACE="                                                     "
PORT_CFG_DIR="$KIRA_CONFIGS/ports/$PORT"
mkdir -p "$PORT_CFG_DIR"
touch "$PUBLIC_PEERS" "$PUBLIC_SEEDS"

while : ; do
    set +e && source "/etc/profile" &>/dev/null && set -e
    PORTS_EXPOSURE=$(globGet PORTS_EXPOSURE)
    printf "\033c"
    ALLOWED_OPTIONS="x"
echo -e "\e[37;1m--------------------------------------------------"
           echo "|         KIRA NETWORKING MANAGER $KIRA_SETUP_VER       |"
           [ "${PORTS_EXPOSURE,,}" == "enabled" ] && \
           echo -e "|\e[0m\e[33;1m   ALL PORTS ARE OPEN TO THE PUBLIC NETWORKS    \e[37;1m|"
           [ "${PORTS_EXPOSURE,,}" == "custom" ] && \
           echo -e "|\e[0m\e[32;1m      ALL PORTS USE CUSTOM CONFIGURATION        \e[37;1m|"
           [ "${PORTS_EXPOSURE,,}" == "disabled" ] && \
           echo -e "|\e[0m\e[31;1m        ACCESS TO ALL PORTS IS DISABLED         \e[37;1m|"
           echo "|-------------- $(date '+%d/%m/%Y %H:%M:%S') -------------| [config]"
    i=-1
    LAST_SNAP=""
    PORTS_CNT=0
    PORTS=$(globGet EXPOSED_PORTS)
    PORTS=($PORTS) || PORTS=""
    for p in "${PORTS[@]}" ; do
        NAME=""
        
        [ "$p" == "$KIRA_INTERX_PORT" ] && NAME="INTERX Service" && TYPE="API" && PORTS_CNT=$((PORTS_CNT + 1))

        [ "$p" == "$KIRA_SEED_P2P_PORT" ] && NAME="Seed Node" && TYPE="P2P" && PORTS_CNT=$((PORTS_CNT + 1))
        [ "$p" == "$KIRA_SENTRY_P2P_PORT" ] && NAME="Public Sentry" && TYPE="P2P" && PORTS_CNT=$((PORTS_CNT + 1))
        [ "$p" == "$KIRA_VALIDATOR_P2P_PORT" ] && NAME="Validator Node" && TYPE="P2P" && PORTS_CNT=$((PORTS_CNT + 1))

        [ "$p" == "$KIRA_SEED_RPC_PORT" ] && NAME="Seed Node" && TYPE="RPC" && PORTS_CNT=$((PORTS_CNT + 1))
        [ "$p" == "$KIRA_SENTRY_RPC_PORT" ] && NAME="Public Sentry" && TYPE="RPC" && PORTS_CNT=$((PORTS_CNT + 1))
        [ "$p" == "$KIRA_VALIDATOR_RPC_PORT" ] && NAME="Validator Node" && TYPE="RPC" && PORTS_CNT=$((PORTS_CNT + 1))

        [ "$p" == "$KIRA_SEED_PROMETHEUS_PORT" ] && NAME="Seed Node Monitor" && TYPE="HTTP" && PORTS_CNT=$((PORTS_CNT + 1))
        [ "$p" == "$KIRA_SENTRY_PROMETHEUS_PORT" ] && NAME="Pub. Sentry Monitor" && TYPE="HTTP" && PORTS_CNT=$((PORTS_CNT + 1))
        [ "$p" == "$KIRA_VALIDATOR_PROMETHEUS_PORT" ] && NAME="Val. Node Monitor" && TYPE="HTTP" && PORTS_CNT=$((PORTS_CNT + 1))

        i=$((i + 1))
        [ -z "$NAME" ] && continue

        PORT_EXPOSURE=$(globGet "PORT_EXPOSURE_${p}")
        [ -z "$PORT_EXPOSURE" ] && PORT_EXPOSURE="enabled"
        P_TMP="${p}${WHITESPACE}"
        NAME_TMP="${NAME}${WHITESPACE}"
        TYPE_TMP="${TYPE}${WHITESPACE}"
        INDEX="[$i]${WHITESPACE}"
        echo "| ${INDEX:0:5}| ${TYPE_TMP:0:4} PORT ${P_TMP:0:5} - ${NAME_TMP:0:21} : $PORT_EXPOSURE" && ALLOWED_OPTIONS="${ALLOWED_OPTIONS}${i}"
    done
       echo "|------------------------------------------------|"
       [ "${PORTS_EXPOSURE,,}" != "enabled" ] && \
       echo "| [E] | Force ENABLE All Ports                   |" && ALLOWED_OPTIONS="${ALLOWED_OPTIONS}e"
       [ "${PORTS_EXPOSURE,,}" != "custom" ] && \
       echo "| [C] | Force CUSTOM Ports Configuration         |" && ALLOWED_OPTIONS="${ALLOWED_OPTIONS}c"
       [ "${PORTS_EXPOSURE,,}" != "disabled" ] && \
       echo "| [D] | Force DISABLE All Ports                  |" && ALLOWED_OPTIONS="${ALLOWED_OPTIONS}d"
       IFACE_TMP="(${IFACE})${WHITESPACE:0:10}|"
       echo "| [I] | Change Network INTERFACE $IFACE_TMP"        && ALLOWED_OPTIONS="${ALLOWED_OPTIONS}i"
       echo "|------------------------------------------------|"
       echo "| [S] | Edit/Show SEED Nodes List                |" && ALLOWED_OPTIONS="${ALLOWED_OPTIONS}s"
       echo "| [P] | Edit/Show Persistent PEERS List          |" && ALLOWED_OPTIONS="${ALLOWED_OPTIONS}p"
       echo "| [F] | Reload FIREWALL Settings                 |" && ALLOWED_OPTIONS="${ALLOWED_OPTIONS}f"
       echo "| [R] | RELOAD Networking                        |" && ALLOWED_OPTIONS="${ALLOWED_OPTIONS}r"
    echo -e "| [X] | Exit ___________________________________ |\e[0m"

    if [[ $PORTS_CNT -le 9 ]] ; then
        OPTION="" && read -s -n 1 -t 30 OPTION || OPTION=""
    else
        OPTION="" && read -n 2 -t 30 OPTION || OPTION=""
    fi

    [ -z "$OPTION" ] && continue
    [[ "${ALLOWED_OPTIONS,,}" != *"$OPTION"* ]] && continue

    if [ "${OPTION,,}" != "x" ] && [ "${OPTION,,}" != "p" ] && [ "${OPTION,,}" != "s" ] && [[ $OPTION != ?(-)+([0-9]) ]] ; then
        echoNErr "Press [Y]es to confirm option (${OPTION^^}) or [N]o to cancel: " && pressToContinue y n && ACCEPT=($(globGet OPTION))
        [ "${ACCEPT,,}" == "n" ] && echo -e "\nWARINIG: Operation was cancelled\n" && sleep 1 && continue
        echo -n ""
    fi

    i=-1
    for p in "${PORTS[@]}" ; do
        i=$((i + 1))
        if [ "$OPTION" == "$i" ]; then
            echoInfo "INFO: Starting port manager ($p)..."
            $KIRA_MANAGER/kira/port-manager.sh "$p"
            OPTION=""
        fi
    done
    
    if [ "${OPTION,,}" == "d" ]; then
        echoInfo "INFO: Disabling all ports..."
        globSet PORTS_EXPOSURE "disabled"
    elif [ "${OPTION,,}" == "e" ]; then
        echoInfo "INFO: Enabling all ports..."
        globSet PORTS_EXPOSURE "enabled"
    elif [ "${OPTION,,}" == "c" ]; then
        echoInfo "INFO: Enabling custom ports configuration..."
        globSet PORTS_EXPOSURE "custom"
    elif [ "${OPTION,,}" == "i" ]; then
        echoInfo "INFO: Starting network interface selection menu..."
        IFACE_OLD="$IFACE"
        $KIRA_MANAGER/menu/interface-select.sh
        set +e && source "/etc/profile" &>/dev/null && set -e
        if [ "$IFACE_OLD" != "$IFACE" ] ; then
            echoInfo "INFO: Reinitalizing firewall..."
            $KIRA_MANAGER/networking.sh
        else
            echoInfo "INFO: Network interface was not changed"
        fi
    elif [ "${OPTION,,}" == "s" ] || [ "${OPTION,,}" == "p" ] ; then
        [ "${OPTION,,}" == "s" ] && TYPE="seeds" && TARGET="Seed Nodes"
        [ "${OPTION,,}" == "p" ] && TYPE="peers" && TARGET="Persistent Peers"

        [ "${OPTION,,}" == "s" ] && FILE=$PUBLIC_SEEDS
        [ "${OPTION,,}" == "p" ] && FILE=$PUBLIC_PEERS
        EXPOSURE="public"
        [ "${INFRA_MODE,,}" == "validator" ] && CONTAINER="validator"
        [ "${INFRA_MODE,,}" == "sentry" ] && CONTAINER="sentry"
        [ "${INFRA_MODE,,}" == "seed" ] && CONTAINER="seed"

        echoInfo "INFO: Starting $TYPE editor..."
        $KIRA_MANAGER/kira/seeds-edit.sh "$FILE" "$EXPOSURE $TARGET"

        COMMON_PATH="$DOCKER_COMMON/$CONTAINER" && mkdir -p "$COMMON_PATH"
        echoInfo "INFO: Copying $TYPE configuration to the $CONTAINER container common directory..."
        cp -a -v -f "$FILE" "$COMMON_PATH/$TYPE"

        echoInfo "INFO: To apply changes you MUST restart your $EXPOSURE facing $CONTAINER container"
        echoNErr "Choose to [R]estart $CONTAINER container or [C]ontinue: " && pressToContinue r c && SELECT=($(globGet OPTION))
        [ "${SELECT,,}" == "c" ] && continue

        echoInfo "INFO: Re-starting $CONTAINER container..."
        $KIRA_MANAGER/kira/container-pkill.sh "$CONTAINER" "true" "restart"
    elif [ "${OPTION,,}" == "f" ]; then
        echoInfo "INFO: Reinitalizing firewall..."
        $KIRA_MANAGER/networking.sh
    elif [ "${OPTION,,}" == "r" ]; then
        echoInfo "INFO: Restarting network interfaces..."
        # $KIRA_MANAGER/scripts/restart-networks.sh
        $KIRA_MANAGER/scripts/update-ifaces.sh
    elif [ "${OPTION,,}" == "x" ]; then
        echoInfo "INFO: Stopping kira networking manager..."
        break
    fi

    if [ "${OPTION,,}" == "e" ] || [ "${OPTION,,}" == "c" ] || [ "${OPTION,,}" == "d" ] ; then
        echoInfo "INFO: Current '$FIREWALL_ZONE' zone rules"
        firewall-cmd --list-ports
        firewall-cmd --get-active-zones
        firewall-cmd --zone=$FIREWALL_ZONE --list-all || echo "INFO: Failed to display current firewall rules"
        echoInfo "INFO: To apply changes to above rules you will have to restart firewall"
        echoNErr "Choose to [R]estart FIREWALL or [C]ontinue: " && pressToContinue r c && SELECT=($(globGet OPTION)) 
        [ "${SELECT,,}" == "c" ] && continue
        echoInfo "INFO: Reinitalizing firewall..."
        $KIRA_MANAGER/networking.sh
    fi

    [ ! -z $OPTION ] && echoNErr "Option ($OPTION) was executed, press any key to continue..." && pressToContinue
done

