LSF_BIN=$(dirname $(find  /opt/lsf/ -name bjobs 2>/dev/null))
LOG_DIR=~/lsf_addon/log

[ -e $LOG_DIR ] || mkdir $LOG_DIR

DIE(){
	echo "$1"
	exit 1
}

# check nodes loads and jobs
$LSF_BIN/lsload -w -I r15m|grep ^node|sed 's/node//'|sort -k1g|awk '{print "node"$1,$3}' > $LOG_DIR/nodes_load 	# collect the actual load
$LSF_BIN/bhosts|grep ^node|sed 's/node//'|sort -k1g|awk '{print "node"$1,$4,$5,$6}' > $LOG_DIR/nodes_jobs		# collect the number of maximum jobs, allocated jobs, and running jobs
$LSF_BIN/paste nodes_jobs nodes_load |awk '$1!=$5{printf "ERROR! the hostname of nodes_jobs and nodes_load mismatch in line "NR": ";print $0;next}int($6)>$3{print}' > $LOG_DIR/warning_nodes   	# get the nodes where the actual load is larger than the number of running jobs.

# if something wrong, do not continue
[ -z grep ERROR $LOG_DIR/warning_nodes ] || DIE "something error when running script, please check log file: $LOG_DIR/warning_nodes"

# if nothing error, exit
[ $(wc -l < $LOG_DIR/warning_nodes) -e 0 ] || DIE "no illegal jobs now"

# wait 30 second and check again
sleep 30

# check wanging_nodes again
for iNode in $(cat $LOG_DIR/warning_nodes|awk '{print $1}')
do
	[ -e PROC.$iNode ] && rm PROC.$iNode
	for iGroup in $(cat control_groups )
	do 
		ssh $iNode ps -F -G $iGroup 2>/dev/null|sed 1d >> PROC.$iNode # collect running processes
		Pid=$(cat PROC.$iNode |awk '$4>50{print $2}')  
		for iPid in $Pid
		do
			FOUND=0
			PPid=$(ssh $iNode ps o ppid --pid $iPid 2>/dev/null | sed 1d) 
			while [ $PPid -lt 0 ] # search the ppid of the processes until 0
			do			
				comm=$(ssh $iNode ps o comm --pid $PPid 2>/dev/null |sed 1d)
				[ $comm = "sbatchd" ] && (FOUND=1; break)  # find the LSF process
				PPid=$(ssh $iNode ps o ppid --pid $PPid 2>/dev/null | sed 1d)  # continue to find the parent process of current process
			done
			
			if [ $FOUND -eq 0 ]  # the process is not started by LSF
			then
				ssh $iNode ps o pcpu,user,pid,ppid,comm --pid $iPid >> $LOG_DIR/illegal_jobs.log
				#ssh $iNode kill -9 $iPid  #kill the illegal job
			fi
		done
	done
done