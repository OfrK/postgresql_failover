#!/bin/sh
# reassign-stdout.sh

CONFDIR=$(dirname $(readlink -f $0))
source $CONFDIR/failover.conf


#params
SSH_USER_PCP=$(echo $MAIN_USER'@')$(echo $PGPOOL_DELEGATE_IP)   #логин и адрес для ssh, выполняет команду на pgpool (pcp)
PCP_CONNECT=' -h '$PGPOOL_DELEGATE_IP' -U '$PGPOOL_USER' -p '$PGPOOL_PORT_PCP' -w ' #pcp соединение с мастером pgpool

NODE_NAME=$( $REPMGR  -f  $REPMGR_CONF   node status | grep Node | cut -d '"' -f 2)     #имя текущей ноды где выполняется скрипт
NODES_COUNT_PGPOOL=$(ssh $SSH_USER_PCP $PGPOOL_PCP_NODE_COUNT $PCP_CONNECT)         #количество нод в pgpool
#params_end

#статус ноды в repmgr
node_check_role () {

NODE_ROLE_REPMGR=$( $REPMGR -f $REPMGR_CONF node status | grep Role: | cut -d ' ' -f 2)    #получаем роль ноды ( мастер или слейв )

}

# присоединение упавшей ноды в pgpool
node_attach () {

count=0
while [ $count -lt $SCRIPT_COUNT_REPEAT_COMMAND ]
do
        down=$(ssh $SSH_USER_PCP $PGPOOL_PCP_NODE_INFO $PCP_CONNECT $1 | grep down)
        standby=$(ssh $SSH_USER_PCP $PGPOOL_PCP_NODE_INFO $PCP_CONNECT $1 | grep standby)
        primary=$(ssh $SSH_USER_PCP $PGPOOL_PCP_NODE_INFO $PCP_CONNECT $1 | grep primary)

        if [ ${#down} -gt 0 ];
                then
                echo "PROMOTE NOTICE: current node in pgpool : down"
                ssh $SSH_USER_PCP $PGPOOL_PCP_ATTACH_NODE $PCP_CONNECT -n $1
                fi

        if [ ${#standby} -gt 0 ];
                then
                echo "PROMOTE NOTICE: current node in pgpool : standby"
                ssh $SSH_USER_PCP $PGPOOL_PCP_PROMOTE_NODE $PCP_CONNECT -n $1
                standby=$(ssh $SSH_USER_PCP $PGPOOL_PCP_NODE_INFO $PCP_CONNECT $1 | grep standby)
                if [ ${#standby} -gt 0 ];
                    then
                        echo "PROMOTE DETAIL: ssh $SSH_USER_PCP $PGPOOL_PCP_ATTACH_NODE $PCP_CONNECT -n $1"
                        ssh $SSH_USER_PCP $PGPOOL_PCP_ATTACH_NODE $PCP_CONNECT -n $1
                    fi
                fi

        if [ ${#primary} -gt 0 ];
                then
                echo "PROMOTE NOTICE: current node in pgpool : primary"
                exit 0
                fi

        sleep $SCRIPT_TIMEOUT_COMMAND
        ((count++))
done

}


#продвигаем ноду до мастера через repmgr
count=0
while node_check_role
do
        #если текущая нода мастер в repmgr
        if [ a"$NODE_ROLE_REPMGR" = a"primary" ];
                then
                #ищем мастера repmgr в нодах pgpool
                for ((i=0;i<=NODES_COUNT_PGPOOL-1;i++));
                        do
                                NODE_PGPOOL=$(ssh $SSH_USER_PCP $PGPOOL_PCP_NODE_INFO $PCP_CONNECT $i | cut -d ' ' -f 1 )
                                if [ a"$NODE_NAME" = a"$NODE_PGPOOL" ];
                                        then
                                                echo "PROMOTE DETAIL: $(ssh  $SSH_USER_PCP $PGPOOL_PCP_NODE_INFO $PCP_CONNECT $i)"
                                                node_attach $i
                                                break
                                        fi
                        done
                fi
        echo "PROMOTE DETAIL: $REPMGR -f $REPMGR_CONF $REPMGR_STANDBY_PROMOTE"
        $REPMGR -f $REPMGR_CONF $REPMGR_STANDBY_PROMOTE ;#команда продвижения ноды до мастера
        echo "PROMOTE NOTICE: node role is $NODE_ROLE_REPMGR"

        if [ $SCRIPT_COUNT_REPEAT_COMMAND = $count ];
            then
                echo ""
                echo "PROMOTE ERROR: repmgr and pgpool can't promote node $NODE_NAME "
                exit 1
            fi

        sleep $SCRIPT_TIMEOUT_COMMAND
        ((count++))
done

exit 1