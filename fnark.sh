#!/bin/bash

set -v
travis compile > monkey.sh
git commit -am 'stuff'
git push
docker build --no-cache -t temp .
