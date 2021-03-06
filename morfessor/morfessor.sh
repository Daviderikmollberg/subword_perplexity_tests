#!/bin/bash
#Implematation of the morfessor subword segmentations
#The tool is avalible here https://github.com/Waino/morfessor-emprune
#Author David Erik Mollberg


if [ $# -ne 2 ]; then
  echo "Usage: morfessor.sh <lang name> <lexicon-size>"
  echo "e.g.: ./morfessor.sh test 100000"
  exit 1;
fi

# Lets clock the runtime
start=`date +%s`

# A parameter used to dicripe the current 
# test e.g. bpe1000 meaning bpe with 1000 merges.

lang=$1

# The parameter that we are going to change
alpha=$2 # Controls how aggresivly the algorithm will segment the words
lang="${alpha}_${lang}"

# Path to the folder where the corpus is located
corpus_folder=/home/derik/work/language_models/LM_corpus

# Name of our training corpus
#training_corpus=${corpus_folder}/demo_files/small_train_corpus
training_corpus=${corpus_folder}/rmh_train_half

# Name of our test corpus 
#test_corpus=${corpus_folder}/demo_files/small_test_corpus
test_corpus=${corpus_folder}/rmh_test_half

stage=0

mkdir -p $lang

if [ $stage -le 1 ]; then
    # We need a tokenized file for the next step
    echo "$0: Tokenizing file"
    cut -d' ' -f2- $training_corpus | sed 's/ /\n/g' > $lang/tokens_training
fi

stage_one=`date +%s`
echo "Tokenizing file took $(((stage_one-start)/60)) min"

if [ $stage -le 2 ]; then
    # Creating substring seed lexicon direct from a pretokenized corpus
    echo "$0: Creating substring seed lexicon"
    freq_substr.py --lex-size 1000000 < $lang/tokens_training > $lang/freq_substr
fi
stage_two=`date +%s`
echo "Creating substring took $(((stage_two-stage_one)/60)) min"

if [ $stage -le 3 ]; then
    # Perform Morfessor EM+Prune training.
    echo "$0: Performing Morfessor EM+Prune training"
    morfessor --em-prune $lang/freq_substr \
              --traindata $training_corpus \
              --num-morph-types $alpha \
              --save-segmentation $lang/emprune.model
fi

stage_three=`date +%s`
echo "Performing Morfessor EM+Prune training took $(((stage_three-stage_two)/60)) min"

if [ $stage -le 4 ]; then
    # Segment data using the Viterbi algorithm

    echo "$0: Segmenting test corpus"
    morfessor-segment $test_corpus \
                      --em-prune $lang/emprune.model \
                      --output-format-separator '@@ ' \
                      -o $lang/rmh_test_segments 
                      #| \
                      #sort -u > $lang/rmh_test_segments

    echo "$0: Segmenting training corpus"
    morfessor-segment $lang/tokens_training \
                      --em-prune $lang/emprune.model \
                      --output-format-separator '@@ ' \
                      -o $lang/rmh_test_segments
                      # | \
                      #sort -u > $lang/rmh_training_segments
fi

stage_four=`date +%s`
echo "Performing Morfessor EM+Prune training took $(((stage_four-stage_three)/60)) min"

if [ $stage -le 5 ]; then
    echo "$0: Applying segments to test text"
    python3 apply_segments_to_text.py $lang/rmh_test_segments $test_corpus $lang/rmh_test

    echo "$0: Applying segments to training text"
    python3 apply_segments_to_text.py $lang/rmh_training_segments $training_corpus $lang/rmh_training
fi

stage_five=`date +%s`
runtime="Applying BPE to text files took $((stage_five-stage_four)) sek"
echo $runtime
echo "Total runtime is $((stage_five-start)) sek"

if [ $stage -le 6 ]; then
  echo "=== Building a language model with KenLM"
  module load kenlm

  lmplz --skip_symbols \
        -o $order \
        -S 70% \
        -T /tmp \
        --prune 0 0 0 1 5 10\
        --discount_fallback 1 \
        --text $lang/rmh_training \
        --arpa $lang/kenlm_${order}g.arpa || error 1 "lmplz failed"
        
  build_binary $lang/kenlm_${order}g.arpa $lang/kenlm_${order}g.binary || error 1 "build_binary failed"
fi

stage_five=`date +%s`
runtime="Creating LM took $((stage_six-stage_five)) sek"
echo $runtime
echo "Total runtime is $((stage_six-start)) sek"

if [ $stage -le 3 ]; then
  echo "=== Calculating perplexity"
  module load kenlm
  
  query -v summary $lang/kenlm_${order}g.binary < $lang/rmh_test > $lang/perplexity || echo "query failed"

  cat $lang/perplexity
fi

stage_seven=`date +%s`
runtime="Calculating perplexity took $((stage_seven-stage_six)) sek"
echo $runtime
echo "Total runtime is $((stage_seven-start)) sek"