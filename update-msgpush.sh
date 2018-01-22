#!/bin/bash
set -x

cd ${GOPATH}/src/github.com/gcinterceptor/gci-go/httphandler/msgpush
go  build
if [ $? -ne 0 ]; then { echo "Compilation failed, aborting." ; exit 1; } fi

for instance in ${INSTANCES};
do
 ssh -i ~/fireman.sururu.key ubuntu@${instance} "killall msgpush"
 scp -i ~/fireman.sururu.key msgpush ubuntu@${instance}:~/
done