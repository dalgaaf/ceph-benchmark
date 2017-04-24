#!/bin/bash

BASE_DIRNAME="WDLabs.CMHe8"
BASE_TESTSETUP_STRING="rbd"
BASE_comment=""
SLEEP_INTERVAL=60
LOGFILE="`pwd`/fio_run.log"

log_msg () {
    echo "[$(date --rfc-3339=seconds)]: $*" >> ${LOGFILE}
    echo "[$(date --rfc-3339=seconds)]: $*"
}

is_int() {
  case $1 in
    ''|*[!0-9]*)
      log_msg "error: Not a number" >&2; exit 1
      ;;
    *)
      ;;
  esac
}

collect() {
  mkdir common_info
  cd common_info
  log_msg "start common collecting some base info ..."
   uname -a > uname
   hostname -s > hostname
   ifconfig > ifconfig
   # hwinfo > hwinfo
  log_msg "... finished common collecting some base info."
  cd ..
}

cleanup () {
  log_msg "cleanup system ... "
  sync
  free > memlog
  echo 1 > /proc/sys/vm/drop_caches
  echo 2 > /proc/sys/vm/drop_caches
  echo 3 > /proc/sys/vm/drop_caches
  free >> memlog
  log_msg "... done"
}

cleanup_rbd () {
  log_msg  "Called cleanup_rbd() ... "
  for i in `rbd ls`; do
    if  [[ "$i" =~ ^fio_test* ]] ; then
      log_msg  "Remove rbd: ${i} ... "
      rbd rm $i;
      log_msg "... done"
    fi
  done
}

prepare_rbd() {
  rbd_ops=$1
  n_rbds=$2

  if [ "$n_rbds" -gt 0 ]; then
    for i in $(seq 1 $n_rbds); do
       log_msg "Create new rbd with name fio_test${i} and options: '${rbd_ops}' ... "
       rbd -p rbd create $rbd_ops fio_test$i || exit 1
       log_msg "... done"
    done
  fi
}

run_fio() {
  log_msg "run_fio() called with $@"
  #run_fio #rbds size bs iodepth pattern base_type max_time rbd_setup rbd_stipe_unit rbd_stipe_count rbd_objsize
  num_rbds=$1
  size_gbyte=$2
  bs=$3
  iodepth=$4
  pattern=$5
  base_type=$6
  max_time=$7  # in seconds
  rbd_setup=$8
  rbd_stipe_unit=$9
  rbd_stipe_count=${10}
  rbd_objsize=${11}

  is_int $num_rbds
  is_int $bs
  is_int $iodepth
  is_int $size_gbyte

  rbd_size_mbyte=$(($size_gbyte*1024))
  RBD_Options="--size $rbd_size_mbyte"

  fio_cmd_tmp=""

  RBD_NEW="true"
  REUSE_RBD=""

  if [ -n "$rbd_setup" ] ; then
    case $rbd_setup in
      R|r)
        log_msg "Reuse RBD ..."
        RBD_NEW="false"
        REUSE_RBD=".prefilled"
        ;;
      N|n)
        log_msg "Setup new RBD ..."
        ;;
      *)
        log_msg "Unknown option (${rbd_setup}) for rbd setup type, fallback to setup a new rbd"
        ;;
    esac
  else
    log_msg "ERROR: no rbd setup type (N=new, R=reuse) defined"%
    exit 1
  fi

  if [ -n "$rbd_stipe_unit" -a $rbd_stipe_unit != "0" ]; then
    is_int $rbd_stipe_unit
    log_msg "rbd_stipe_unit = ${rbd_stipe_unit}"
    RBD_Options="$RBD_Options --image-format 2 --stripe-unit $rbd_stipe_unit"%

    if [ -n "$rbd_stipe_count" ]; then
      is_int $rbd_stipe_count
      RBD_Options="$RBD_Options --stripe-count $rbd_stipe_count"
    fi
  fi
  if [ -n "$rbd_objsize" -a $rbd_objsize != "0" ]; then
    is_int $rbd_objsize
    log_msg "rbd_objsize = ${rbd_objsize}"
    RBD_Options="$RBD_Options --object-size $rbd_objsize"
    BASE_comment="${BASE_comment}.objsize${rbd_objsize}"
  fi


  if [ -n "$base_type" ] ; then
    case $base_type in
      T|t)
        log_msg "Run time based fio."
        is_int $max_time
        fio_cmd_tmp="--time_based --runtime=${max_time} "
        ;;
      S|s)
        log_msg "Run size instead of time based fio run"
        ;;
      *)
        log_msg "Unknown option value for (${time_based}), Exit"
        exit 1
        ;;
    esac
  else
    log_msg "ERROR: no fio base type (time or size) defined"
    exit 1
  fi

  if [ -n "$pattern" ] ; then
    case $pattern in
      read|write|randread|randwrite|readwrite|randrw)
        log_msg "Run time ${pattern} pattern"
        ;;
      *)
        log_msg "Unknown option value for pattern (${pattern}), Exit"
        exit 1
        ;;
    esac
  else
    log_msg "ERROR: no fio io pattern defined"
    exit 1
  fi

  log_msg "--- START FIO RUN with bs=${bs}k iodepth=${iodepth} pattern=${pattern} against a RBD with size of ${size_gbyte}GB"

  if [ -n "$size_gbyte" ] ; then
    if [ "$size_gbyte" -gt 0 ] ; then
      fio_cmd_tmp+="--size=${size_gbyte}G "
    fi
  fi

  if [ "$num_rbds" -gt 0 ]; then
    for i in $(seq 1 $num_rbds); do
       fio_cmd_tmp+="--name=rbd_run${i} --rbdname=fio_test${i} ";
    done
  fi

  fiocmd="fio --ioengine=rbd --clientname=admin --pool=rbd  --invalidate=0 --direct=1 --buffered=0 \
          --bs=${bs}k --readwrite=${pattern} --iodepth=${iodepth} \
          --write_iops_log=w_iops_log --write_bw_log=w_bw_log --write_lat_log=w_lat_log \
          --write_hist_log=w_hist_log --log_avg_msec=500 --log_hist_msec=1000 \
          --group_reporting=1 --output=fio_log ${fio_cmd_tmp}"

  fiocmd=$(sed 's/ \{1,\}/ /g' <<< $fiocmd)
  log_msg "Compiled fio_cmd: '${fiocmd}'"

  DATE=`date +%Y%m%d%H%M`
  if [ -n "$BASE_comment" ] ; then
    dirname="${BASE_DIRNAME}.${BASE_TESTSETUP_STRING}.${BASE_comment}.${num_rbds}rbd.${pattern}.${size_gbyte}G.${bs}k_iodepth${iodepth}_${rbd_setup}_${DATE}"
  else
    dirname="${BASE_DIRNAME}.${BASE_TESTSETUP_STRING}.${num_rbds}rbd.${pattern}.${size_gbyte}G.${bs}k_iodepth${iodepth}_${rbd_setup}_${DATE}"
  fi

  if [ "$RBD_NEW" == "true" ] ; then
    cleanup_rbd
    log_msg "Go to sleep for ${SLEEP_INTERVAL} sec to settle ..."
     sleep $SLEEP_INTERVAL
    log_msg "done ... wake up."
     prepare_rbd "${RBD_Options}" "${num_rbds}"
    log_msg "Go to sleep for ${SLEEP_INTERVAL} sec to settle ..."
     sleep $SLEEP_INTERVAL
    log_msg "done ... wake up."
  fi

  log_msg "Create and change to dir ${dirname} ..."
   mkdir $dirname
   cd $dirname
  log_msg "... done"

  log_msg "cleanup osd blacklist ..."
   ceph osd blacklist ls > ceph_osd_blacklist
   for i in `ceph osd blacklist ls | cut -d " " -f1`; do
     ceph osd blacklist rm $i
   done
   echo " ------- AFTER CLEAMUP: --------" >> ceph_osd_blacklist
   ceph osd blacklist ls >> ceph_osd_blacklist
  log_msg "... done"

  log_msg "start collecting some base info ..."
   echo "$fiocmd" >> fio_cmd
   date > date
   cp /var/log/syslog .
   dmesg > dmesg
   ceph -v > ceph_version
   ceph -s > ceph_status
   ceph df > ceph_df
   ceph osd tree > ceph_osd_tree
   ceph osd dump > ceph_osd_dump
   ceph osd df > ceph_osd_df
   rados lspools > rados_pools
   rados df > rados_df
   for i in `rados lspools`; do
     for j in `rbd -p $i ls`; do
       if test $? -eq 0; then
         echo "check pool $i for rbd image $j" >> rbd_infos
         rbd -p $i info $j >> rbd_infos
       fi
     done
   done
   mkdir ceph_osd_config && cd ceph_osd_config
   for i in `ceph osd ls`; do
     ceph -n osd.$i --show-config > osd$i
   done
   cd ..
   cp ../common_info/* .
  log_msg "... finished collecting some base info."

  cleanup
  sleep $SLEEP_INTERVAL

  log_msg "run fio ..."
   $fiocmd
  log_msg " ... done"

  log_msg "Go to sleep for ${SLEEP_INTERVAL} sec to settle ..."
   sleep $SLEEP_INTERVAL
  log_msg "done ... wake up."

  log_msg "--- FINISHED FIO RUN with bs=${bs}k iodepth=${iodepth} pattern=${pattern}"

  # collect logs
  dmesg > dmesg-after
  cp /var/log/syslog syslog-after
  cd ..
}

# single run collection
collect

#run_fio #rbds size bs iodepth pattern base_type max_time rbd_setup rbd_stipe_unit rbd_stipe_count rbd_objsize
#run_fio {n} {n} {n} {n} {T|S} {read|write|randread|randwrite|readwrite|randrw} {n} {N|R} {n} {n} {n}

# example

for blocksize in 4 8 16 32 64 128 256 512 1024 2048 4096; do
  for io_depth in 1 16 32 64 128; do
    run_fio 1 10 $blocksize $io_depth write T 900 N 0 0 0
  done
done

