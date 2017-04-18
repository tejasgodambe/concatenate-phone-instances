#!/bin/bash

cmd=run.pl

. ./cmd.sh 

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
  echo "Usage: $0 phone ih"
  echo "Usage: $0 word  interactive"
  echo "This script outputs {word/phone}.lab and {word/phone}.wav"
fi

# 1) Intialization
working_dir="/home/tejas/experiments/nl-NL/s5" 
token=$1 # word | phone
export word_phone=$2
export data="data/train_32k_42k"
model_path="exp/tri1"
lang="data/lang"
nj=`cat ${model_path}_ali/num_jobs`

cd $working_dir


# 2) Generate $word_phone.lab file
[[ ! -e $word_phone.txt ]] || rm $word_phone.txt; 
[[ ! -e $word_phone.lab ]] || rm $word_phone.lab; 
touch $word_phone.txt
echo "#" > $word_phone.lab   


echo "Generating $word_phone.lab file ..." 

if [ "$token" == "phone" ]; then
  $cmd JOB=1:$nj logs/ctm.JOB.log ali-to-phones --ctm-output $model_path/final.mdl ark:"gunzip -c $model_path/ali.JOB.gz|" ${model_path}_ali/ctm
  ./utils/int2sym.pl -f 5 $lang/phones.txt ${model_path}_ali/ctm | sort | grep -w "$word_phone" | awk '{print $3 "_" $4, $1}' | ./utils/utt2spk_to_spk2utt.pl ">>" $word_phone.txt
  perl -e '$et=0; open PHONE, "$ENV{'word_phone'}.txt"; while (<PHONE>) {chomp; @arr=split; foreach $st_dur (@arr[1 .. $#arr]) {$st_dur=~s/.*_//; $et+=$st_dur; print "$et 125 $arr[0]\n";}}' >> $word_phone.lab 
fi

if [ "$token" == "word" ]; then
  steps/get_train_ctm.sh $data $lang ${model_path}_ali
  grep -w $word_phone ${model_path}_ali/ctm | awk '{print $3 "_" $4, $1}' | ./utils/utt2spk_to_spk2utt.pl >> $word_phone.txt
  perl -e '$et=0; open WORD, "$ENV{'word_phone'}.txt"; while (<WORD>) {chomp; @arr=split; foreach $st_dur (@arr[1 .. $#arr]) {$st_dur=~s/.*_//; $et+=$st_dur; print "$et 125 $arr[0]\n";}}' >> $word_phone.lab 
fi

cnt=$(grep -o -w "$word_phone" ${model_path}_ali/ctm | wc -l)
echo "No. of instances of \"$word_phone\" in data = $cnt"


# 3) Concatenate all instances of $word_phone present in $phone.lab
echo "Concatenating all instances of \"$word_phone\" ..."
sox -n -r 8000 -c 1 -b 16 $word_phone.wav trim 0.0 0.01
instance=0
perl -e '%table=(); open TABLE, "$ENV{'data'}/wav.scp"; while (<TABLE>) {chomp; @a=split; $table{$a[0]}=$a[1];} close TABLE; open WORD_PHONE, "$ENV{'word_phone'}.txt"; while (<WORD_PHONE>) {chomp; @arr=split; $ENV{'instance'}+=$#arr; print "Concatenating $ENV{'instance'} instance\n"; $fname=$table{$arr[0]}; foreach $st_dur (@arr[1 .. $#arr]) {$st_dur=~s/_/ /; system "sox $fname temp.wav trim $st_dur"; system "sox $ENV{'word_phone'}.wav temp.wav $ENV{'word_phone'}.temp.wav"; system "mv $ENV{'word_phone'}.temp.wav $ENV{'word_phone'}.wav";}}'
rm temp.wav $word_phone.txt 
