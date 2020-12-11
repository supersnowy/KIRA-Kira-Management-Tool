#!/bin/bash

set +e && source $ETC_PROFILE &>/dev/null && set -e

NAME=$1

LOOP_FILE="/tmp/container_manager_loop"
CONTAINER_DUPM="$KIRA_DUMP/kira/${NAME^^}.log"
mkdir -p $(dirname "$KIRA_DUMP")

exec &> >(tee -a "$CONTAINER_DUPM")

DEBUG_MODE=$2
if [ "$DEBUG_MODE" == "True" ] ; then set -x ; else set +x ; fi

while : ; do
    START_TIME="$(date -u +%s)"
    EXISTS=$($KIRA_SCRIPTS/container-exists.sh "$NAME" || echo "Error")

    if [ "$EXISTS" != "True" ] ; then
        clear
        echo "WARNING: Container $NAME no longer exists, press [X] to exit or restart your infra"
        read -n 1 -t 3 KEY || continue
         [ "${OPTION,,}" == "x" ] && exit 1
    fi

    # (docker ps --no-trunc -aqf name=$NAME) 
    ID=$(docker inspect --format="{{.Id}}" ${NAME} 2> /dev/null || echo "undefined")
    STATUS=$(docker inspect $ID | jq -r '.[0].State.Status' || echo "Error")
    PAUSED=$(docker inspect $ID | jq -r '.[0].State.Paused' || echo "Error")
    HEALTH=$(docker inspect $ID | jq -r '.[0].State.Health.Status' || echo "Error")
    RESTARTING=$(docker inspect $ID | jq -r '.[0].State.Restarting' || echo "Error")
    STARTED_AT=$(docker inspect $ID | jq -r '.[0].State.StartedAt' || echo "Error")
    IP=$(docker inspect $ID | jq -r '.[0].NetworkSettings.Networks.kiranet.IPAMConfig.IPv4Address' || echo "")
    if [ -z "$IP" ] || [ "$IP" == "null" ] ; then IP=$(docker inspect $ID | jq -r '.[0].NetworkSettings.Networks.regnet.IPAMConfig.IPv4Address' || echo "") ; fi
    
    clear
    
    echo -e "\e[36;1m-------------------------------------------------"
    echo "|        KIRA CONTAINER MANAGER v0.0.3          |"
    echo "|             $(date '+%d/%m/%Y %H:%M:%S')               |"
    echo "|-----------------------------------------------|"
    echo "| Container Name: $NAME ($(echo $ID | head -c 8))"
    echo "|     Ip Address: $IP"
    echo "|-----------------------------------------------|"
    echo "|     Status: $STATUS"
    echo "|     Paused: $PAUSED"
    echo "|     Health: $HEALTH"
    echo "| Restarting: $RESTARTING"
    echo "| Started At: $(echo $STARTED_AT | head -c 19)"
    echo "|-----------------------------------------------|"
    [ "$EXISTS" == "True" ] && 
    echo "| [I] | Try INSPECT container                   |"
    [ "$EXISTS" == "True" ] && 
    echo "| [L] | View container LOGS                     |"
    [ "$EXISTS" == "True" ] && 
    echo "| [R] | RESTART container                       |"
    [ "$STATUS" == "exited" ] && 
    echo "| [A] | START container                         |"
    [ "$STATUS" == "running" ] && 
    echo "| [S] | STOP container                          |"
    [ "$STATUS" == "running" ] && 
    echo "| [R] | RESTART container                       |"
    [ "$STATUS" == "running" ] && 
    echo "| [P] | PAUSE container                         |"
    [ "$STATUS" == "paused" ] && 
    echo "| [U] | UNPAUSE container                       |"
    [ "$EXISTS" == "True" ] && 
    echo "|-----------------------------------------------|"
    echo "| [X] | Exit | [W] | Refresh Window | [Y] Debug |"
    echo -e "-------------------------------------------------\e[0m"
    
    echo -en "Input option then press [ENTER] or [SPACE]: " && rm -f $LOOP_FILE && touch $LOOP_FILE && OPTION=""
    while : ; do
        [ -f $LOOP_FILE ] && OPTION=$(cat $LOOP_FILE || echo "")
        [ -z "$OPTION" ] && [ $(($(date -u +%s)-$START_TIME)) -ge 6 ] && break
        read -n 1 -t 3 KEY || continue
        [ ! -z "$KEY" ] && echo "${OPTION}${KEY}" > $LOOP_FILE
        [ -z "$KEY" ] && break
    done
    OPTION=$(cat $LOOP_FILE || echo "") && [ -z "$OPTION" ] && continue
    ACCEPT="" && while [ "${ACCEPT,,}" != "y" ] && [ "${ACCEPT,,}" != "n" ] ; do echo -en "\e[36;1mPress [Y]es to confirm option (${OPTION^^}) or [N]o to cancel: \e[0m\c" && read  -d'' -s -n1 ACCEPT && echo "" ; done
    [ "${ACCEPT,,}" == "n" ] && echo "\nWARINIG: Operation was cancelled\n" && continue

    if [ "${OPTION,,}" == "i" ] ; then
        docker exec -it $ID /bin/bash || docker exec -it $ID /bin/sh #; read -d'' -s -n1 -p 'Press any key to exit...' && exit
        sleep 2 && continue
    elif [ "${OPTION,,}" == "l" ] ; then
    echo "INFO: Dumping all loggs..."
        $WORKSTATION_SCRIPTS/dump-logs.sh $NAME
        break
    elif [ "${OPTION,,}" == "r" ] ; then
        echo "INFO: Restarting container..."
        $KIRA_SCRIPTS/container-restart.sh $NAME
        break
    elif [ "${OPTION,,}" == "a" ] ; then
        echo "INFO: Staring container..."
        $KIRA_SCRIPTS/container-start.sh $NAME
        break
    elif [ "${OPTION,,}" == "s" ] ; then
        echo "INFO: Stopping container..."
        $KIRA_SCRIPTS/container-stop.sh $NAME
        break
    elif [ "${OPTION,,}" == "p" ] ; then
        echo "INFO: Pausing container..."
        $KIRA_SCRIPTS/container-pause.sh $NAME
        break
    elif [ "${OPTION,,}" == "u" ] ; then
        echo "INFO: UnPausing container..."
        $KIRA_SCRIPTS/container-unpause.sh $NAME
        break
    elif [ "${OPTION,,}" == "w" ] ; then
        echo "INFO: Please wait, refreshing user interface..." && break
    elif [ "${OPTION,,}" == "y" ] ; then
        echo "INFO: Enabling debug mode..."
        DEBUG_MODE="True"
        break
    elif [ "${OPTION,,}" == "x" ] ; then
        exit 0
    fi
done

touch $LOOP_FILE && [ ! -z "$(cat $LOOP_FILE || echo '')" ] && sleep 2
source $KIRA_MANAGER/container-manager.sh "$NAME" "$DEBUG_MODE"
