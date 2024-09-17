#!/bin/bash -x

for f in *.img; do
    xz -z -9 --threads=0 -v $f
done
