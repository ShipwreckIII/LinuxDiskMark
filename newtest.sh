#!/bin/bash

# ====== DETECT POOL NAME FROM PATH ======
CURRENT_PATH=$(pwd)
POOL=$(echo "$CURRENT_PATH" | cut -d'/' -f3)

# ====== USER INPUT ======
read -p "Enter context label (e.g. data, backup, vm): " CONTEXT
read -p "Enter target directory (default: current): " TARGET_DIR
TARGET_DIR=${TARGET_DIR:-.}
read -p "Enter test file size (e.g. 1G, 500M): " SIZE
read -p "Enter runtime in seconds (e.g. 5, 10): " RUNTIME
read -p "Enter I/O depth (default: 32): " IODEPTH
IODEPTH=${IODEPTH:-32}
read -p "Enter number of jobs (default: 1): " NUMJOBS
NUMJOBS=${NUMJOBS:-1}
read -p "Include hostname in filename? (y/n): " INCLUDE_HOSTNAME
read -p "Delete test file after run? (y/n): " DELETE_FILE

# ====== FILE PATHS ======
HOSTNAME=$(hostname)
RAW_OUTPUT="raw_${POOL}_${CONTEXT}"
CSV_OUTPUT="${POOL}_${CONTEXT}"
if [[ "$INCLUDE_HOSTNAME" =~ ^[Yy]$ ]]; then
  RAW_OUTPUT="${RAW_OUTPUT}_${HOSTNAME}"
  CSV_OUTPUT="${CSV_OUTPUT}_${HOSTNAME}"
fi
RAW_OUTPUT="${RAW_OUTPUT}.txt"
CSV_OUTPUT="${CSV_OUTPUT}.csv"
TESTFILE="$TARGET_DIR/fio_testfile.tmp"

# ====== PREVIEW SUMMARY ======
echo
echo "Ready to run benchmark with the following settings:"
echo "--------------------------------------------------"
echo "POOL        : $POOL"
echo "CONTEXT     : $CONTEXT"
echo "DIR         : $TARGET_DIR"
echo "FILE SIZE   : $SIZE"
echo "RUNTIME     : $RUNTIME seconds"
echo "IO DEPTH    : $IODEPTH"
echo "NUM JOBS    : $NUMJOBS"
echo "HOSTNAME    : $HOSTNAME"
echo "TEST FILE   : $TESTFILE"
echo "OUTPUT FILE : $(realpath "$RAW_OUTPUT")"
echo

read -p "Proceed with test? (y/n): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Aborted." && exit 1

# ====== TEST MATRIX ======
declare -a tests=(
  "seq1mq8t1 randrw 1M 8 $NUMJOBS"
  "seq1mq1t1 randrw 1M 1 $NUMJOBS"
  "rnd4kq32t1 randrw 4k $IODEPTH $NUMJOBS"
  "rnd4kq1t1 randrw 4k 1 $NUMJOBS"
)

# ====== RUN TESTS ======
echo "Running benchmarks on pool [$POOL]..." > "$RAW_OUTPUT"

for test in "${tests[@]}"; do
  set -- $test
  NAME=$1
  RW=$2
  BS=$3
  QD=$4
  JOBS=$5

  echo -e "\n===== $NAME ($RW bs=$BS qd=$QD jobs=$JOBS) =====" >> "$RAW_OUTPUT"

  fio --name="$NAME" --rw="$RW" --rwmixread=50 --bs="$BS" --ioengine=libaio \
      --iodepth="$QD" --numjobs="$JOBS" --size="$SIZE" --runtime="$RUNTIME" \
      --group_reporting --filename="$TESTFILE" >> "$RAW_OUTPUT"
done

# ====== CLEANUP ======
[[ "$DELETE_FILE" =~ ^[Yy]$ ]] && rm -f "$TESTFILE"

echo
echo "✅ Benchmark complete!"
echo "Results saved to: $(realpath "$RAW_OUTPUT")"

# ====== PARSE RESULTS TO CSV ======
echo "Test Name,Block Size,Queue Depth,IOPS (Read),Bandwidth (Read),Latency Avg (Read),IOPS (Write),Bandwidth (Write),Latency Avg (Write)" > "$CSV_OUTPUT"

awk -v input_file="$RAW_OUTPUT" '
/^===== / {
    if (match($0, /===== ([^ ]+) \(randrw bs=([^ ]+) qd=([0-9]+)/, a)) {
         test_name = a[1]
         block_size = a[2]
         queue_depth = a[3]
    }
}
/^[[:space:]]*read:/ {
    if (match($0, /IOPS=([0-9.]+[kK]?)[,] BW=([^ ]+)/, a)) {
         iops_read = a[1]
         bw_read = a[2]
    }
}
/^[[:space:]]*slat \(usec\):/ && iops_read != "" && latency_read == "" {
    if (match($0, /avg=[[:space:]]*([0-9.]+)/, a)) {
         latency_read = a[1]
    }
}
/^[[:space:]]*write:/ {
    if (match($0, /IOPS=([0-9.]+[kK]?)[,] BW=([^ ]+)/, a)) {
         iops_write = a[1]
         bw_write = a[2]
    }
}
/^[[:space:]]*slat \(usec\):/ && iops_write != "" && latency_write == "" {
    if (match($0, /avg=[[:space:]]*([0-9.]+)/, a)) {
         latency_write = a[1]
         printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n", test_name, block_size, queue_depth, iops_read, bw_read, latency_read, iops_write, bw_write, latency_write
         iops_read = latency_read = iops_write = latency_write = ""
    }
}
' "$RAW_OUTPUT" >> "$CSV_OUTPUT"

echo
cat "$CSV_OUTPUT"
echo "\n✅ CSV data written to: $(realpath "$CSV_OUTPUT")"
