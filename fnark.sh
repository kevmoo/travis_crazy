#!/bin/bash

travis compile > monkey.sh
git commit -am 'stuff'
git push
docker build --no-cache -t temp .
