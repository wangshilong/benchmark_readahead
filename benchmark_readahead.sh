#!/bin/bash

TEST_OUTPUT_FILE="/var/log/test_results"
LUSTRE_MNT="/mnt/lustre/test_dir"
TEST_FILE="$LUSTRE_MNT/test_file"
IOR=""

function error()
{
	echo "$1"
	exit 1
}

function check_depedency()
{
	which iozone >&/dev/null || error "iozone needed"
	which git >& /dev/null || error "git needed"
	which tar >& /dev/null || error "tar needed"
}
check_depedency

#Setstripe befor testing...
#We need disable read/write cache on OSS side too..
function prepare_test()
{
	mkdir -p $LUSTRE_MNT
	lfs setstripe -c -1 $LUSTRE_MNT || error "failed to setstripe"
}
prepare_test

MemTotal=$(cat /proc/meminfo | grep MemTotal: | awk  '{print $2}')
FileSize=$(($MemTotal + 1024 * 1024 - 1)) #KB
FileSize=$(($FileSize >> 20)) #GB
FileSize=$(($FileSize * 2)) #double memory size
[ $FileSize -lt 256 ] && FileSize=256

echo "XXXXX Start test `date` XXXXX" | tee -a $TEST_OUTPUT_FILE
rec_size_array=(1k 4k 32k 512k 1m 4m 16m)
i_array=(1 2 3 5 8)
#initial write data, ignore this results
COMMAND="iozone -w -c -t1 -s $FileSize"G" -r $record_size -F $TEST_FILE"
$COMMAND -i0 >& /dev/null
# Start normal buffer size testing, only one thread testing
for record_size in ${rec_size_array[@]}
do
	echo "$COMMAND" | tee -a $TEST_OUTPUT_FILE
	for i in ${i_array[@]}
	do
		#drop memory firstly
		echo 3 > /proc/sys/vm/drop_caches
		$COMMAND -i$i | grep Children | tee -a $TEST_OUTPUT_FILE
	done
done
rm -f $TEST_FILE

#start MMAP test for 4K
COMMAND="iozone -B -w -c -t1 -s $FileSize"G" -r 4k -F $TEST_FILE"
echo "$COMMAND" | tee -a $TEST_OUTPUT_FILE
#initial write data, ignore this results
$COMMAND -i0 >& /dev/null
for i in ${i_array[@]}
do
	#drop memory firstly
	echo 3 > /proc/sys/vm/drop_caches
	$COMMAND -i$i | grep Children | tee -a $TEST_OUTPUT_FILE
done
rm -f $TEST_FILE

pushd $LUSTRE_MNT
	git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
	#reset to specific commit
	git reset --hard ccda4af0f4b92f7b4c308d3acc262f4a7e3affad
	#rm .git objects which is optimized...
	rm linux/.git -rf
	echo "Tar Linux Repo time" | tee -a $TEST_OUTPUT_FILE
	time tar -czf linux.tar.gz linux | tee -a $TEST_OUTPUT_FILE
popd

#how many threads we could use
NR_THREAD=$(cat /proc/cpuinfo  | grep processor -c)
#finially generate a mix workload..
TEST_FILES=""
for i in `seq 1 $NR_THREAD`
do
	TEST_FILES="$TEST_FILES $TEST_FILE$i"
done
COMMAND="iozone -w -c -t $NR_THREAD -s $FileSize"G" -r 1m -F $TEST_FILES"
echo "$COMMAND" | tee -a $TEST_OUTPUT_FILE
#initial write data, ignore this results
$COMMAND -i0 >& /dev/null
for i in ${i_array[@]}
do
	#drop memory firstly
	echo 3 > /proc/sys/vm/drop_caches
	$COMMAND -i$i | grep Children | tee -a $TEST_OUTPUT_FILE
done
rm -f $TEST_FILES

#$IOR -w -k -t 1m -b $FileSize"g" -e -F -vv -o $TEST_FILE
#$IOR -r -k -E -t 1m -b 256g -e -F -vv -o $TEST_FILE
echo "----- Finish test `date` -----" | tee -a $TEST_OUTPUT_FILE


