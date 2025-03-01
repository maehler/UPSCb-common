#!/bin/bash

# safeguards
set -ex

# project vars
account=SNIC2019-3-207
mail=nicolas.delhomme@umu.se

# source
source functions.sh

# modules
#module load bioinfo-tools seidr-devel
#export PATH=/pfs/nobackup/home/b/bastian/seidr/build:$PATH
source /pfs/nobackup/home/b/bastian/seidr/build/sourcefile

# Variables
resultDir=results

correlationNCPUs=28

inference=(aracne clr genie3 llr-ensemble narromi pcor pearson plsnet spearman tigress)

run=(
  [0]=0
  [1]=0
  [2]=0
  [3]=0
  [4]=0
  [5]=1
  [6]=1
  [7]=0
  [8]=1
  [9]=0)

# 28 workers on 1 nodes (kk has 28 per node) - setting -n 2 -c 14 (14 cores on 2 nodes, results in the same)
default="-n 1 -c 28 -t 1-00:00:00"

arguments=(
  [0]=$default
  [1]=$default
  [2]="-n 2 -c 28 -t 2-00:00:00"
  [3]=$default
  [4]=$default
  [5]="-n 1 -c $correlationNCPUs -t 12:00:00"
  [6]="-n 1 -c $correlationNCPUs -t 12:00:00"
  [7]=$default
  [8]="-n 1 -c $correlationNCPUs -t 12:00:00"
  [9]="-n 3 -c 28 -t 3-00:00:00")

parallel="-O "'$SLURM_CPUS_PER_TASK'
command=(
  [0]="mi -m ARACNE -M $resultDir/mi/mi.tsv "$parallel
  [1]="mi -m CLR -M $resultDir/mi/mi.tsv "$parallel
  [2]="genie3 "$parallel
  [3]="llr-ensemble "$parallel
  [4]="narromi "$parallel
  [5]="pcor"
  [6]="correlation -m pearson"
  [7]="plsnet "$parallel
  [8]="correlation -m spearman"
  [9]="tigress "$parallel)

# usage
USAGETXT=\
"
$0 <expression-matrix.tsv> <genes.tsv>

Methods to be run: ${inference[@]}

"

# input: gene and data
if [ $# -ne 2 ]; then
  abort "This script expects 2 arguments"
fi

if [ ! -f $1 ]; then
  abort "The first argument needs to be the expression matrix tab delimited file"
fi

if [ ! -f $2 ]; then
  abort "The second argument needs to be the gene names tab delimited file"
fi

# create dirs
if [ ! -d $resultDir ]; then
  mkdir $resultDir
fi

if [ ! -d $resultDir/mi ]; then
  mkdir $resultDir/mi
fi

# Find the number of genes to set the batch size
# Rules: set -B to
# 1) the number of genes if you are using a single node
# 2) if using more nodes split the number of genes by the number of nodes
# 3) for batch mode, set it to batch
ngenes=$(cat $2 | wc -w)
default="-B $ngenes"

# the number of nodes depends on the arguments list and default
optionB=(
  [0]=$default
  [1]=$default
  [2]="-B $(expr $(expr $ngenes '/' 2) '+' 1)"
  [3]=$default
  [4]=$default
  [5]=""
  [6]=""
  [7]=$default
  [8]=""
  [9]="-B $(expr $(expr $ngenes '/' 3) '+' 1)")

# Set the number of OMP threads
# default to 1
# set to -n (number of cores for pearson, spearman, and pcor
default=
ompThread=(
  [0]=$default
  [1]=$default
  [2]=$default
  [3]=$default
  [4]=$default
  [5]=$correlationNCPUs
  [6]=$correlationNCPUs
  [7]=$default
  [8]=$correlationNCPUs
  [9]=$default)

# Set dependencies
# Both ARACNE and CLR calculate the RAW MI
# We will have ARACNE export it and CLR use it.
deps=(
  [1]=0
)

# Define a JobIDs array
jobIDs=()

# Create template script and submit
len=${#inference[@]}
for ((i=0;i<len;i++)); do
  inf=${inference[$i]}
  if [ ${run[$i]} -eq 1 ]; then
    if [ ! -f $resultDir/$inf/$inf.tsv ]; then
      mkdir -p $resultDir/$inf
      echo "#!/bin/bash" > $resultDir/$inf/$inf.sh
      if [ -z ${ompThread[$i]} ]; then
 	echo "unset OMP_NUM_THREADS" >> $resultDir/$inf/$inf.sh
      else
    	echo "export OMP_NUM_THREADS=${ompThread[$i]}" >> $resultDir/$inf/$inf.sh
      fi
      echo "srun --cpu-bind=cores ${command[$i]} ${optionB[$i]} -i $1 -g $2 -o $resultDir/$inf/$inf.tsv" >> $resultDir/$inf/$inf.sh

      # Handle dependencies
      dep=
      if [ ! -z ${deps[$i]} ]; then
        dep="-d afterok:${jobIDs[${deps[$i]}]}"
      fi

      dep=$(sbatch --mail-type=ALL --mail-user=$mail -A $account -J $inf $dep \
      -e $resultDir/$inf/$inf.err -o $resultDir/$inf/$inf.out ${arguments[$i]} $resultDir/$inf/$inf.sh)

      jobIDs[$i]=${dep//[^0-9]/}
    fi
  fi
done

