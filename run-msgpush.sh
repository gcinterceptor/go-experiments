#!/bin/bash
# IMPORTANT: This script requires pidstats (part of sysstas package).

date
set -x

# Expected Parameters:
# Example:
# LB="3.3.3.3"
# INSTANCES="1.1.1.1 2.2.2.2"

# TODO(danielfireman): Check parameters.

# GCI on/off switcher.
if [ "$USE_GCI" == "false" ];
then
    FILE_NAME_SUFFIX="nogci"
else
    USE_GCI="true"
    FILE_NAME_SUFFIX="gci"
fi

# Output.
# TODO(danielfireman): Add OUTPUT as parameter.
OUTPUT_DIR="/tmp/2instances"

# Overall experiment configuration (these bellow thend to be more static).
echo "ROUND_START: ${ROUND_START:=1}"
echo "ROUND_END: ${ROUND_END:=1}"
echo "USE_GCI: ${USE_GCI}"
echo "EXPERIMENT_DURATION: ${EXPERIMENT_DURATION:=3m}"
echo "MSG_SIZE: ${MSG_SIZE:=10240}"
echo "THROUGHPUT: ${THROUGHPUT:=1750}"
echo "WINDOW_SIZE: ${WINDOW_SIZE:=1000}"
echo "SUFFIX: ${SUFFIX:=}"
FILE_NAME_SUFFIX="${FILE_NAME_SUFFIX}${SUFFIX}"
GODEBUG=gctrace=1


for round in `seq ${ROUND_START} ${ROUND_END}`
do
    echo ""
    echo "round ${round}: Bringing up server instances..."
    for instance in ${INSTANCES};
    do
        ssh -i ~/fireman.sururu.key ubuntu@${instance} "killall msgpush 2>/dev/null;killall pidstat 2>/dev/null; GODEBUG=${GODEBUG} nohup ./msgpush --msg_size=${MSG_SIZE} --window_size=${WINDOW_SIZE} --use_gci=${USE_GCI} >/dev/null 2>gctrace.out & nohup pidstat -C msgpush 1 | grep msgpush | sed s/,/./g |  awk '{if (\$0 ~ /[0-9]/) { print \$1\",\"\$2\",\"\$3\",\"\$4\",\"\$5\",\"\$6\",\"\$7\",\"\$8\",\"\$9; }  }'> cpu.csv 2>/dev/null &"
    done

    sleep 5
    echo "round ${round}: Done. Starting load test..."
    ssh -i ~/fireman.sururu.key ubuntu@${LB} "sudo rm /var/log/nginx/*.log;  sudo systemctl restart nginx; killall wrk 2>/dev/null; bin/wrk -t2 -c100 -d${EXPERIMENT_DURATION} -R${THROUGHPUT} --latency --timeout=15s http://localhost > ~/wrk_${FILE_NAME_SUFFIX}_${round}.out; cp /var/log/nginx/access.log ~/nginx_access_${FILE_NAME_SUFFIX}_${round}.log; cp /var/log/nginx/error.log ~/nginx_error_${FILE_NAME_SUFFIX}_${round}.log"

    echo "round ${round}: Done. Putting server instances down..."
    i=0
    for instance in ${INSTANCES};
    do
        cmd="killall msgpush; killall pidstat; mv cpu.csv cpu_${FILE_NAME_SUFFIX}_${i}_${round}.csv; mv gctrace.out gctrace_${FILE_NAME_SUFFIX}_${i}_${round}.out"
        ssh -i ~/fireman.sururu.key ubuntu@${instance} "$cmd"
        ((i++))
    done

    echo "round ${round}: Done. Copying results and cleaning up instances..."
    scp -i ~/fireman.sururu.key ubuntu@${LB}:~/\{*log,*.out\} ${OUTPUT_DIR}
    ssh -i ~/fireman.sururu.key ubuntu@${LB} "rm *.log; rm *.out"
    sed -i '1i timestamp;status;request_time;upstream_response_time' ${OUTPUT_DIR}/nginx_access_${FILE_NAME_SUFFIX}_${round}.log

    i=0
    for instance in ${INSTANCES};
    do
        scp -i ~/fireman.sururu.key ubuntu@${instance}:~/\{cpu*.csv,gctrace*.out\} ${OUTPUT_DIR}
        sed -i '1i time,ampm,uid,pid,usr,system,guest,cpu,cpuid' ${OUTPUT_DIR}/cpu_${FILE_NAME_SUFFIX}_${i}_${round}.csv
        sed -i '1i gc gcnum time perctime wallclock wallclockmetric clock cputime cputimemetric cpu mem memmetric memgoal memgoalmetric goal numprocs p isforced' ${OUTPUT_DIR}/gctrace_${FILE_NAME_SUFFIX}_${i}_${round}.out;
        ssh -i ~/fireman.sururu.key ubuntu@${instance} "rm ~/cpu*.csv ~/gctrace*.out"
        ((i++))
    done
    echo "round ${round}: Finished."
    echo ""
done
