# Kafka performance testing tools

This is a kafka performance testing tool that helps you get useful performance metrics output to the frontend, reducing the difficulty of operations and maintenance.

##  Requirements

Tested on a host running Centos 7 System
- pre-required:
> Preparing a fully available kafka cluster


## Basic Usage
```
[root@localhost benchmark]# bash kafka-benchmark-tools.sh -h
 Usage: kafka-benchmark-tools.sh [-h] [-v] [-m] [-l] [-t] [-z] [-k] [-n] [-p] [-u] [-w] [-a]

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
```

### Example

```shell
[root@localhost benchmark]# bash  kafka-benchmark-tools.sh  -l ZingJDK -k 192.168.10.218,192.168.10.219,192.168.10.220 -z 192.168.10.122 -t 1
[2023-09-15 15:45:42] 👶 Starting up...
[2023-09-15 15:45:42] 📁 Created temporary working directory /tmp/tmp.aAWuCrRtbo
[2023-09-15 15:45:42] 👍 Simulate kafka's current benchmarking the 1 time
[2023-09-15 15:45:53] 👍 topics add successfully
[2023-09-15 15:45:54] 👍 ZingJDK environment, simulate 10000000 message writing to NOSCRAM-ZingJDK-TOPIC-P20, acks=1, message size 100
[2023-09-15 15:46:20] 👍 Execute script /home/kafka/kafka_2.11-2.4.0/bin/kafka-producer-perf-test.sh successfully
[2023-09-15 15:46:20] 👍 Fetch kafka metrics value Success
[2023-09-15 15:46:51] 👍 ZingJDK environment, simulate 10000000 message writing to NOSCRAM-ZingJDK-TOPIC-P20, acks=1, message size 500
[2023-09-15 15:47:39] 👍 Execute script /home/kafka/kafka_2.11-2.4.0/bin/kafka-producer-perf-test.sh successfully
[2023-09-15 15:47:40] 👍 Fetch kafka metrics value Success
[2023-09-15 15:48:11] 👍 ZingJDK environment, simulate 10000000 message writing to NOSCRAM-ZingJDK-TOPIC-P20, acks=1, message size 1024
[2023-09-15 15:49:28] 👍 Execute script /home/kafka/kafka_2.11-2.4.0/bin/kafka-producer-perf-test.sh successfully
[2023-09-15 15:49:28] 👍 Fetch kafka metrics value Success
[2023-09-15 15:49:58] 👍 Showing data in the current directory /root/benchmark/NOSCRAM_ZingJDK_producer_acks-1-2023-09-15_15:45:42
[2023-09-15 15:49:58] 👍 Merge data into fulldata.out file
[2023-09-15 15:49:58] 👍 Filter data into data.out file
[2023-09-15 15:49:58] 👍 Outputs data for the current catalog file /root/benchmark/NOSCRAM_ZingJDK_producer_acks-1-2023-09-15_15:45:42/data.out
速率(records/sec)  速率(MB/sec)  平均延迟  99%延迟  最大延迟
467814.37          44.61         409.80    1271.00  1797.00
218698.74          104.28        280.29    936.00   1212.00
135580.35          132.40        220.27    1174.00  1577.00
[2023-09-15 15:49:58] 👍 the move data to the current directory
[2023-09-15 15:49:58] ✅ Completed.
```

## Thanks
This scripting tool references [Kafka-install](https://www.conduktor.io/kafka/how-to-install-apache-kafka-on-linux/), [kafka-doc](https://kafka.apache.org/08/ documentation.html), etc., excellent articles that provided me with good ideas.