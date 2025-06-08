#!/bin/bash

set -ex

get_max_jobs() {
    cpu_cores=$(nproc)
    load=$(awk '{print $1}' /proc/loadavg)
    max_jobs=$(awk -v load="$load" -v cores="$cpu_cores" 'BEGIN {
        if (load == 0) load = 0.01;
        base_jobs = cores * 2;
        max_jobs_calculated = int(base_jobs * cores / load);
        max_jobs_max = cores * 4;
        max_jobs_min = cores / 2;
        if (max_jobs_calculated > max_jobs_max) {
            print max_jobs_max
        } else if (max_jobs_calculated < max_jobs_min) {
            print max_jobs_min
        } else {
            print max_jobs_calculated
        }
    }')
    echo "$max_jobs"
}

cd gem5

dimensions=(8 16 32 64 128 256 512 1024 2048 3072 4096)
# dimensions=(8 16 32 64 128 256 512 1024 2048 4096)
# dimensions=(512 1024)
# dimensions=(8 16 32 64 128 256 2048 3072 4096)
# topks=(1 5 10 50 100)
topks=(1 5 10 50)
# topks=(100)
train=1000
test=100

vlens=(128 256 512 1024)
# vlens=(512 1024)
# vlens=(128 256)
elen=64

# Define base directories
BASE_DIR="../"

for vlen in "${vlens[@]}"; do
    # Create directories if they don't exist
    LOGS_DIR="${BASE_DIR}rvv-logs-vlen${vlen}-elen${elen}"
    OUTPUT_DIR="${BASE_DIR}rvv-output-vlen${vlen}-elen${elen}"

    for dir in "${LOGS_DIR}" "${OUTPUT_DIR}"; do
        if [ ! -d "${dir}" ]; then
            mkdir -p "${dir}"
        fi
    done

    for dim in "${dimensions[@]}"; do
        for topk in "${topks[@]}"; do
            DATASET_NAME="random-euclidean-${dim}-${train}-${test}"
            TEST_NAME="${DATASET_NAME}-top${topk}"
            M5OUT_DIR="${OUTPUT_DIR}/m5out-rvv-${TEST_NAME}"
            LOG_FILE="${LOGS_DIR}/rvv-${TEST_NAME}.log"
            DATASET_PATH="/home/zxge/VDB/hnsw/data/${DATASET_NAME}.bin"

            (
                echo "Running rvv test for dimension $dim and topk $topk..."
                { time build/RISCV/gem5.opt --outdir="${M5OUT_DIR}" \
                    configs/example/bvb-board.py \
                    --vlen $vlen \
                    --elen $elen \
                    --resource ../build/bin/hnsw_search_riscv_rvv \
                    --prog_args="--topk ${topk} --dataset ${DATASET_PATH}" \
                    ; } 2>&1 > "${LOG_FILE}"
                echo "RVV Test for dimension $dim and topk $topk completed."
            ) &

            while [ "$(jobs -r | wc -l)" -ge "$(get_max_jobs)" ]; do
                sleep 1
            done
            
            # (
            #     echo "Running rv test for dimension $dim and topk $topk..."
            #     { time build/RISCV/gem5.opt --outdir="${OUTPUT_DIR}/m5out-rv-${TEST_NAME}" \
            #         configs/example/bvb-board.py \
            #         --vlen $vlen \
            #         --elen $elen \
            #         --resource ../build/bin/hnsw_search_riscv \
            #         --prog_args="--topk ${topk} --dataset ${DATASET_PATH}" \
            #         ; } 2>&1 > "${RV_LOGS_DIR}/rv-${TEST_NAME}.log"
            #     echo "RV Test for dimension $dim and topk $topk completed."
            # ) &
            
            # while [ "$(jobs -r | wc -l)" -ge "$max_jobs" ]; do
            #     sleep 1
            # done
        done
    done
done

wait

echo "All tests completed."

# time build/RISCV/gem5.opt --outdir=../m5out-rv256 configs/example/bvb-board.py --vlen 1024 --resource ../build/bin/hnsw_search_riscv --prog_args="--topk 100 --dataset /home/zxge/VDB/hnsw/data/random-euclidean-512-1000-100.bin" 
