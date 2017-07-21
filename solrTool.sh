#!/bin/bash

function log() {
	echo "`date +"%Y-%m-%d %H:%M:%S"` - $1" >> /var/log/dblog/solrTool.log
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
	date +%s
}

function getCores() {
	ls -l /index | grep -v solr.xml | awk '{print $9}' | awk -F '_' '{print $1}' | sort -u
}

function remote(){
	for i in `cat /bigdata/salut/components/hadoop/etc/hadoop/slaves`;do
		ssh $i $1
	done
}

function remoteWithIp(){
	for i in `cat /bigdata/salut/components/hadoop/etc/hadoop/slaves`;do
		ssh $i $1 | awk '{print "'"$i"'""    "$0}'
	done
}

function uploadConf() {
	for core in `getCores`;do
		len=${#core};
		conf=${core::len-2};
		cmd="sh /bigdata/salut/components/solr/server/scripts/cloud-scripts/zkcli.sh -zkhost localhost -cmd upconfig -confdir /bigdata/salut/conf/solr/$conf -confname $core"
		echo $cmd
		$cmd
	done
}

function clearSolrMeta() {
	echo 'rmr /configs'           | zkCli.sh
	echo 'rmr /overseer'          | zkCli.sh
	echo 'rmr /overseer_elect'    | zkCli.sh
	echo 'rmr /live_nodes'        | zkCli.sh
	echo 'rmr /collections'       | zkCli.sh
	echo 'rmr /clusterstate.json' | zkCli.sh
}

#output format
# 1            2              3                                       4           5              6                                  7
# replica1_IP  replica1_size  replica1_name                           replica2_IP replica2_size  replica2_name                      replica_size_diff
# 21.60.1.91   40272         /index/FaceImage01_shard10_replica1      21.60.1.89  40708	        /index/FaceImage01_shard10_replica2 760
function replicaCheck() {
	remoteWithIp 'du /index --max-depth=1 | grep .*replica.*' | sort -k 3 -d | sed 'N;s/\n/\t/' | awk '{diff=sqrt(($2-$5)*($2-$5));str=$0"\t"$2-$5;if(diff>512000)str=str"  out-sync";print str}'
}

function replicaSync() {
	for i in `replicaCheck | grep 1G`;do
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

function healthCheck() {
	echoAndLog "Solr healthcheck..."
	for core in `getCores`;do
		healthy=`/bigdata/salut/components/solr/bin/solr healthcheck -c $core -z localhost | grep status | head -1 | grep healthy`
		if [ ! "$healthy" ];then
			echoAndLog "$core: unhealthy"
			echoAndLog "SFinish Checking,solr is unhealthy"
			return 1
		else
			echoAndLog "$core: healthy"
		fi
	done
	echoAndLog "Finish Checking,solr is healthy"
	return 0
}

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


function repairIfNeed() {
	last=`cat /var/log/dblog/lastRepair`
	if (("`now`"-"$last">"1800"));then
		healthCheck
		if [ "$?" != "0" ];then
			repair
			now > /var/log/dblog/lastRepair
		else
			echo "No need to repair"
		fi
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



