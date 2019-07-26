#!/usr/bin/bash

if [ "$1" == "-n" ]; then
  ls -ld data/dihard_*
  ls -ld exp/dihard_*
  ls -ld exp/ivector/vectors_*
  ls -ld exp/make_mfcc/dihard_*
  ls -ld mfcc
  ls -ld exp/xvector_nnet_1a/vectors_dihard_*
  ls -ld exp/xvector_nnet_1a/tuning_track*
  exit
fi

rm -rf data/dihard_*
rm -rf exp/dihard_*
rm -rf exp/ivector/vectors_*
rm -rf exp/make_mfcc/dihard_*
rm -rf mfcc
rm -rf exp/xvector_nnet_1a/vectors_dihard_*
rm -rf exp/xvector_nnet_1a/tuning_track*
