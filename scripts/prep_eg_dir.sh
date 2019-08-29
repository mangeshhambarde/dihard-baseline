#!/bin/bash
# Prepare the ``egs/dihard_2018/v2`` directory for experiments.

vector_type="xvector" # default option.
model_file="final.raw"
plda_file="plda_track1"
system_id="default"

THIS_DIR=`realpath $(dirname "$0")`
DATA_DIR=$THIS_DIR/../data
KALDI_DIR=$THIS_DIR/../tools/kaldi
SCRIPTS_DIR=$THIS_DIR/../scripts
DIHARD_EG_DIR=$KALDI_DIR/egs/dihard_2018/v2

. $KALDI_DIR/egs/wsj/s5/utils/parse_options.sh || exit 1;

if [ -f $KALDI_DIR ]; then
    echo "$KALDI_DIR not found. Please run ``tools/install_kaldi.sh``"
    exit 1
fi
if [ -f $DIHARD_EG_DIR ]; then
    "$DIHARD_EG_DIR not found. Please run ``tools/install_kaldi.sh``"
    exit 1
fi

BNS="alltracksrun.sh md_eval.pl clean_slate.sh"
for bn in $BNS; do
    src_path=$SCRIPTS_DIR/$bn
    dest_path=$DIHARD_EG_DIR/$bn
    cp $src_path $dest_path
done

BNS="beamformit.cfg"
CONF_DIR=$DIHARD_EG_DIR/conf
for bn in $BNS; do
    src_path=$DATA_DIR/$bn
    dest_path=$CONF_DIR/$bn
    cp $src_path $dest_path
done
BNS="flac_to_wav.sh make_data_dir.py run_beamformit.sh run_denoising.sh run_vad.sh split_rttm.py prepare_feats.sh extract_cvectors.sh score_plda.sh"
for bn in $BNS; do
    src_path=$SCRIPTS_DIR/$bn
    dest_path=$DIHARD_EG_DIR/local/$bn
    cp $src_path $dest_path
done

VEC_DIR=$DIHARD_EG_DIR/exp/${system_id}

mkdir -p $VEC_DIR

BNS="max_chunk_size min_chunk_size extract.config"
for bn in $BNS; do
    src_path=$DATA_DIR/$bn
    dest_path=$VEC_DIR/$bn
    cp $src_path $dest_path
done

# Copy nnet or ivec models.
BNS="$model_file"
for bn in $(echo $BNS); do
    fileext=${bn##*.}
    src_path=$DATA_DIR/$bn
    dest_path=$VEC_DIR/"final.$fileext"
    cp $src_path $dest_path
done

# Copy PLDA file.
cp $DATA_DIR/$plda_file $VEC_DIR/plda

# Change MFCC config based on argument.
echo "Copying appropriate mfcc.conf"
if [ $vector_type == "ivector" ]; then
    cp $DATA_DIR/mfcc-ivector.conf $CONF_DIR
elif [ $vector_type == "xvector" ]; then
    cp $DATA_DIR/mfcc-xvector.conf $CONF_DIR
elif [ $vector_type == "cvector" ]; then
    cp $DATA_DIR/mfcc-ivector.conf $CONF_DIR
    cp $DATA_DIR/mfcc-xvector.conf $CONF_DIR
fi
