#!/bin/bash

# Job parameters
#SBATCH --job-name=SEED
#SBATCH --output=sim.out
#SBATCH --error=sim.err
#SBATCH --open-mode=append
#SBATCH --dependency=singleton

# Partition parameters
#SBATCH --partition=gpu
#SBATCH --time=2-00:00:00

## CPU-only parameters
##SBATCH --nodes=1
##SBATCH --ntasks=1
##SBATCH --cpus-per-task=2

# GPU parameters
#SBATCH --ntasks=1
#SBATCH --gpus-per-task=1 

module load cuda/12.4 

export AMBERHOME=/groups/nl2960_gp/software/amber24/
export PATH="$AMBERHOME/bin:$PATH"

source $AMBERHOME/amber.sh

if [[ ! -f Prod_1.rst ]]; then
    $AMBERHOME/bin/pmemd.cuda -O -i Restart.in -o Prod_1.out -p PARM7 -c RST7 -r Prod_1.rst -ref RST7 -x Prod_1.nc
elif [[ -f Prod_1.rst ]]; then
    last=$(ls -1 Prod_*.rst | sed 's/.*_\([0-9]\+\).*/\1/' | sort -n | tail -n1)
    $AMBERHOME/bin/pmemd.cuda -O -i Prod.in -o Prod_$((last+1)).out -p PARM7 -c Prod_$last.rst -r Prod_$((last+1)).rst -ref Prod_$last.rst -x Prod_$((last+1)).nc
fi
