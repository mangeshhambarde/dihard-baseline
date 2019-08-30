#!/bin/bash

# Copyright          2013  Daniel Povey
#                    2016  David Snyder
#               2017-2018  Matthew Maciejewski
# Apache 2.0.

# This script extracts c-vectors over a sliding window for a
# set of utterances, given features and a trained iVector and xVector
# extractor. This is used for speaker diarization. This is done
# using subsegmentation on the data directory. As a result, the
# files containing "spk" (e.g. utt2spk) in the data directory
# within the cvector directory are not referring to true speaker
# labels, but are referring to recording labels. For example,
# the spk2utt file contains a table mapping recording IDs to the
# sliding-window subsegments generated for that recording.

# Begin configuration section.
nj=30
cmd="run.pl"
stage=0
window=1.5
period=0.75
pca_dim=
min_segment=0.5
hard_min=false
num_gselect=20 # Gaussian-selection using diagonal model: number of Gaussians to select
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)
posterior_scale=1.0 # This scale helps to control for successve features being highly
                    # correlated.  E.g. try 0.1 or 0.3.
apply_cmn=true # If true, apply sliding window cepstral mean normalization
apply_deltas=true # If true, copy the delta options from the i-vector extractor directory.
                  # If false, we won't add deltas in this step. For speaker diarization,
		  # we sometimes need to write features to disk that already have various
		  # post-processing applied so adding deltas is no longer needed in this stage.
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# != 4 ]; then
  echo "Usage: $0 <extractor-dir> <data1> <data2> <cvector-dir>"
  echo " e.g.: $0 exp/extractor_2048 data/train exp/cvectors"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --window <window|1.5>                            # Sliding window length in seconds"
  echo "  --period <period|0.75>                           # Period of sliding windows in seconds"
  echo "  --pca-dim <n|-1>                                 # If provided, the whitening transform also"
  echo "                                                   # performs dimension reduction."
  echo "  --min-segment <min|0.5>                          # Minimum segment length in seconds per cvector"
  echo "  --hard-min <bool|false>                          # Removes segments less than min-segment if true."
  echo "                                                   # Useful for extracting training cvectors."
  echo "  --nj <n|10>                                      # Number of jobs"
  echo "  --stage <stage|0>                                # To control partial reruns"
  echo "  --num-gselect <n|20>                             # Number of Gaussians to select using"
  echo "                                                   # diagonal model."
  echo "  --min-post <min-post|0.025>                      # Pruning threshold for posteriors"
  echo "  --apply-cmn <true,false|true>                    # if true, apply sliding window cepstral mean"
  echo "                                                   # normalization to features"
  echo "  --apply-deltas <true,false|true>                 # If true, copy the delta options from the i-vector"
  echo "                                                   # extractor directory. If false, we won't add deltas"
  echo "                                                   # in this step. For speaker diarization, we sometimes"
  echo "                                                   # need to write features to disk that already have"
  echo "                                                   # various post-processing applied so adding deltas is"
  echo "                                                   # no longer needed in this stage."
  exit 1;
fi

srcdir=$1 # extractor dir.
data1=$2 # 24 dim mfcc.
data2=$3 # 30 dim mfcc.
dir=$4 # final cvectors.

for f in $srcdir/final.ie $srcdir/final.ubm $data1/feats.scp $data2/feats.scp $srcdir/final.raw $srcdir/min_chunk_size $srcdir/max_chunk_size ; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

# Extract i-vectors.
if [ $stage -le 0 ]; then
    echo "$0: Extracting ivectors"
    diarization/extract_ivectors.sh \
    --cmd "$train_cmd --mem 5G" --nj $nj \
    --window 1.5 --period 0.75 --apply-cmn false \
    --min-segment 0.5 --pca-dim $pca_dim $srcdir \
    $data1 $srcdir/intermediate-ivectors || exit 1;
    cp $srcdir/intermediate-ivectors/{segments,spk2utt,utt2spk} $dir
fi

# Extract x-vectors.
if [ $stage -le 1 ]; then
    echo "$0: Extracting xvectors"
    diarization/nnet3/xvector/extract_xvectors.sh \
    --cmd "$train_cmd --mem 5G" --nj $nj \
    --window 1.5 --period 0.75 --apply-cmn false \
    --min-segment 0.5 --pca-dim $pca_dim $srcdir \
    $data2 $srcdir/intermediate-xvectors || exit 1;
    cp $srcdir/intermediate-xvectors/{segments,spk2utt,utt2spk} $dir
fi

# Concatenate.
if [ $stage -le 2 ]; then
    echo "$0: Concatenating i-vectors and x-vectors"
    # Concatenate i-vectors and x-vectors to get c-vectors.
    $train_cmd $dir/log/append_vectors.log \
      append-vectors \
        scp:$srcdir/intermediate-ivectors/ivector.scp \
        scp:$srcdir/intermediate-xvectors/xvector.scp \
        ark,scp:$dir/cvector.ark,$dir/cvector.scp || exit 1;
fi

if [ $stage -le 3 ]; then
  echo "$0: Computing mean of cvectors"
  $cmd $dir/log/mean.log \
    ivector-mean scp:$dir/cvector.scp $dir/mean.vec || exit 1;
fi

if [ $stage -le 4 ]; then
  if [ -z "$pca_dim" ]; then
    pca_dim=-1
  fi
  echo "$0: Computing whitening transform"
  $cmd $dir/log/transform.log \
    est-pca --read-vectors=true --normalize-mean=false \
      --normalize-variance=true --dim=$pca_dim \
      scp:$dir/cvector.scp $dir/transform.mat || exit 1;
fi
