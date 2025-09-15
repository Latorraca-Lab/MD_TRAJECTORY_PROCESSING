#!/bin/bash 

# Author: Christina A. Stephens
# Date: 20250618
# Purpose: Concatenate and reimage simulation trajectories 
#	   systematically.
#          For the given folder name, all directories matching
#          this name will be search and any trajectories found processed.
#          Processed trajectories will be outputed to a new folder called
#          "PROCESSED_TRAJS"
#          [!] This is customized for amber simulation output [!]
#          [!] Expects the following format for simulation output:
#              Min* = minimization
#	       Heat* = heating
#              Eq* = equilibration
#              Prod* = production
#          [!] if this does not match you naming system please edit 
#              the line marked "EDIT A"

# make sure you have access to cpptraj 
# it's provided by Amber
#export AMBERHOME=/groups/nl2960_gp/software/amber24/
#export PATH="$AMBERHOME/bin:$PATH"=
#source $AMBERHOME/amber.sh
HOME=`pwd`

master_ref='CHARMMGUI_prep_ref_aligned_chained_centered.pdb'

if [ ! -d "$HOME/SEEDS" ]; then
  mkdir $HOME/SEEDS
fi

OUTFLDR="$HOME/SEEDS"

FOLDER=""
only_prod="F"
ALIGN="F"
CENTER="F"
skip=1
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo " "
      echo "options:"
      echo "-h, --help        Show brief help"
      echo "-f, --folder      The name of the folder containing the trajectories. Default=cwd"     
      echo "-p, --only_prod   Specify T/F to only include the production trajectories in the reimaged trajectory"  
      echo "-n, --frames      Specify the number of frames to save to save single rst7 files, will be even spaced apart in production"
      exit 0
      ;;

    -f)
      shift
      if test $# -gt 0; then
        export FOLDER=$1
      else
        export FOLDER=""
      fi
      shift
      ;;
    --folder)
      shift
      if test $# -gt 0; then
        export FOLDER=$1
      else
        export FOLDER=""
      fi
      shift
      ;;
    -n)
      shift
      if test $# -gt 0; then
        export frames=$1
      else
        frames=20
      fi
      shift
      ;;
    --frames)
      shift
      if test $# -gt 0; then
        export frames=$1
      else
        frames=20
      fi
      shift
      ;;
    *)
      break
      ;;
  esac
done

systms=($(find ${HOME} -path "*/${FOLDER}*" -prune | grep -v "SEEDS" | grep -v "PROCESSED_TRAJS" | sort -V))

echo ${systms}

cnt=1
for sys in ${systms[@]}; do
   subdir_name=`echo $(basename $sys)`
   dir_name=`echo $(basename $(dirname $sys))`
   sim_fldr="${HOME}/${dir_name}/${subdir_name}"
   echo "---> Now processing ${sim_fldr} <---"
   echo ""

   if [ ! -d "$OUTFLDR/${dir_name}" ]; then
  	mkdir $OUTFLDR/${dir_name}
   fi

   cd ${sim_fldr}
    
   # Grab a topology file
   top=`ls | grep -E "psf" | tail -1`
   parm=`ls | grep -E "parm7" | tail -1`

   # START OF EDIT A <------------------------------

   # Grab production output
   prod_trajs=($(ls | grep -E "nc" | grep "Prod" | sort -V))
   prod_out=`ls | grep -E "out" | grep "Prod" | sort -V | tail -1`
   eq_out=`ls | grep -E "out" | grep "Eq" | sort -V | tail -1`
   
   echo "${prod_out} ${eq_out}"

   time_ps=`grep "TIME(PS)" ${prod_out} | tail -1 | awk '{print $6}'`
   time_total=`awk -v a="$time_ps" 'BEGIN { printf "%f\n", a/1000 }'`
   time_ps=`grep "TIME(PS)" ${eq_out} | tail -1 | awk '{print $6}'`
   time_eq=`awk -v a="$time_ps" 'BEGIN { printf "%f\n", a/1000 }'`

   save_rate=`awk -v a="$time_total" -v b="$time_eq" -v c="${frames}" 'BEGIN { printf "%f\n", (a-b)/c }'`

   time_round=`echo "$save_rate" | xargs printf "%.*f\n" "0"`


   # Build the cpptraj input file
   echo "parm ${top}" > temp.in
   for r in ${prod_trajs[@]}; do
        echo "trajin ${r}" >> temp.in
   done
   
   f=0
   for t in $(seq 1 ${frames}); do
	f=`awk -v F="$f" -v G=$time_round 'BEGIN { printf "%f\n", F+G }'`
	echo ${f}
   	int_f=`echo "$f" | xargs printf "%.*f\n" "0"`
	echo "trajout seed_ex_${dir_name}_${subdir_name}_frame_$int_f.rst7 onlyframes ${int_f}" >> temp.in
   done

   echo "go" >> temp.in

   cat temp.in

   cpptraj -i temp.in

   # copy over all the necessary files to restart the simulation
   f=0
   for t in $(seq 1 ${frames}); do
        f=`awk -v F="$f" -v G=$time_round 'BEGIN { printf "%f\n", F+G }'`
        echo ${f}
        int_f=`echo "$f" | xargs printf "%.*f\n" "0"`
	pwd
   	if [ -f "seed_ex_${dir_name}_${subdir_name}_frame_$int_f.rst7" ] ; then
		pwd
		if [ ! -d "$OUTFLDR/${dir_name}/SEED_${t}" ]; then
        		mkdir $OUTFLDR/${dir_name}/SEED_${t}
		fi
   		mv seed_ex_${dir_name}_${subdir_name}_frame_$int_f.rst7 $OUTFLDR/${dir_name}/SEED_${t}
		cp ${HOME}/SIMULATION_SCRIPTS/PRODUCTION_SEEDING/* $OUTFLDR/${dir_name}/SEED_${t}
		cp ${parm} $OUTFLDR/${dir_name}/SEED_${t}
		cp ${top} $OUTFLDR/${dir_name}/SEED_${t}
		sed -i "s/SEED/SEED${t}/g" $OUTFLDR/${dir_name}/SEED_${t}/run_amber.sh
		sed -i "s/RST7/seed_ex_${dir_name}_${subdir_name}_frame_$int_f.rst7/g" $OUTFLDR/${dir_name}/SEED_${t}/run_amber.sh
		sed -i "s/PARM7/${parm}/g" $OUTFLDR/${dir_name}/SEED_${t}/run_amber.sh
   	fi
	echo ""
   done

   cd ${HOME}

   echo ""
   cnt=`awk -v a="$cnt" 'BEGIN { printf "%f\n", a+1 }'`
done





