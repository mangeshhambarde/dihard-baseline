. ./cmd.sh
. ./path.sh
set -e
mfccdir=`pwd`/mfcc
vaddir=`pwd`/vad


vec_dir="exp/default"
plda_path=default
njobs=40
stage=0
vector_type="xvector" # default option.
pca_dim=-1
system_id="default"

. parse_options.sh || exit 1;

if [ $# != 0 -o "$plda_path" = "default" ]; then
  echo "Usage: $0 --plda_path <path of plda file>"
  echo "main options (for others, see top of script file)"
  echo "  --plda_path <plda-file>           # path of PLDA file"
  echo "  --njobs <n|40>                    # number of jobs"
  echo "  --stage <stage|0>                 # current stage; controls partial reruns"
  echo "  --vector_type <ivector|xvector>   # speaker representation used"
  echo "  --system_id                          # system_id id"
  exit 1;
fi

# Set exp directory.
vec_dir=exp/${system_id}

if [ $vector_type == "xvector" ]; then
    mfcc_conf_file="conf/mfcc-xvector.conf"
elif [ $vector_type == "ivector" ]; then
    mfcc_conf_file="conf/mfcc-ivector.conf"
elif [ $vector_type == "cvector" ]; then
    mfcc_conf_file="conf/mfcc-ivector.conf" # extract 24 dim MFCCs by default.
fi

# Set exp directory.
dihard_dev=${system_id}_dev
dihard_eval=${system_id}_eval

# Determine max num jobs for each of DEV/EVAL.
dev_nfiles=`wc -l < data/${dihard_dev}/wav.scp`
dev_njobs=$((${njobs}<${dev_nfiles}?${njobs}:${dev_nfiles}))
eval_nfiles=`wc -l < data/${dihard_eval}/wav.scp`
eval_njobs=$((${njobs}<${eval_nfiles}?${njobs}:${eval_nfiles}))

# Extract MFCCs.
if [ $stage -le 0 ]; then
    echo "Extracting MFCCs...."
    for name in ${dihard_dev} ${dihard_eval}; do
	if [[ "$name" == "$dihard_dev" ]]; then
	    njobs=$dev_njobs
	else
	    njobs=$eval_njobs
	fi
	set +e # We expect failures for short segments.
	steps/make_mfcc.sh \
	    --cmd "$train_cmd --max-jobs-run 20" --nj $njobs \
	    --write-utt2num-frames true --mfcc-config $mfcc_conf_file \
	    data/${name} exp/make_mfcc/$name $mfccdir
	set -e
	utils/fix_data_dir.sh data/${name}
    done

    # If cvector, we need to do feature extraction again for 30 dim.
    if [ $vector_type == "cvector" ]; then
        echo "Extracting second set of MFCCs for cvectors."
        for name in ${dihard_dev}_2 ${dihard_eval}_2; do
	        if [[ "$name" == "${dihard_dev}_2" ]]; then
	            njobs=$dev_njobs
	        else
	            njobs=$eval_njobs
	        fi
	        set +e # We expect failures for short segments.
	        steps/make_mfcc.sh \
	            --cmd "$train_cmd --max-jobs-run 20" --nj $njobs \
	            --write-utt2num-frames true --mfcc-config conf/mfcc-xvector.conf \
	            data/${name} exp/make_mfcc/${name} $mfccdir
	        set -e
	        utils/fix_data_dir.sh data/${name}
        done
    fi
    echo "MFCC extraction finished. See $PWD/exp/make_mfcc for logs."
fi

# Perform CMN.
if [ $stage -le 1 ]; then
    echo "Performing cepstral mean normalisation (CMN)..."
    for name in ${dihard_dev} ${dihard_eval}; do
        if [[ "$name" == "$dihard_dev" ]]; then
            njobs=$dev_njobs
        else
            njobs=$eval_njobs
        fi
	local/prepare_feats.sh \
	    --nj $njobs --cmd "$train_cmd" \
	    --vector-type "$vector_type" \
	    data/$name data/${name}_cmn exp/${system_id}/${name}_cmn
	if [ -f data/$name/vad.scp ]; then
	    echo "vad.scp found .. copying it"
	    cp data/$name/vad.scp data/${name}_cmn/
	fi
	if [ -f data/$name/segments ]; then
	    echo "Segments found .. copying it"
	    cp data/$name/segments data/${name}_cmn/
	fi
	utils/fix_data_dir.sh data/${name}_cmn
    done

    echo "Performing CMN (again) for cvectors..."
    if [ $vector_type == "cvector" ]; then
        for name in ${dihard_dev}_2 ${dihard_eval}_2; do
            if [[ "$name" == "${dihard_dev}_2" ]]; then
                njobs=$dev_njobs
            else
                njobs=$eval_njobs
            fi
	        local/prepare_feats.sh \
	            --nj $njobs --cmd "$train_cmd" \
	            --vector-type "$vector_type" \
	            data/$name data/${name}_cmn exp/${system_id}/${name}_cmn
	        if [ -f data/$name/vad.scp ]; then
	            echo "vad.scp found .. copying it"
	            cp data/$name/vad.scp data/${name}_cmn/
	        fi
	        if [ -f data/$name/segments ]; then
	            echo "Segments found .. copying it"
	            cp data/$name/segments data/${name}_cmn/
	        fi
	        utils/fix_data_dir.sh data/${name}_cmn
        done
    fi
    echo "CMN finished."
fi

DEV_VEC_DIR=$vec_dir/vectors_${dihard_dev}
EVAL_VEC_DIR=$vec_dir/vectors_${dihard_eval}

if [ $stage -le 2 ]; then
    # Extract i/x-vectors for DIHARD 2019 development and evaluation set.
    if [ $vector_type == "xvector" ]; then
        extraction_script=diarization/nnet3/xvector/extract_xvectors.sh
        dev_cmn_dir=data/${dihard_dev}_cmn
        dev_cmn_dir_2=
        eval_cmn_dir=data/${dihard_eval}_cmn
        eval_cmn_dir_2=
    elif [ $vector_type == "ivector" ]; then
        extraction_script=diarization/extract_ivectors.sh
        dev_cmn_dir=data/${dihard_dev}_cmn
        dev_cmn_dir_2=
        eval_cmn_dir=data/${dihard_eval}_cmn
        eval_cmn_dir_2=
    elif [ $vector_type == "cvector" ]; then
        extraction_script=local/extract_cvectors.sh
        dev_cmn_dir="data/${dihard_dev}_cmn"
        dev_cmn_dir_2="data/${dihard_dev}_2_cmn"
        eval_cmn_dir="data/${dihard_eval}_cmn"
        eval_cmn_dir_2="data/${dihard_eval}_2_cmn"
    fi

    echo "Extracting ${vector_type}s for DEV..."
    $extraction_script \
	--cmd "$train_cmd --mem 5G" --nj $dev_njobs \
	--window 1.5 --period 0.75 --apply-cmn false \
	--min-segment 0.5 --pca-dim $pca_dim $vec_dir \
	$dev_cmn_dir $dev_cmn_dir_2 $DEV_VEC_DIR
    echo "${vector_type} extraction finished for DEV. See $DEV_VEC_DIR/log for logs."

    echo "Extracting ${vector_type}s for EVAL..."
    $extraction_script \
	--cmd "$train_cmd --mem 5G" --nj $eval_njobs \
	--window 1.5 --period 0.75 --apply-cmn false \
	--min-segment 0.5 --pca-dim $pca_dim $vec_dir \
	$eval_cmn_dir $eval_cmn_dir_2 $EVAL_VEC_DIR
    echo "${vector_type} extraction finished for EVAL. See $EVAL_VEC_DIR/log for logs."
fi

# Perform PLDA scoring
PLDA_DIR=$DEV_VEC_DIR
DEV_SCORE_DIR=$DEV_VEC_DIR/plda_scores
EVAL_SCORE_DIR=$EVAL_VEC_DIR/plda_scores
if [ $vector_type == "xvector" ]; then
    scoring_script=diarization/nnet3/xvector/score_plda.sh
elif [ $vector_type == "ivector" ]; then
    scoring_script=diarization/score_plda.sh
elif [ $vector_type == "cvector" ]; then
    scoring_script=local/score_plda.sh
fi
if [ $stage -le 3 ]; then
    cp $plda_path $PLDA_DIR/plda

    echo "Performing PLDA scoring for DEV..."
    $scoring_script \
	    --cmd "$train_cmd --mem 4G" --nj $dev_njobs \
	    $PLDA_DIR $DEV_VEC_DIR $DEV_SCORE_DIR
    echo "PLDA scoring finished for DEV. See $DEV_SCORE_DIR/log for logs."

    echo "Performing PLDA scoring for EVAL..."
    $scoring_script \
	--cmd "$train_cmd --mem 4G" --nj $eval_njobs \
	$PLDA_DIR $EVAL_VEC_DIR $EVAL_SCORE_DIR
    echo "PLDA scoring finished for EVAL, See $EVAL_SCORE_DIR/log for logs."
fi

# Tune clustering threshold.
if [ $stage -le 4 ]; then
    mkdir -p $vec_dir/tuning
    echo "Tuning clustering threshold using DEV..."
    best_der=100
    best_threshold=0
    for threshold in -0.5 -0.4 -0.3 -0.2 -0.1 -0.05 0 0.05 0.1 0.2 0.3 0.4 0.5; do
	echo "Clustering with threshold $threshold..."
	cluster_dir=${DEV_VEC_DIR}/plda_scores_t${threshold}
	diarization/cluster.sh \
	    --cmd "$train_cmd --mem 4G" --nj $dev_njobs \
	    --threshold $threshold --rttm-channel 1 \
	    $DEV_SCORE_DIR $cluster_dir
	perl md_eval.pl -r data/${dihard_dev}/rttm \
	     -s $cluster_dir/rttm \
	     2> $vec_dir/tuning/${dihard_dev}_t${threshold}.log \
	     > $vec_dir/tuning/${dihard_dev}_t${threshold}
	der=$(grep -oP 'DIARIZATION\ ERROR\ =\ \K[0-9]+([.][0-9]+)?' \
		   $vec_dir/tuning/${dihard_dev}_t${threshold})
	if [ $(echo $der'<'$best_der | bc -l) -eq 1 ]; then
            best_der=$der
            best_threshold=$threshold
	fi
    done
    echo "Threshold tuning finished. See $DEV_VEC_DIR/plda_scores_t*/log for logs."
    echo "*** Best threshold is: $best_threshold. PLDA scores of eval ${vector_type}s will "
    echo "**  be clustered using this threshold"
    echo "*** DER on dev set using best threshold is: $best_der"
    echo "$best_threshold" > $vec_dir/tuning/${dihard_dev}_best
fi

# Cluster.
if [ $stage -le 5 ]; then
    best_threshold=$(cat $vec_dir/tuning/${dihard_dev}_best)
       
    echo "Performing agglomerative hierarchical clustering (AHC) using threshold $best_threshold for DEV..."
    diarization/cluster.sh \
	--cmd "$train_cmd --mem 4G" --nj $dev_njobs \
	--threshold $best_threshold --rttm-channel 1 \
	$DEV_SCORE_DIR $DEV_SCORE_DIR
    echo "Clustering finished for DEV. See $DEV_SCORE_DIR/log for logs."

    echo "Performing agglomerative hierarchical clustering (AHC) using threshold $best_threshold for EVAL..."
    diarization/cluster.sh \
	--cmd "$train_cmd --mem 4G" --nj $eval_njobs \
	--threshold $best_threshold --rttm-channel 1 \
	$EVAL_SCORE_DIR $EVAL_SCORE_DIR
    echo "Clustering finished for EVAL. See $EVAL_SCORE_DIR/log for logs."
fi
