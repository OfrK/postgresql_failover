#!/bin/bash
# reassign-stdout.sh

CONFDIR=$(dirname $(readlink -f $0))
MASTER_HOST=$1
FALLEN_NODE_ID=$2
FAILED_NODE_FROM_REPMGR_ID=$3

#params
source $CONFDIR/failover.conf

SSH_USER_PCP=$(echo $MAIN_USER'@')$(echo $PGPOOL_DELEGATE_IP)    #логин и адрес для ssh, выполняет команду на pgpool (pcp)
PCP_CONNECT=' -h '$PGPOOL_DELEGATE_IP' -U '$PGPOOL_USER' -p '$PGPOOL_PORT_PCP' -w -n '$FALLEN_NODE_ID #pcp соединение с мастером pgpool

#params_end

echo "-------------failover-------------" >> $SCRIPT_ERROR_LOG
date >> $SCRIPT_ERROR_LOG

#проверка статуса сервиса
check_SERVICE_status () {
RUN=$(systemctl status $SERVICE -l | grep 'Active' | cut -d "(" -f 2 | cut -d ")" -f 1)
}

#обработчик ошибок с выходом
ERROR_exit () {
S=$(grep "$1" $SCRIPT_ERROR_LOG )
if [ -n "$ERROR" ]
then
        echo "FAILOVER ERROR: $ERROR"
        date >> $SCRIPT_ERROR_LOG
        echo  $ERROR >> $SCRIPT_ERROR_LOG
        cat $SCRIPT_ERROR_LOG >> $SCRIPT_LOG
        rm -rf $SCRIPT_ERROR_LOG
        exit
fi
}

# останавливает на старом мастере постгрес и делает копию с нового мастер на старый
standby_clone () {
SCRIPT_COUNT_REPEAT_COMMAND0=$SCRIPT_COUNT_REPEAT_COMMAND
SERVICE=$POSTGRESQL_SERVICE
while check_SERVICE_status
do
echo "FAILOVER NOTICE: tries-$SCRIPT_COUNT_REPEAT_COMMAND0 node is copying a data from new master node" >> $SCRIPT_ERROR_LOG
        if [ -n "$RUN"  ]
        then
                if [ a"$RUN" == a"running" ]
                then
                        echo "FAILOVER NOTICE: service $SERVICE is running, SERVICE will be stoping"
                        $SCRIPT_SYSTEMCTL stop $SERVICE
                fi

                if [ a"$RUN" == a"dead" ]
                then
                        echo "FAILOVER NOTICE: $MAIN_USER'@'$MASTER_HOST $REPMGR -f $REPMGR_CONF primary unregister --node-id=$FAILED_NODE_FROM_REPMGR_ID"
                        ssh $MAIN_USER'@'$MASTER_HOST $REPMGR -f $REPMGR_CONF primary unregister --node-id=$FAILED_NODE_FROM_REPMGR_ID
                        echo "FAILOVER NOTICE: service $SERVICE is stoping, run standby clone"
                        echo "FAILOVER DETAIL: $REPMGR -f $REPMGR_CONF  -h $MASTER_HOST -d $REPMGR_DB -U $REPMGR_USER  standby clone -F"
                        $REPMGR -f $REPMGR_CONF -h $MASTER_HOST -d $REPMGR_DB -U $REPMGR_USER  standby clone -F  2>> $SCRIPT_ERROR_LOG
                        ERROR_exit 'ERROR'
                        echo "FAILOVER NOTICE: complete, node is replica a new master node"
                        break
                fi

                if [ a"$RUN" == a"Result: exit-code" ]
                then
                        echo "FAILOVER NOTICE: service $SERVICE is failed , run standby clone"
                        echo "FAILOVER DETAIL: $REPMGR -f $REPMGR_CONF --force --wait-sync  -h $MASTER_HOST -d $REPMGR_DB -U $REPMGR_USER --verbose  standby clone"
                        $REPMGR -f $REPMGR_CONF --force --wait-sync  -h $MASTER_HOST -d $REPMGR_DB -U $REPMGR_USER --verbose  standby clone  2>> $SCRIPT_ERROR_LOG
                        ERROR_exit 'ERROR'
                        echo "FAILOVER NOTICE: complete, node is replica a new master node"
                        break
                fi

        fi

                ((SCRIPT_COUNT_REPEAT_COMMAND0--))

        if [ SCRIPT_COUNT_REPEAT_COMMAND0 = 0 ];
            then
                echo "FAILOVER ERROR: SCRIPT_TIMEOUT_COMMANDout repmgr standby clone node "
                exit 1
            fi

         sleep $SCRIPT_TIMEOUT_COMMAND

done

}

#регистрация старого мастера как новый слейв в repmgr
standby_register () {
SCRIPT_COUNT_REPEAT_COMMAND0=$SCRIPT_COUNT_REPEAT_COMMAND
SERVICE=$POSTGRESQL_SERVICE
while check_SERVICE_status
do
echo "FAILOVER NOTICE: tries-$SCRIPT_COUNT_REPEAT_COMMAND0 node is registering in repmgr" >> $SCRIPT_ERROR_LOG
        if [ -n "$RUN"  ]
        then
                if [ a"$RUN" == a"running" ]
                then
                        echo "FAILOVER NOTICE: service $SERVICE is running"
                        $REPMGR -f $REPMGR_CONF --force --wait-sync  -h $MASTER_HOST -d $REPMGR_DB -U $REPMGR_USER --verbose standby register 2>> $SCRIPT_ERROR_LOG
                        ERROR_exit 'ERROR'
                        echo "FAILOVER NOTICE: complete, node is register in repmgr"
                        break
                fi

                if [ a"$RUN" == a"dead" ]
                then
                        echo "FAILOVER NOTICE: service $SERVICE is stoping"
                        echo "FAILOVER DEBUG: systemctl start $SERVICE"
                        $SCRIPT_SYSTEMCTL start $SERVICE

                fi

                if [ a"$RUN" == a"Result: exit-code" ]
                then
                        echo "FAILOVER NOTICE: service $SERVICE is failed"
                        $SCRIPT_SYSTEMCTL start $SERVICE
                fi
        fi

                ((SCRIPT_COUNT_REPEAT_COMMAND0--))

        if [ SCRIPT_COUNT_REPEAT_COMMAND0 = 0 ];
            then
                echo "FAILOVER ERROR: SCRIPT_TIMEOUT_COMMANDout repmgr standby clone node "
                exit 1
            fi

         sleep $SCRIPT_TIMEOUT_COMMAND

done
}

#поднятие этой ноды в pgpool
attach_node () {
SCRIPT_COUNT_REPEAT_COMMAND0=$SCRIPT_COUNT_REPEAT_COMMAND
SERVICE=$REPMGR_SERVICE
while check_SERVICE_status
do
echo "FAILOVER NOTICE: tries-$SCRIPT_COUNT_REPEAT_COMMAND0 node is registering in pgpool" >> $SCRIPT_ERROR_LOG
        if [ -n "$RUN"  ]
        then
                if [ a"$RUN" == a"running" ]
                then
                        echo "FAILOVER NOTICE: service $SERVICE is running"
                        ssh $SSH_USER_PCP $PGPOOL_PCP_ATTACH_NODE $PCP_CONNECT 2>> $SCRIPT_ERROR_LOG
                        ERROR_exit 'ERROR'
                        echo "FAILOVER NOTICE: complete, node is register in pgpool"
                        break
                fi

                if [ a"$RUN" == a"dead" ]
                then
                        echo "FAILOVER NOTICE: service $SERVICE is stoping"
                        $SCRIPT_SYSTEMCTL start $SERVICE

                fi

                if [ a"$RUN" == a"Result: exit-code" ]
                then
                        echo "FAILOVER NOTICE: service $SERVICE is failed"
                        $SCRIPT_SYSTEMCTL start $SERVICE

                fi

        fi

                ((SCRIPT_COUNT_REPEAT_COMMAND0--))

        if [ SCRIPT_COUNT_REPEAT_COMMAND0 = 0 ];
            then
                echo "FAILOVER ERROR: SCRIPT_TIMEOUT_COMMANDout PGPOOL_PCP_ATTACH_NODE "
                exit 1
            fi

         sleep $SCRIPT_TIMEOUT_COMMAND

done
}

standby_clone
standby_register
attach_node

cat $SCRIPT_ERROR_LOG >> $SCRIPT_LOG
date > $SCRIPT_ERROR_LOG

echo "FAILOVER NOTICE: complete, node up" >> $SCRIPT_LOG

echo "-------------failover END-------------" >> $SCRIPT_ERROR_LOG

exit 0