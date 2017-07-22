#!/bin/bash
# solr检查/修复脚本
# 注意：本脚本只适用于集群状态下，2备份的solr

function log() {
	echo "`now` - $1" >> /var/log/dblog/solrTool.log
}

function echoAndLog() {
	echo "$1"
	log "$1"
}

function logAndExe() {
	$1
	echoAndLog "$1"
}

function now() {
	date +"%Y-%m-%d %H:%M:%S"
}

# 获取所有Core名称
function getCores() {
	ls -l /index | grep -v solr.xml | awk '{print $9}' | awk -F '_' '{print $1}' | sort -u
}

# 在集群所有机器上运行命令
function remote(){
	for i in `cat /bigdata/salut/components/hadoop/etc/hadoop/slaves`;do
		ssh $i $1
	done
}

# 同remote(),不过输出结果中会包含IP地址
function remoteWithIp(){
	for i in `cat /bigdata/salut/components/hadoop/etc/hadoop/slaves`;do
		ssh $i $1 | awk '{print "'"$i"'""    "$0}'
	done
}

# 上传Solr配置文件
function uploadConf() {
	for core in `getCores`;do
		len=${#core};
		conf=${core::len-2};
		cmd="sh /bigdata/salut/components/solr/server/scripts/cloud-scripts/zkcli.sh -zkhost localhost -cmd upconfig -confdir /bigdata/salut/conf/solr/$conf -confname $core"
		echo $cmd
		$cmd
	done
}

# 清除Zookeeper上的Solr节点
function clearSolrMeta() {
	echo 'rmr /configs'           | zkCli.sh
	echo 'rmr /overseer'          | zkCli.sh
	echo 'rmr /overseer_elect'    | zkCli.sh
	echo 'rmr /live_nodes'        | zkCli.sh
	echo 'rmr /collections'       | zkCli.sh
	echo 'rmr /clusterstate.json' | zkCli.sh
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
	for i in `replicaCheck | grep out-sync`;do
		diff=`echo $i | 'awk {print $7}'`
		ip1=`echo $i | 'awk {print $1}'`
		r1=`echo $i | 'awk {print $3}'`
		ip1=`echo $i | 'awk {print $4}'`
		r2=`echo $i | 'awk {print $6}'`
		if (("$diff">"0"));then
			logAndExe "ssh $ip2 \"mv $r2/data $r2/data_`now`\""
			logAndExe "scp -r $ip1:$r1/data $ip2:$r2"
		else
			logAndExe "ssh $ip1 \"mv $r1/data $r1/data_`now`\""
			logAndExe "scp -r $ip2:$r2/data $ip1:$r1"
		fi
	done
}

# 检查每个Collections状态是否正常，正常返回0，异常返回1
function healthCheck() {
	echoAndLog "Solr healthcheck..."
	for core in `getCores`;do
		healthy=`/bigdata/salut/components/solr/bin/solr healthcheck -c $core -z localhost | grep status | head -1 | grep healthy`
		if [ ! "$healthy" ];then
			echoAndLog "$core: unhealthy"
			echoAndLog "Finish Checking,solr is unhealthy"
			return 1
		else
			echoAndLog "$core: healthy"
		fi
	done
	echoAndLog "Finish Checking, solr is healthy"
	return 0
}

# 通过删除zk节点的方式修复solr
function repair() {
	echoAndLog "start to repair..."
	remote 'dbserver.sh stop_server daemon'
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
	mv /bigdata/salut/components/zookeeper/data/version-2 /tmp/version-2_`now`
	remote 'dbserver.sh start_server zookeeper'
	uploadConf
	dbserver.sh start
	sh /bigdata/salut/conf/salut/kafka/kafkaCreate.sh
	echoAndLog 'Force repair finish'
}

# 检查collection状态，如果不正常就执行修复
function repairIfNeed() {
	healthCheck
	if [ "$?" != "0" ];then
		repair
	else
		echoAndLog "No need to repair"
	fi
}

function printUsage() {
	echo ""
	echo "Usage: $0 [OPTION]"
	echo "Options:"
	echo "	-healthCheck      solr health check"
	echo "	-replicaCheck     compare size between replicas"
	echo "	-repairIfNeed     do repair if solr is corrupt"
	echo "	-repair           repair solr by clearing solr mata from zookeeper"
	echo "	-forceRepair      repair solr by deleting zookeeper data (VERSION-2) directly"
	echo "	-repairIfNeed     do repair if solr is corrupt"
	echo "	-syncReplica      copy biggest replica to another"
}

if [ "`ps -ef | grep $0 | grep -v $$ | grep -v grep`" ];then
	echoAndLog "Already exists a instance of $0, exit"
	exit 1
fi
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
elif [ "$cmd" == "-replicaSync" ];then
	replicaSync	
else
	printUsage
fi
