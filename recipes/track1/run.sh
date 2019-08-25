#!/bin/bash

export PATH="/share/spandh.ami1/sw/std/python/anaconda3-5.1.0/v5.1.0/bin:$PATH" # for virtualenv

#####################################
### Mangesh: experiment params ######
#####################################
system_id="sys5"
#####################################

echo "Running system: $system_id"

pca_dim=-1

if [ $system_id == "sys1" ]; then
    # Baseline.
    vector_type="xvector"
    plda_file="plda_track1"
    model_file="final.raw"
elif [ $system_id == "sys2" ]; then
    vector_type="ivector"
    # Voxceleb i-vector from http://kaldi-asr.org/models/m7.
    plda_file="ivector-pretrained.plda"
    model_file="ivector-pretrained.ie ivector-pretrained.ubm"
    pca_dim=200
elif [ $system_id == "sys3" ]; then
    # x-vector trained using dev set.
    vector_type="xvector"
    plda_file="dev-xvector.plda"
    model_file="dev-xvector.raw"
    pca_dim=200
elif [ $system_id == "sys4" ]; then
    # i-vector trained using dev set.
    vector_type="ivector"
    plda_file="dev-ivector.plda"
    model_file="dev-ivector.ie dev-ivector.ubm"
    pca_dim=200
elif [ $system_id == "sys5" ]; then
    # Voxceleb x-vector from http://kaldi-asr.org/models/m7.
    vector_type="xvector"
    plda_file="xvector-pretrained.plda"
    model_file="xvector-pretrained.raw"
    pca_dim=200
fi

set -e

NJOBS=40
PYTHON=python

exp_dir=exp/${system_id}

#####################################
#### Set following paths  ###########
#####################################
# Path to root of DIHARD II dev release (LDC2019E31).
DIHARD_DEV_DIR=/share/mini5/data/audvis/dia/dihard-2018-dev-for-use-with-2019-baseline

# Path to root of DIHARD II eval release (LDC2019E32).
DIHARD_EVAL_DIR=/share/mini5/data/audvis/dia/dihard-2018-eval-for-use-with-2019-baseline

#####################################
#### Check deps satisfied ###########
#####################################
THIS_DIR=`realpath $(dirname "$0")`
TOOLS_DIR=$THIS_DIR/../../tools
SCRIPTS_DIR=$THIS_DIR/../../scripts
[ -f $TOOLS_DIR/env.sh ] && . $TOOLS_DIR/env.sh
if [ -z	$KALDI_DIR ]; then
    echo "KALDI_DIR not defined. Please run tools/install_kaldi.sh"
    exit 1
fi
$SCRIPTS_DIR/prep_eg_dir.sh --vector-type $vector_type --model-file "$model_file" --plda-file $plda_file --system-id $system_id


#####################################
#### Run experiment  ################
#####################################
EG_DIR=$KALDI_DIR/egs/dihard_2018/v2
pushd $EG_DIR > /dev/null
echo $PWD

# Prepare data directory for DEV set.
echo "Preparing data directory for DEV set..."
DEV_DATA_DIR=data/${system_id}_dev
rm -fr $DEV_DATA_DIR
local/make_data_dir.py \
   --audio_ext '.flac' \
   --rttm_dir $DIHARD_DEV_DIR/data/single_channel/rttm \
   $DEV_DATA_DIR \
   $DIHARD_DEV_DIR/data/single_channel/flac \
   $DIHARD_DEV_DIR/data/single_channel/sad
utils/fix_data_dir.sh $DEV_DATA_DIR

# Prepare data directory for EVAL set.
echo "Preparing data directory for EVAL set...."
EVAL_DATA_DIR=data/${system_id}_eval
rm -fr $EVAL_DATA_DIR
local/make_data_dir.py \
   --audio_ext	'.flac'	\
   $EVAL_DATA_DIR \
   $DIHARD_EVAL_DIR/data/single_channel/flac \
   $DIHARD_EVAL_DIR/data/single_channel/sad
utils/fix_data_dir.sh $EVAL_DATA_DIR

# Diarize.
echo "Diarizing..."
./alltracksrun.sh --vector_type $vector_type --plda_path $exp_dir/plda --njobs $NJOBS --pca_dim $pca_dim --system-id $system_id

# Extract dev/eval RTTM files.
echo "Extracting RTTM files..."
DEV_RTTM_DIR=$THIS_DIR/rttm_dev
local/split_rttm.py \
    $exp_dir/vectors_${system_id}_dev/plda_scores/rttm $DEV_RTTM_DIR
EVAL_RTTM_DIR=$THIS_DIR/rttm_eval
local/split_rttm.py \
    $exp_dir/vectors_${system_id}_eval/plda_scores/rttm $EVAL_RTTM_DIR

popd > /dev/null

# Score system outputs for DEV set against reference.
echo "Scoring DEV set RTTM..."
$PYTHON $DSCORE_DIR/score.py \
    -u $DIHARD_DEV_DIR/data/single_channel/uem/all.uem \
    -r $DIHARD_DEV_DIR/data/single_channel/rttm/*.rttm \
    -s $DEV_RTTM_DIR/*.rttm \
    > metrics_dev.stdout 2> metrics_dev.stderr

# Score system outputs for EVAL set against reference.
echo "Scoring EVAL set RTTM..."
$PYTHON $DSCORE_DIR/score.py \
    -u $DIHARD_EVAL_DIR/data/single_channel/uem/all.uem \
    -r $DIHARD_EVAL_DIR/data/single_channel/rttm/*.rttm \
    -s $EVAL_RTTM_DIR/*.rttm \
    > metrics_eval.stdout 2> metrics_eval.stderr

echo "Run finished successfully."
