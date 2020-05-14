#!/bin/sh
# reassign-stdout.sh

CONFDIR=$(dirname $(readlink -f $0))
source $CONFDIR/failover.conf

#params
date >> $SCRIPT_LOG

SSH_USER_PCP=$(echo $MAIN_USER'@')$(echo $PGPOOL_DELEGATE_IP)   #логин и адрес для ssh, выполняет команду на pgpool (pcp)
PCP_CONNECT=' -h '$PGPOOL_DELEGATE_IP' -U '$PGPOOL_USER' -p '$PGPOOL_PORT_PCP' -w ' #pcp соединение с мастером pgpool

MASTER_HOST=$($REPMGR -f $REPMGR_CONF  node check | grep Node | cut -d '"' -f 2)
NODES_COUNT_PGPOOL=$(ssh $SSH_USER_PCP $PGPOOL_PCP_NODE_COUNT $PCP_CONNECT)         #количество нод в pgpool

#params_end

# метод возвращает нерабочие ноды в файл построчно в список
add_failed_nodes () {

echo > $SCRIPT_CLUSTER_SHOW
$REPMGR -f $REPMGR_CONF  cluster show >> $SCRIPT_CLUSTER_SHOW

echo > $SCRIPT_FAILED_NODES

cat $SCRIPT_CLUSTER_SHOW | grep '| ? unreachable |' | cut -d '|' -f 2 | xargs >> $SCRIPT_FAILED_NODES
cat $SCRIPT_CLUSTER_SHOW | grep '| - failed  |' | cut -d '|' -f 2 | xargs >> $SCRIPT_FAILED_NODES
cat $SCRIPT_CLUSTER_SHOW | grep '| ! running as primary |' | cut -d '|' -f 2 | xargs >> $SCRIPT_FAILED_NODES
cat $SCRIPT_CLUSTER_SHOW | grep '| ! running |' | cut -d '|' -f 2 | xargs >> $SCRIPT_FAILED_NODES

echo "REPAIR_NODE NOTICE: failed node list $(cat $SCRIPT_FAILED_NODES) " >> $SCRIPT_LOG

}

repair_nodes () {

for FAILED_NODE_FROM_REPMGR in `cat $SCRIPT_FAILED_NODES`;
do
        echo "$FAILED_NODE_FROM_REPMGR" #упавшая нода из repmgr
        echo "cat $SCRIPT_CLUSTER_SHOW | grep '| $FAILED_NODE_FROM_REPMGR |' | cut -d '|' -f 1"
        FAILED_NODE_FROM_REPMGR_ID=$(cat $SCRIPT_CLUSTER_SHOW | grep "| $FAILED_NODE_FROM_REPMGR |" | cut -d '|' -f 1 | xargs )
        #echo $(cat $SCRIPT_CLUSTER_SHOW | grep '| $FAILED_NODE_FROM_REPMGR |')
        echo "ID = $FAILED_NODE_FROM_REPMGR_ID"
        for ((i=0;i<=NODES_COUNT_PGPOOL-1;i++));
                        do
                                FAILED_HOST=$(ssh $SSH_USER_PCP $PGPOOL_PCP_NODE_INFO $PCP_CONNECT $i | cut -d ' ' -f 1)  #упавшая нода из pgpool

                                if [ "$FAILED_NODE_FROM_REPMGR" = "$FAILED_HOST" ]; #если имя ноды pgpool и repmgr равны
                                        then
                                                ping $FAILED_NODE_FROM_REPMGR -c 4
                                                PING=$(echo "$?")
                                                echo "REPAIR_NODE NOTICE: ping $PING"
                                                if [ $PING = 0 ];
                                                        then
                                                                #запускаем скрипт восстановления упавшей ноды
                                                                echo "REPAIR_NODE DETAIL: $MAIN_USER'@'$FAILED_NODE_FROM_REPMGR $SCRIPT_FAILOVER_SH $MASTER_HOST $i $FAILED_NODE_FROM_REPMGR_ID"
                                                                ssh $MAIN_USER'@'$FAILED_NODE_FROM_REPMGR $SCRIPT_FAILOVER_SH $MASTER_HOST $i $FAILED_NODE_FROM_REPMGR_ID 2>>$SCRIPT_LOG #передаем (виртуальный ip , имя нового мастера и id pgpool упавшей ноды) в скрипт восстановления упавшей ноды
                                                                break
                                                else    echo "REPAIR_NODE ERROR: timeout connect to $FAILED_NODE_FROM_REPMGR" >> $SCRIPT_LOG
                                                        break

                                                        fi
                                        fi
                        done
done

}

add_failed_nodes
repair_nodes

rm -rf $SCRIPT_FAILED_NODES

exit