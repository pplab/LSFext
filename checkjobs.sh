#!/bin/bash
# This script is used to check all processes of the users in control_groups on compute nodes,
# and report the processes which are not started by job manager
usage() {
    echo "  checkjobs.sh:  check jobs and processes running on the system               "
    echo "          NOTE:  only check the compute nodes whose hostname start with node  "
    echo "                                                                              "
    echo "  usage: checkjobs.sh -G <control groups>                                     "
    echo "                      -s <sensitivity>                                        "
    echo "                      -h                                                      "
    echo "      -G :    The user group lists file under control                         "
    echo "              default: control_groups                                         "
    echo "      -s :    The sensitibity when determine whether a host is overload       "
    echo "              The sensitibity's range: [0 1].                                 "
    echo "              0: the actually system load can be twice the times of the       "
    echo "                 number of running jobs                                       "
    echo "              1: the actually system load can only below the number of        "
    echo "                 running jobs                                                 "
    echo "              NOTE: Most of the time, 0.8~0.9 is a good choice. Do NOT        "
    echo "                    use 1 unless you are aware of what you're doing.          "
    echo "              default: 0.9                                                    "
    echo "      -h :    Show help                                                       "
    exit 1
}

while getopts "G:s:h" Options
do
    case ${Options} in
        G  ) CONTROLGROUPS=$OPTARG;;
        s  ) SENSITIVITY=$OPTARG;;
        h  ) usage; exit;;
        *  ) echo "Unimplemented option chosen.";uasge;exit;;
    esac
done

[ -z $CONTROLGROUPS ] && CONTROLGROUPS=control_groups

[ -z $SENSITIVITY ] && SENSITIVITY=0.9  

LSF_BIN=$(echo $PATH|sed 's/\:/\n/g'|grep lsf|grep bin$|head -n 1)
[ -z LSF_BIN ] && LSF_BIN=$(dirname $(find  /opt/lsf/ -name bjobs 2>/dev/null|head -n 1))
WORK_DIR=/tmp/checkjobs.$$
[ -e $WORK_DIR ] && rm -rf $WORKDIR
mkdir $WORK_DIR

DIE(){
    echo "$1"
    rm -rf $WORK_DIR
    exit 1
}

# check nodes loads and jobs
$LSF_BIN/lsload -w -I r15s|grep ^node|sed 's/node//'|sort -k1g|awk '{print "node"$1,0$3}' > $WORK_DIR/nodes_load     # collect the actual load
# the 0 before $3 is useful when $3 is an empty string instead of a number
$LSF_BIN/bhosts|grep ^node|sed 's/node//'|sort -k1g|awk '{print "node"$1,$4,$5,$6}' > $WORK_DIR/nodes_jobs      # collect the number of maximum jobs, allocated jobs, and running jobs
paste $WORK_DIR/nodes_jobs $WORK_DIR/nodes_load |awk -v s=$SENSITIVITY '\
                             $1!=$5{printf "ERROR! the hostname of nodes_jobs and nodes_load mismatch in line "NR": ";print $0;next}
                             $6/(2-s)>$3 {print $0;}' > $WORK_DIR/warning_nodes       # get the nodes where the actual load is larger than the number of running jobs.

# if something wrong, do not continue
[ -z $(grep ERROR $WORK_DIR/warning_nodes) ] || DIE "something error when running script, please check log file: $WORK_DIR/warning_nodes"

# wait 30 second in case of the lag of the job manager's information
# sleep 30

# check wanging_nodes again
echo 'TIME                           HOST    %CPU USER     PID   PPID  COMMAND'; 

# if nothing error, exit
[ $(wc -l < $WORK_DIR/warning_nodes) -eq 0 ] && DIE

for iNode in $(cat $WORK_DIR/warning_nodes|awk '{print $1}')
do
    [ -e $WORK_DIR/PROC.$iNode ] && rm $WORK_DIR/PROC.$iNode

    # collect all running processes of control_group
    for iGroup in $(cat $CONTROLGROUPS)
    do 
        ssh $iNode ps -F -G $iGroup 2>/dev/null|sed 1d >> $WORK_DIR/PROC.$iNode 
    done

    # check these processes
    Pid=$(cat $WORK_DIR/PROC.$iNode |awk '$4>20{print $2}')  
    for iPid in $Pid
    do
        FOUND=0
        PPid=$(ssh $iNode ps o ppid --pid $iPid 2>/dev/null | sed 1d) 
        [ -z $PPid ] && break   # the process has already die 

        while [ $PPid -gt 0 ] # search the ppid of the processes until 0
        do          
            COMM_PPid=$(ssh $iNode ps o comm,ppid --pid $PPid 2>/dev/null |sed 1d)
            
            # Check the process's name
            PPid=$(echo "$COMM_PPid" |awk '{
                                    MATCH=0
                                    if($1=="sbatchd") MATCH=1;
                                    if($1~/^[0-9]+\.[0-9]+$/) MATCH=1;
                                    
                                    # add other LSF process patterns here
                                    if(MATCH == 1)
                                        print -1;
                                    else 
                                        print $2;
                                  }')
            [ $PPid -eq -1 ] && (FOUND=1;break)
        done
        
        if [ $FOUND -eq 0 ]  # the process is not started by LSF
        then
            printf "`date`   $iNode   "
            ssh $iNode ps o pcpu,user,pid,ppid,comm --pid $iPid |sed 1d
            #ssh $iNode kill -9 $iPid  #kill the illegal job
        fi
    done
done

[ -e $WORK_DIR ] && rm -rf $WORK_DIR
