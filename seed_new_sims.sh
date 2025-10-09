#!/bin/bash 

# AUTHOR: Christina A. Stephens 
# DATE:   20250618
   
# ------------------------------ PURPOSE -------------------------------------*
# 1. Extract the user specified full system snapshot (choose by sim. time)    |
# 2. Generate a new folder with the snaphot and all necesarry components to   |
#    start a new simulation (seed) from the snapshot.                         |
#          [!] This is customized for amber simulation output [!]             |
#          [!] Expects the following format for simulation output:            |
#              Prod*.nc = production output trajectory			      |
#              Prod*.out = production output summary file                     |   
#          [!] if this does not match you naming system please edit           |
#              the line marked "EDIT A"                                       |
#  Recommended folder organization:                                           |
#                           $CWD/SYSNAME/REPLICA_#                            |
#  And processed output will be places in:                                    |
#                           $CWD/PROCESSED_TRAJS/SYSNAME/REPLICA_#            |
#                                                                             |
#  * This analysis assumes that you used the same coordinate save rate        |
#    in all production runs                                                   |
#                                                                             |
#  * Also assumes ALL of your simulation output is in one folder              |
#                                                                             |
# ----------------------------------------------------------------------------*
        
# ------------------------------REQUIREMENTS ---------------------------------*
# make sure you have access to cpptraj                                        |
# it's provided by the AmberTools software                                    |
# This was written for AmberTools 24/25:                                         |
#    https://ambermd.org/AmberTools.php                                       |
# See also cpptraj atom selection formating:                                  |
#    https://amberhub.chpc.utah.edu/atom-mask-selection-syntax/               |
# ----------------------------------------------------------------------------*
   
HOME=`pwd`
   
   
chars='abcdefghijklmnopqrstuvwxyz0123456789'
n=5
str=""
for ((i = 0; i < n; ++i)) ; do
    str+=${chars:RANDOM%${#chars}:1}
done
err_log="${HOME}/seeding_warning.${str}.log"


FOLDER=""
TIME="1"
SIM_VERSION="Amber24"
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo " "
      echo "options:"
      echo "-h, --help        Show brief help"
      echo "-f, --folder      The name of the folder containing the trajectories. Default=cwd"     
      echo "-t, --time        Specify simulation time for the snapshot (post equilibration). Default=1"
      echo "-s, --version     Which simulation engine specifications do you want to use. Default=Amber24"   
      exit 0
      ;;

    -f|--folder)
      shift
      if test $# -gt 0; then
        export FOLDER=$1
      else
        export FOLDER=`pwd`
      fi
      shift
      ;;
    -t|--time)
      shift
      if test $# -gt 0; then
        export TIME=$1
      else
        TIME=1
      fi
      shift
      ;;
    *)
      break
      ;;
  esac
done

OUTFLDR="$HOME/SEEDS"

systms=($(find ${HOME} -path "*/${FOLDER}*" -prune | grep -v "SEEDS" | grep -v "PROCESSED_TRAJS" | grep -v "SNAPSHOTS" | sort -V))

cnt=1
for sys in ${systms[@]}; do
   subdir_name=`echo $(basename $sys)`
   dir_name=`echo $(basename $(dirname $sys))`
   sim_fldr="${HOME}/${dir_name}/${subdir_name}"
   echo "---> Now processing ${sim_fldr} <---"
   echo ""

   cd ${sim_fldr}
    
   # START OF EDIT A <------------------------------

   # Grab a topology file
   top=`ls | grep -E "parm7|psf|prmtop" | tail -1`

   # Grab the production output summaries and trajectories
   prod_trajs=($(ls | grep -E "nc" | grep "Prod" | sort -V))
   prod_outs=($(ls | grep -E "out" | grep "Prod" | sort -V))

   # END OF EDIT A <--------------------------------

   # Find the frame that corresponds to the specified 
   # simulation time
   
   # Build the cpptraj input file to save stripped pdb
   if [ ! -z "${top}" ] ; then
        echo "parm ${top}" > temp.in
   else
        echo "Topology file with extension '.psf' not found --> ${dir_name}/${subdir_name}" >> ${err_log}
   fi

   if (( ${#prod_trajs[@]} )); then
        for r in ${prod_trajs[@]}; do
                echo "trajin ${r}" >> temp.in
        done
   else
        echo "No production coordinate files found --> ${dir_name}/${subdir_name}" >> ${err_log}
   fi


   total_steps=0
   if (( ${#prod_outs[@]} )); then
           for PO in ${prod_outs[@]} ; do
              timesteps=`grep "NSTEP" ${PO} | tail -1 | awk '{print $3}'`
              total_steps=`echo "$timesteps+$total_steps" | bc -l`
              save_rate=`grep "ntwx=" ${PO} | cut -d',' -f1 | cut -d'=' -f2`
	      dt=`grep "dt=" ${PO} | cut -d',' -f1 | cut -d'=' -f2`
           done
       	
	   time_per_frame=`awk -v b="${save_rate}" -v c="${dt}" 'BEGIN { printf "%f\n", (b*c)/1000 }'` # simulation time/frame in ns
	   n_frames=`awk -v a="$total_steps" -v b="${save_rate}" 'BEGIN { printf "%f\n", a/b }'`
	   
	   pre_frame=`awk -v a="$TIME" -v b="${time_per_frame}" 'BEGIN { printf "%f\n", a/b }'`
	   FRAME=`echo "$pre_frame" | xargs printf "%.*f\n" "0"` 
   	   echo "Will save a SEED from frame ${FRAME}"
	   echo "trajout seed_ex_${dir_name}_${subdir_name}_frame_$FRAME.rst7 onlyframes ${FRAME}" >> temp.in
	   echo "go" >> temp.in
	   echo "Generating snapshot now..."
   	   cpptraj -i temp.in > ${HOME}/${dir_name}_${subdir_name}_cpptraj.${str}.log
	   rm temp.in

	   # copy over all the necessary files to restart the simulation
	   if [ -f "seed_ex_${dir_name}_${subdir_name}_frame_${FRAME}.rst7" ] ; then
           	
	      	echo "Snapshot generation completed."

		if [ ! -d "$HOME/SEEDS" ] ; then
     		     mkdir $HOME/SEEDS
   		fi

	   	if [ ! -d "$OUTFLDR/${dir_name}" ]; then
        		mkdir $OUTFLDR/${dir_name}
   		fi 

		n_seeds=`ls $OUTFLDR/${dir_name} | grep SEED | wc -l`
		seed_number=`echo "${n_seeds}+1" | bc -l`

		if [ ! -d "$OUTFLDR/${dir_name}/SEED_${seed_number}" ]; then
                        mkdir $OUTFLDR/${dir_name}/SEED_${seed_number}
                fi

		echo "This simulation was seeded from simulation: ${dir_name}/${subdir_name}" > $OUTFLDR/${dir_name}/SEED_${seed_number}/SEED.README
		echo "At frame: ${FRAME}" >> $OUTFLDR/${dir_name}/SEED_${seed_number}/SEED.README
		echo "Which best corresponds to: ${TIME} ns of production simulation" >> $OUTFLDR/${dir_name}/SEED_${seed_number}/SEED.README

                mv seed_ex_${dir_name}_${subdir_name}_frame_$FRAME.rst7 $OUTFLDR/${dir_name}/SEED_${seed_number}
                cp ${HOME}/TEMPLATE_SCRIPTS_FOR_MEMBRANE_SIMULATIONS_${SIM_VERSION}/* $OUTFLDR/${dir_name}/SEED_${seed_number}
                cp ${top} $OUTFLDR/${dir_name}/SEED_${seed_number}
                sed -i "s/SEED/SEED${seed_number}/g" $OUTFLDR/${dir_name}/SEED_${seed_number}/run_amber.sh
                sed -i "s/RST7/seed_ex_${dir_name}_${subdir_name}_frame_$FRAME.rst7/g" $OUTFLDR/${dir_name}/SEED_${seed_number}/run_amber.sh
                sed -i "s/PARM7/${top}/g" $OUTFLDR/${dir_name}/SEED_${seed_number}/run_amber.sh
		rm ${HOME}/${dir_name}_${subdir_name}_cpptraj.${str}.log
	   else
		echo "Failed to generate snapshot, please consult the cpptraj log file:" >> ${err_log}
		echo "${HOME}/${dir_name}_${subdir_name}_cpptraj.${str}.log" >> ${err_log}
	   fi

   else
           echo "No production output files found, frame to save could not be determined  --> ${dir_name}/${subdir_name}" >> ${err_log}
   fi
   
   cd ${HOME}

   echo ""
   cnt=`awk -v a="$cnt" 'BEGIN { printf "%f\n", a+1 }'`
done


echo ""
echo "=============================="
echo "Finished Seeding from $TIME ns"
echo "=============================="
echo ""



