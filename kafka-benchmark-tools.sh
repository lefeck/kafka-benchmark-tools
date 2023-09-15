#!/bin/bash
set -Eeuo pipefail

function cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
	if [ -n "${tmpdir+x}" ]; then
		rm -rf "$tmpdir"
		log "🚽 Deleted temporary working directory $tmpdir"
	fi
}

#trap cleanup SIGINT SIGTERM ERR EXIT

# Gets the current location of the script
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
# check whether the date command-line tools exists
[[ ! -x "$(sudo command -v date)" ]] && echo "💥 date command not found." && exit 1

function log() {
	sudo echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] ${1-}" >&2
}

function die() {
	local msg=$1
	local code=${2-1} # Bash parameter expansion - default exit status 1. See https://wiki.bash-hackers.org/syntax/pe#use_a_default_value
	log "$msg"
	exit "$code"
}

# sent record size
recordsize_string="100 500 1024"
recordsize_array=(${recordsize_string// / })

# usage of the command line tool
usage() {
	cat <<EOF
 Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-m] [-l] [-t] [-z] [-k] [-n] [-p] [-u] [-w] [-a]

 💁 This is a scripting tool to test the performance of kafka.

 Available options:

 -h, --help                Print this help and exit
 -v, --verbose             Print script debug info
 -m, --mode                Set authentication mode for kafka, there are 2 modes: SCRAM, NOSCRAM, the default is NOSCRAM
 -l, --label               Set different types of java environment, there are two types: ZingJDK, OracleJDK, the default is OracleJDK
 -t, --times               For testing kafka performance, set the number of tests, the default is 1
 -k, --kafka-node-ips      Specify the ip address of kakfa node
 -z, --zookeeper-node-ips  Specify the ip address of zookeeper node
 -n, --num-records         Simulate the size of the data to be written, the default is 100000
 -p, --partition-id        Divide each topic into one or more partitions, the default is 20
 -u, --throughput          Set kafka throughput, the default is unlimited, value is -1
 -w, --wait                The time to wait after executing a round of kafka pressure testing script, default is 30s.
 -a, --acks                When the producer sends data to the leader, you can set the reliability level of the data through
                           the acks parameter,which has three values: 1, 0, and -1. The default is 1. For more details, please see here: https://kafka.apache.org/08/documentation.html
EOF
	exit
}

function parse_params() {
	# default values of variables set from params
	mode=${mode:-NOSCRAM}
	label=${label:-OracleJDK}
	kafka_node_ips=''
	zookeeper_node_ips=''
	times=${times:-1}
	num_records=${num_records:-10000000}
	partition_id=${partition_id:-20}
	throughput=${throughput:--1}
	wait=${wait:-30}
	acks=${acks:-1}
	# parse argument of the command
	getopt_cmd=$(getopt -o m:l:k:z:t:n:p:u:w:a:hv --long mode:,label:,kafka_node_ips:,zookeeper_node_ips:,times:,num_records:,partition_id:,throughput:,wait:,acks:,help,verbose -n $(basename $0) -- "$@")
	if [ $? -ne 0 ]; then
		exit 1
	fi
	eval set -- "$getopt_cmd"
	while [ -n "$1" ]; do
		case "$1" in
		-m | --mode)
			mode="${2-}"
			shift
			;;
		-l | --label)
			label="${2-}"
			shift
			;;
		-k | --kafka-node-ips)
			kafka_node_ips="${2-}"
			shift
			;;
		-z | --zookeeper-node-ips)
			zookeeper_node_ips="${2-}"
			shift
			;;
		-t | --times)
			times="${2-}"
			shift
			;;
		-n | --num-records)
			num_records="${2-}"
			shift
			;;
		-p | --partition-id)
			partition_id="${2-}"
			shift
			;;
		-u | --throughput)
			throughput="${2-}"
			shift
			;;
		-w | --wait)
			wait="${2-}"
			shift
			;;
		-a | --acks)
			acks="${2-}"
			shift
			;;
		-h | --help)
			usage
			;;
		-v | --verbose)
			set -x
			;;
		--)
			shift
			break
			;;
		?*)
			die "Unknown option: $1"
			;;
		esac
		shift
	done
	log "👶 Starting up..."
}

parse_params "$@"

function backup() {
	# The default create a a random directory in /tmp
	tmpdir=$(mktemp -d)

	if [[ ! "$tmpdir" || ! -d "$tmpdir" ]]; then
		die "💥 Could not create temporary working directory."
	else
		log "📁 Created temporary working directory $tmpdir"
	fi

	dirs_name=$(find . -maxdepth 1 -mindepth 1 -type d)
	dirs_name_array=(${dirs_name})
	if [ -n "${dirs_name}" ]; then
	for i in ${dirs_name[@]};do
       mv "${i}" $tmpdir
	done
	fi
}


function check_params() {
  # check options parameters
	parameter_values=(${times} ${num_records} ${partition_id} ${wait})

	for value in ${parameter_values[@]}; do
		echo "$value" | [ -n "$(sed -n '/^[0-9][0-9]*$/p')" ] || die "The $value is an illegal value. You have to specify a number."
	done

	if [ ${label} == "OracleJDK" -o ${label} == "ZingJDK" ]; then
		topic_name=$mode-$label-TOPIC-P${partition_id}
	else
		die "The error ${label} that You can choose one of OracleJDK or ZingJDK"
	fi

	# check kafka node ip address
	kafka_node_ips_array=($(echo ${kafka_node_ips} | sed 's/,/ /g'))
	new_kafka_node_sockets_array=()
	if [ -n "${kafka_node_ips}" ]; then
		for ((i = 0; i < ${#kafka_node_ips_array[@]}; i++)); do
			check_IPAddr ${kafka_node_ips_array[$i]}
			if [ ${mode} == "NOSCRAM" ]; then
				socket=${kafka_node_ips_array[$i]}:9092
			else
				socket=${kafka_node_ips_array[$i]}:9093
			fi
			new_kafka_node_sockets_array[i]=${socket}
		done
		kafka_node_sockets=$(echo "${new_kafka_node_sockets_array[@]}" | sed 's/ /,/g')
		kafka_scram_api="${kafka_node_sockets}"
		kafka_noscram_api="${kafka_node_sockets}"
	else
		die "The kafka_node_ips is no exist, you have to specify"
	fi

  # check zookeeper node ip address
	zookeeper_node_ips_array=($(echo ${zookeeper_node_ips} | sed 's/,/ /g'))
	new_zookeeper_node_sockets_array=()
	if [ -n "${zookeeper_node_ips}" ]; then
		for ((i = 0; i < ${#zookeeper_node_ips_array[@]}; i++)); do
			check_IPAddr ${zookeeper_node_ips_array[$i]}
			socket=${zookeeper_node_ips_array[$i]}:2181
			new_zookeeper_node_sockets_array[i]=${socket}
		done
		zookeeper_node_sockets=$(echo "${new_zookeeper_node_sockets_array[@]}" | sed 's/ /,/g')
	else
		die "The zookeeper_node_ip is no exist, you have to specify"
	fi
}

# ip address checkout
function check_IPAddr() {
	echo $1 | grep "^[0-9]\{1,3\}\.\([0-9]\{1,3\}\.\)\{2\}[0-9]\{1,3\}$" >/dev/null
	if [ $? -ne 0 ]; then
		die "👿 Illegal ip address $1"
	fi
	ipaddr=$1
	a=$(echo $ipaddr | awk -F . '{print $1}')
	b=$(echo $ipaddr | awk -F . '{print $2}')
	c=$(echo $ipaddr | awk -F . '{print $3}')
	d=$(echo $ipaddr | awk -F . '{print $4}')
	for num in $a $b $c $d; do
		if [ $num -gt 255 ] || [ $num -lt 0 ]; then
			die "👿 Illegal ip address $1"
		fi
	done
}

function create_topic() {
	time=$(date "+%Y-%m-%d_%H:%M:%S")
	sub_directory="${script_dir}/${mode}_${label}_producer_acks-${acks}-${time}"
	sudo mkdir -p ${sub_directory}
	# the location  of   the script file kafka topic
	local kafka_topics_script_name=$(sudo find / -type f -iname kafka-topics.sh)
	if [ -f ${kafka_topics_script_name} ]; then
		topic_name_uniqe=$(${kafka_topics_script_name} --zookeeper ${zookeeper_node_sockets} --list | grep $topic_name >/dev/null && echo yes || echo no)
		# shellcheck disable=SC2070
		if [ ${topic_name_uniqe} == "yes" ]; then
			# delete topics title
			${kafka_topics_script_name} --zookeeper ${zookeeper_node_sockets} --topic $topic_name --delete >/dev/null
			log "👍 topics remove successfully"
		fi
		# new create topics title
		${kafka_topics_script_name} --zookeeper ${zookeeper_node_sockets} --topic $topic_name --partitions ${partition_id} --replication-factor 1 --create >/dev/null
		log "👍 topics add successfully"
	else
		die "👿 the ${kafka_topics_script_name} is not exist."
	fi
}

function fetch_metrics() {
	records=$(grep -r "10000000 records sent" $1 | awk -F , '{print $2}' | sed "s/ //g" | awk '{printf("%.2f",$1)}')
	mb_records=$(grep -r "10000000 records sent" $1 | awk -F , '{print $2}' | awk -F "(" '{print $2}' | sed "s/)//g" | awk -F "MB" '{print $1}' | sed "s/ //g" | awk '{printf("%.2f",$1)}')
	avg_latency=$(grep -r "10000000 records sent" $1 | awk -F , '{print $3}' | awk -F "ms" '{print $1}' | sed "s/ //g" | awk '{printf("%.2f",$1)}')
	_99_latency=$(grep -r "10000000 records sent" $1 | awk -F , '{print $7}' | awk -F "ms" '{print $1}' | sed "s/ //g" | awk '{printf("%.2f",$1)}')
	max_latency=$(grep -r "10000000 records sent" $1 | awk -F , '{print $4}' | awk -F "ms" '{print $1}' | sed "s/ //g" | awk '{printf("%.2f",$1)}')
}

function benchmark() {
	for recordsize in ${recordsize_array[@]}; do
		local kafka_producer_perf_test_script_name=$(sudo find / -type f -iname kafka-producer-perf-test.sh)
		local data_file=${sub_directory}/${mode}_${label}_producer_acks-${acks}_rs-${recordsize}.rp
		sudo touch ${data_file} && sudo chmod 777 ${data_file}
		start_time=$(date "+%Y-%m-%d_%H:%M:%S")
		echo "开始时间：$start_time" >>${data_file}
		echo "案例：${label}环境，模拟${num_records}消息写入${topic_name}，acks=$acks，消息大小$recordsize" >>${data_file}
		log "👍 ${label} environment, simulate ${num_records} message writing to ${topic_name}, acks=$acks, message size $recordsize"
		if [ -f ${kafka_producer_perf_test_script_name} ]; then
			if [[ $mode == "SCRAM" ]]; then
				echo "命令：${kafka_producer_perf_test_script_name}  --topic $topic_name --num-records $num_records --record-size $recordsize --throughput $throughput --producer-props bootstrap.servers=$kafka_scram_api acks=$acks --producer.config /home/kafka/kafka_2.11-2.4.0/config/client-sasl.properties" >>${data_file}
				echo "压测结果报告：" >>${data_file}
				${kafka_producer_perf_test_script_name} --topic $topic_name --num-records $num_records --record-size $recordsize --throughput $throughput --producer-props bootstrap.servers=$kafka_scram_api acks=$acks --producer.config /home/kafka/kafka_2.11-2.4.0/config/client-sasl.properties >>${data_file}
			else
				echo "命令：${kafka_producer_perf_test_script_name}  --topic $topic_name --num-records $num_records --record-size $recordsize --throughput $throughput --producer-props bootstrap.servers=$kafka_noscram_api acks=$acks" >>${data_file}
				echo "压测结果报告：" >>${data_file}
				${kafka_producer_perf_test_script_name} --topic $topic_name --num-records $num_records --record-size $recordsize --throughput $throughput --producer-props bootstrap.servers=$kafka_noscram_api acks=$acks >>${data_file}
				log "👍 Execute script ${kafka_producer_perf_test_script_name} successfully"
			fi
		else
			die "👿 the ${kafka_producer_perf_test_script_name} is not exist."
		fi

		end_time=$(sudo date "+%Y-%m-%d_%H:%M:%S")
		echo "结束时间：$end_time" >>${data_file}
		echo "关键指标统计：" >>${data_file}

		if [ -f ${data_file} ]; then
			fetch_metrics ${data_file}
			log "👍 Fetch kafka metrics value Success"
		else
			die "👿 the ${data_file} is not exist."
		fi

		echo "速率(records/sec) 速率(MB/sec) 平均延迟 99%延迟 最大延迟" >>${data_file}
		echo "$records $mb_records $avg_latency $_99_latency $max_latency" >>${data_file}

		sleep ${wait}
	done
}

function full_data() {
	local fulldata_name=$1/fulldata.out
	files=$(sudo find $1 -type f -iname "*.rp")
	sudo touch ${fulldata_name} && sudo chmod 777 ${fulldata_name}
	for file in ${files}; do
		echo "############################################################################" >>${fulldata_name}
		cat ${file} >>${fulldata_name}
	done
	log "👍 Merge data into fulldata.out file"
}

function filter_data() {
	local data_name=$1/data.out
	files=$(sudo find $1 -type f -iname "*.rp")
	sudo touch ${data_name} && sudo chmod 777 ${data_name}
	echo '速率(records/sec) 速率(MB/sec) 平均延迟 99%延迟 最大延迟' >${data_name}
	for file in ${files}; do
		cat ${file} | tail -1 >>${data_name}
	done
	log "👍 Filter data into data.out file"
	log "👍 Outputs data for the current catalog file ${data_name}"
	cat ${data_name} | column -t | tee ${data_name}
}

function data_summary() {
	data_dirname=$(sudo find ${script_dir} -type d -not -path "${script_dir}")
	for dir in ${data_dirname[@]}; do
		log "👍 Showing data in the current directory ${dir}"
		full_data ${dir}
		filter_data ${dir}
	done
	if [ -z "$(ls -A ${tmpdir})" ]; then
    log "👍  the ${tmpdir} directory is empty"
  else
    mv ${tmpdir}/* .
    log "👍 the move data to the current directory"
  fi
	die "✅ Completed." 0
}

function main() {
	backup
	check_params
	for ((i = 1; i <= $times; i++)); do
		log "👍 Simulate kafka's current benchmarking the ${i} time"
		create_topic
		benchmark
	done
	data_summary
}

main
