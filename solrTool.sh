#!/bin/bash
# solr检查/修复脚本
# 注意：本脚本只适用于集群状态下，2备份的solr

minRepairInterval=1200 # 两次repair至少间隔时间
logfile=/var/log/dblog/solrTool.log

function log() {
	echo "`now` - $1" >> $logfile
}

function echoAndLog() {
	echo "$1"
	log "$1"
}

function report() {
    curl -d "$1" "http://21.60.100.83:8888" --connect-timeout 2
}

function now() {
        date +"%Y-%m-%d_%H:%M:%S"
}

# 获取所有Core名称
function getCores() {
	ls -l /index | grep -v solr.xml | awk '{print $9}' | awk -F '_' '{print $1}' | sort -u
}

# 在集群所有机器上运行命令
function remote(){
	for i in `cat /bigdata/salut/components/hadoop/etc/hadoop/slaves`;do
        log "ssh $i $1"
		ssh $i $1
	done
}

# 同remote(),不过输出结果中会包含IP地址
function remoteWithIp(){
	for i in `cat /bigdata/salut/components/hadoop/etc/hadoop/slaves`;do
        log "ssh $i $1"
		ssh $i $1 | awk '{print "'"$i"'""    "$0}'
	done
}

# 上传Solr配置文件
function uploadConf() {
	for core in `getCores`;do
		len=${#core};
		conf=${core::len-2};
		cmd="sh /bigdata/salut/components/solr/server/scripts/cloud-scripts/zkcli.sh -zkhost localhost -cmd upconfig -confdir /bigdata/salut/conf/solr/$conf -confname $core"
		echoAndLog "$cmd"
		$cmd
	done
}

# 清除Zookeeper上的Solr节点
function clearSolrMeta() {
    true > /tmp/zkCmdTmp
    echo 'rmr /configs'>>/tmp/zkCmdTmp
    echo 'rmr /overseer'>>/tmp/zkCmdTmp
    echo 'rmr /overseer_elect'>>/tmp/zkCmdTmp
    echo 'rmr /live_nodes'>>/tmp/zkCmdTmp
    echo 'rmr /collections'>>/tmp/zkCmdTmp
    echo 'rmr /clusterstate.json'>>/tmp/zkCmdTmp
    zkCli.sh < /tmp/zkCmdTmp
}

# 检查replica大小，如果相差大于500M，会在最后一列标记 out-sync
#
# replica1_IP  replica1_size  replica1_name                           replica2_IP replica2_size  replica2_name                      replica_size_diff  
# 21.60.1.91   812000         /index/FaceImage01_shard10_replica1      21.60.1.89  0	        /index/FaceImage01_shard10_replica2 812000                 out-sync
function replicaCheck() {
	remoteWithIp 'du /index --max-depth=1 | grep .*replica.*' | sort -k 3 -d | sed 'N;s/\n/\t/' | awk '{diff=sqrt(($2-$5)*($2-$5));str=$0"\t"$2-$5;if(diff>512000)str=str"  out-sync";print str}'
}

# 重新同步体积相差过大的Replica，可能会要求输入密码，如果没有配无密钥的话
function replicaSync() {
	remote 'dbserver.sh stop_server daemon'
    remote 'dbserver.sh stop_server solr'
    IFSBAK=$IFS
    IFS=$'\n'
	for i in `replicaCheck | grep out-sync`;do
		diff=`echo $i | awk '{print $7}'`
		ip1=`echo $i | awk '{print $1}'`
		r1=`echo $i | awk '{print $3}'`
		ip2=`echo $i | awk '{print $4}'`
		r2=`echo $i | awk '{print $6}'`
		if [ "$diff" -gt 0 ];then
                        ssh $ip2 "mkdir -p /home$r2"
			ssh $ip2 "mv $r2/data /home$r2/data_`now`"
			echoAndLog "ssh $ip2 \"mv $r2/data /home$r2/data_`now`\""
			scp -r $ip1:$r1/data $ip2:$r2
			echoAndLog "scp -r $ip1:$r1/data $ip2:$r2"
		else
                        ssh $ip1 "mkdir -p /home$r1"
		        ssh $ip1 "mv $r1/data /home$r1/data_`now`"
                        echoAndLog "ssh $ip1 \"mv $r1/data /home$r1/data_`now`\""
			scp -r $ip2:$r2/data $ip1:$r1
                        echoAndLog "scp -r $ip2:$r2/data $ip1:$r1"
		fi
	done
    IFS=$IFSBAK
    remote 'dbserver.sh start_server solr'
    remote 'dbserver.sh start_server daemon'
    echoAndLog 'ReplicaSync finish'
}

# 检查每个Collections状态是否正常，正常返回0，异常返回1
function healthCheck() {
	echoAndLog "Solr healthcheck..."
	down=`/bigdata/salut/components/solr/server/scripts/cloud-scripts/zkcli.sh -zkhost localhost -cmd get /clusterstate.json |  grep '"leader":"true"' -B 1 | grep '"state":"down"'`
	recoveryfailed=`/bigdata/salut/components/solr/server/scripts/cloud-scripts/zkcli.sh -zkhost localhost -cmd get /clusterstate.json |  grep '"leader":"true"' -B 1 | grep '"state":"recovery_failed"'`
	if [ "$down" ] || [ "$recoveryfailed" ];then
		echoAndLog "Finish Checking,solr is unhealthy"
		return 1
	else
		echoAndLog "Finish Checking, solr is healthy"
		return 0
	fi
}

# 通过删除zk节点的方式修复solr
function repair() {
	echoAndLog "start to repair..."
	remote 'dbserver.sh stop_server daemon'
	dbserver.sh stop_server RealtimeStreaming
	remote 'dbserver.sh stop_server solr'
	remote 'dbserver.sh start_server zookeeper'
	clearSolrMeta
	uploadConf
	remote 'dbserver.sh start_server solr'
	remote 'dbserver.sh start_server daemon'
	echoAndLog 'Repair finish'
}

# 通过删除zk数据文件的方式修复solr
function forceRepair() {
	echoAndLog "start to force repair..."
	dbserver.sh stop
        remote "mv /bigdata/salut/components/zookeeper/data/version-2 /tmp/version-2_`now`"	
        remote 'dbserver.sh start_server zookeeper'
	uploadConf
	dbserver.sh start
        echo "PLEASE WAIT 60s"
        sleep 60
	sh /bigdata/salut/conf/salut/kafka/kafkaCreate.sh
	echoAndLog 'Force repair finish'
}

# 检查collection状态，如果不正常就执行修复
function repairIfNeed() {
	healthCheck
	if [ "$?" != "0" ];then
        report "Solr异常，已执行自动修复，请及时检查数据接入是否正常"
		repair
	else
		echoAndLog "No need to repair"
	fi
}

# solr启动后一段时间之内不会再次检查solr，以确保有足够的时间让solr shard上线
function secureRepair() {
    # 当主机solr进程未启动则认为是人为关掉的，跳过检查
    solr=`jps -lm | grep 8983 | awk '{print $1}'`
    if [ ! "$solr" ];then
            echoAndLog "solr is not running, skip"
            return 0
    fi
    # solr启动minRepairInterval秒内不检查状态
    uptime=`jcmd $solr VM.uptime | tail -1 | awk '{print $1}' | awk -F . '{print $1}'`
    if [ "$uptime" -lt "$minRepairInterval" ];then
            echoAndLog "solr uptime ${uptime}s must greater than ${minRepairInterval}s, skip"
            return 0
    fi
    repairIfNeed
}

# 轮询检查solr状态，如有异常执行修复
function poll() {
    duration=$1
    # 杀掉其他正在运行的实例
    myname=`basename $0`
    otherInstance=`ps -ef | grep $myname | grep -v grep | grep -v $$ | awk '{print $2}' | xargs`
    if [ "$otherInstance" ];then
        kill -9 $otherInstance
        echo "Find other running instance, kill it"
    fi
    {
      while true;do
        secureRepair
        sleep $duration
      done
    } > /dev/null 2>&1 &  
    echo "Started in backgound, check solr every ${duration}s, log to $logfile"
}

function printUsage() {
	echo ""
	echo "Usage: $0 [OPTION]"
	echo "Options:"
	echo "	-healthCheck      solr health check"
	echo "	-replicaCheck     compare size between replicas"
	echo "	-repair           repair solr by clearing solr mata from zookeeper"
	echo "	-forceRepair      repair solr by deleting zookeeper data (VERSION-2) directly"
	echo "	-repairIfNeed     do repair if solr is corrupt"
	echo "	-secureRepair     similar with '-repairIfNeed', but avoid doing repair too close"
	echo "	-replicaSync      copy biggest replica to another"
    echo "	-poll [duration]  check and repair frequently in second"
}

cmd=$1
if [ ! "$cmd" ];then
	printUsage
elif [ "$cmd" == "-replicaCheck" ];then
	replicaCheck
elif [ "$cmd" == "-healthCheck" ];then
	healthCheck
elif [ "$cmd" == "-repair" ];then
	repair
elif [ "$cmd" == "-forceRepair" ];then
	forceRepair
elif [ "$cmd" == "-repairIfNeed" ];then
	repairIfNeed
elif [ "$cmd" == "-secureRepair" ];then
	secureRepair
elif [ "$cmd" == "-replicaSync" ];then
	replicaSync
elif [ "$cmd" == "-poll" ] && [ "$2" ];then
	poll $2
else
	printUsage
fi
