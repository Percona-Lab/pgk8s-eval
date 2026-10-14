#!/bin/bash
# fetch probe logs to results/probe-<name>.log
cd ~/pgk8s; for n in pdirect pbouncer cnpg; do ssh -F ssh_config pk-cp "kubectl -n probe logs probe-$n" > results/probe-$n.log; done
