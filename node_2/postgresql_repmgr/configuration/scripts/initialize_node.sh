#!/bin/bash
# reassign-stdout.sh

CONNINFO="$1"

#params
REPMGR_WITH_CONF="/usr/pgsql-11/bin/repmgr -f /etc/repmgr/11/repmgr.conf"
START_POSTGRESQL="sudo systemctl start postgresql-11"
STOP_POSTGRESQL="sudo systemctl stop postgresql-11"
START_REPMGR="sudo systemctl start repmgr11"
LOG="/var/log/repmgr/initialize_node.log"
#paramsend

date >> $LOG

if [ -z "$CONNINFO" ]
then
  echo "PRIMARY_CONNINFO=$CONNINFO" >> $LOG
  echo "exit" >> $LOG
  exit 0
elif [ a"$CONNINFO" == a"primary" ]
then
  echo "PRIMARY_CONNINFO=$CONNINFO" 2>> $LOG
  echo "this node will be PRIMARY" 2>> $LOG
  $START_POSTGRESQL 2>> $LOG&&\
  $REPMGR_WITH_CONF primary register -F 2>> $LOG&&\
  $START_REPMGR 2>> $LOG&&\
  REPMGR_WITH_CONF cluster show 2>> $LOG
  echo "complete" 2>> $LOG
  exit 0
else
  echo "PRIMARY_CONNINFO=$CONNINFO" >> $LOG
  echo "this node will be STANDBY" >> $LOG
  $STOP_POSTGRESQL 2>> $LOG&&\
  $REPMGR_WITH_CONF standby clone -d "$CONNINFO" -c -F --dry-run 2>> $LOG&&\
  $REPMGR_WITH_CONF standby clone -d "$CONNINFO" -c -F 2>> $LOG&&\
  $START_POSTGRESQL 2>> $LOG&&\
  $REPMGR_WITH_CONF standby register 2>> $LOG&&\
  $START_REPMGR 2>> $LOG&&\
  echo "complete" >> $LOG
  exit 0
fi

exit 1