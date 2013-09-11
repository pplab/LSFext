#!/bin/sh
#kill none-lsfjob 
#please run on nodes as root
#written by qymeng@ustc.edu.cn
#modified by hmli@ustc.edu.cn

#exit 0
LC_ALL=C
HOSTNAME=`hostname -s`
LSF_BJOBS_CMD=$(find /opt/lsf -name bjobs 2> /dev/null)
#LOG_D=="/opt/lsf/killlog/`date +%Y-%m-%d`"
#LOGFILE="$LOG_D/${HOSTNAME}-clean.log"
ERRORFILE="/opt/lsf/addons/log/${HOSTNAME}-clean.err"
. /opt/lsf/conf/profile.lsf

#if [ $HOSTNAME = "node48" -o $HOSTNAME = "node49" ]; then
#	NF=0
#else
#	NF=1
#fi
#MAXLOAD=`bhosts $HOSTNAME| awk '{if($1~"node") print $4*100}'`
MAXLOAD=`bhosts $HOSTNAME|sed 1d|awk '{print $4*100}'`
#echo $MAXLOAD
cd /opt/lsf/addons
if [ ! -x $LSF_BJOBS_CMD ]; then
	echo "command $LSF_BJOBS_CMD not found!" >>$ERRORFILE
	exit 1
fi

while true
do
	LOG_D="/opt/lsf/killlog/`date +%Y-%m-%d`"
	LOGFILE="$LOG_D/${HOSTNAME}-clean.log"
	echo $LOGFILE
	if [ ! -e $LOG_D ]
	then
		mkdir -p $LOG_D
	fi

	#wait lsf batchd 
	ps aux | grep "sbatchd" | grep -v grep > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		sleep 60
		continue
	fi
	#get localhost lsf user
	LSFUSER=`$LSF_BJOBS_CMD -w -u all -m $HOSTNAME 2>/dev/null|sed 1d|awk '{print $2}'|uniq`
#	LSFUSER=`$LSF_BJOBS_CMD -w -u all -m $HOSTNAME 2>/dev/null|grep -v FROM_HOST|awk '{print $2}'|uniq`

	#get lsfuser's pid to ALLOWPIDS
	for USER in $LSFUSER
	do
		if [ $USER = "root" ];then
			continue
		fi
		#kill threads over lsf load BEGIN
		#LSFLOAD=`$LSF_BJOBS_CMD -w -u $USER -m $HOSTNAME 2>/dev/null|sed 1d| awk -v HOSTNAME=$HOSTNAME -f lsfload.awk`
		#LSFLOAD=`$LSF_BJOBS_CMD -w -u $USER -m $HOSTNAME 2>/dev/null|grep -v FROM_HOST| awk -v HOSTNAME=$HOSTNAME -f lsfload.awk`
		#LSF_temp=`$LSF_BJOBS_CMD -w -u $USER -m $HOSTNAME 2>/dev/null|grep -v FROM_HOST``
		#LSF_temp=$($LSF_BJOBS_CMD -w -u $USER -m $HOSTNAME 2>/dev/null|awk '{if($1 != "JOBID") print $0 " "}')
		LSF_temp=$($LSF_BJOBS_CMD -w -u $USER -m $HOSTNAME 2>/dev/null|sed 1d|awk '{print $0 " "}')
		#LSFLOAD=`echo -e $LSF_temp | awk -v HOSTNAME=$HOSTNAME 'BEGIN{ LOAD=0 } { split($6,NODES,":"); for(i in NODES) { split(NODES[i],n,"*"); if(n[1] == HOSTNAME) { LOAD++ }else if(n[2] == HOSTNAME){ LOAD+=n[1] } } } END{ print LOAD*101+50 }'`
		#LSFLOAD=`$LSF_BJOBS_CMD -w -u $USER -m $HOSTNAME 2>/dev/null|awk '{if($1 != "JOBID") print $0 "\n"}' | awk -v HOSTNAME=$HOSTNAME 'BEGIN{ LOAD=0 } { split($6,NODES,":"); for(i in NODES) { split(NODES[i],n,"*"); if(n[1] == HOSTNAME) { LOAD++ }else if(n[2] == HOSTNAME){ LOAD+=n[1] } } } END{ print LOAD*101+50 }'`
#		LSFLOAD=`$LSF_BJOBS_CMD -w -u $USER -m $HOSTNAME 2>/dev/null|awk '{if($1 != "JOBID") print $0 "\n"}' | awk -v HOSTNAME=$HOSTNAME 'BEGIN{ LOAD=0 } { split($6,NODES,":"); for(i in NODES) { split(NODES[i],n,"*"); if(n[1] == HOSTNAME) { LOAD++ }else if(n[2] == HOSTNAME){ LOAD+=n[1] } } } END{ print LOAD*101+50 }'`
		
		# get the current user's total load of the jobs on the node
		LSFLOAD=`$LSF_BJOBS_CMD -w -u $USER -m $HOSTNAME 2>/dev/null|sed 1d| \
		        awk -v HOSTNAME=$HOSTNAME 'BEGIN{ LOAD=0 } 
				                            {
												split($6,NODES,":"); 
												for(i in NODES) 
												{ 
													split(NODES[i],n,"*"); 
													if(n[1] == HOSTNAME) 
													{
														LOAD+=n[2] 
													}
													else if(n[2] == HOSTNAME)
													{
														LOAD+=n[1] 
													} 
												} 
											} 
											END{ print LOAD*101+50 }'`
	#	if [ $NF = 1 ]; then #8 cores nodes
			if [ $LSFLOAD -gt $MAXLOAD ];then
				LSFLOAD=$((MAXLOAD * 10))
			#echo $LSFLOAD
			fi
	#	else #node48 and node49
	#		if [ $LSFLOAD -gt 3240 ];then
	#			LSFLOAD=80000
	#		fi
	#	fi
		LSF_JOBID=${LSF_temp%% *}  # ??
		
		# get the actually load and all the PIDs of the user
		PSLOAD=`ps -o "%p %u %C" -U $USER 2>/dev/null|sed 1d| awk 'BEGIN{ LOAD=0 ; PS="" } { LOAD=LOAD+$3; PS=PS" "$1 } END{ print PS": "int(LOAD) }'`
		PS=${PSLOAD%:*}  #??
		PSLOAD=${PSLOAD#*:}  #??
		if [ $LSFLOAD -lt $PSLOAD ]; then
			KILLTIME=`date +%F" "%T`
			echo "OverLoad: <$KILLTIME> <$USER> <$HOSTNAME>: $PSLOAD(Real_Load*100%) > $LSFLOAD(LSF_Num_Nodes*100+50), killed:" >>$LOGFILE
			echo "LSF_JOBID: $LSF_JOBID killed:" >>$LOGFILE
			ps -o "%p %C %c" -U $USER >>$LOGFILE
			echo "MAXLOAD" $MAXLOAD >>$LOGFILE
			echo "LSFLOAD" $LSFLOAD >>$LOGFILE
			bjobs -l $LSF_JOBID >>$LOGFILE
			bkill -r $LSF_JOBID
			sleep 60
			kill -9 $PS
		fi
		#kill threads over lsf load END

		for PLINE in $PS
		do
			if echo $ALLOWPIDS |grep "$PLINE:" >/dev/null 2>&1; then
				:
			 else
				ALLOWPIDS=$PLINE:$ALLOWPIDS
			 fi
		done
	done

	#kill none lsf jobs
	
	#get all pids running by users in the control groups
	for LINE in `cat /opt/lsf/addons/control_groups`
	do
		GROUPPID=$GROUPPID" "`ps -G $LINE|sed 1d|awk '{print $1}'`
	done
	
	# check if the running processes all are in the jobs list
	for PLINE in $GROUPPID
	do
		if ps -o "%u %U" -p $PLINE|sed 1d|egrep "root|hmli|lsfadmin" >/dev/null 2>&1; then
			:
		else
			if echo $ALLOWPIDS |grep "$PLINE:" >/dev/null 2>&1; then
			  :
			else
				KILLTIME=`date +%F" "%T`
			  	ps -o "NoLSF: <$KILLTIME> <$HOSTNAME>: KILL PID=%p USER=%U CMD=%c" -p $PLINE|sed 1d >>$LOGFILE
				kill -9 $PLINE >>$LOGFILE 2>/dev/null
			  #	ps -o "<$HOSTNAME> <$KILLTIME> KILL PID=%p USER=%U CMD=%c" -p $PLINE|sed 1d
			fi
		fi
	done

	unset GROUPPID
	unset ALLOWPIDS

	#sleep for next check
	sleep 300
done

