# ceph-benchmark
Tools and scripts to run (semi-)automated performance benchmarks against ceph

## Current tools
- fio_rbd.sh: run fio tests against RBDs (via librbd)

## TODOs
- make rbd name configurable
- check rbd size against requested size if run reuses existing rbd (prevent fio seqfault)
- add optional features:
  - disable scrub/deepscrub
  - collect 'rbd du' before and after for all used rbds
  - cat fio results into bash output/log
- separate into functions (e.g. fillup function)
