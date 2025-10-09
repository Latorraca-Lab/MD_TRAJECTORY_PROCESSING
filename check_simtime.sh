#!/bin/bash 

# AUTHOR: Christina A. Stephens
# DATE:   20250618

# ------------------------------ PURPOSE -------------------------------------*
#  Find the simulation summary output files in each given sub-directory       |
#  and report if the simulation has reached the desired length (in ns).       |
#  There is also an option to relaunch the SLURM job for the simulation       |
#  if the simulation time is not met and the job is not currently running.    |
#          [!] This is customized for amber simulation output [!]             |
#          [!] Expects the following format for simulation output:            |
#              Prod*.out = production output summary file                     |   
#	       Eq*.out = production output summary file 		      |
#          [!] if this does not match you naming system please edit           |
#              the line marked "EDIT A"                                       |
#  Recommended folder organization:                                           |
#                           $CWD/SYSNAME/REPLICA_#                            |
#  And processed output will be places in:                                    |
#                           $CWD/PROCESSED_TRAJS/SYSNAME/REPLICA_#            |
#                           						      |
#  * This analysis assumes that you used the same coordinate save rate        |
#    in all production runs                                                   |
#    									      |
#  * Re-launching SLURM jobs will only work is a SLURM submission file is     |
#    already present in individual simulation subdirectories.                 |
#    									      |
#  * Also assumes ALL of your simulation output is in one folder              |
#  									      |
#  * make sure your SLURM Amber submission scripts automatiocally update      |
#    naming of repeated simulation steps (i.e. Prod and Eq) is following      |
#    the template scripting in TEMPATE_SCRIPTS_FOR_*_SIMULATIONS/             |
# ----------------------------------------------------------------------------*

echo ""
HOME=`pwd`
date_=`date`
user=`whoami`

chars='abcdefghijklmnopqrstuvwxyz0123456789'
n=5
str=""
for ((i = 0; i < n; ++i)) ; do
    str+=${chars:RANDOM%${#chars}:1}
done
err_log="${HOME}/check_warning.${str}.log"
summ_log="${HOME}/simtime_summary.${str}.txt"


FOLDER=`pwd`
RESTART="F"
STACK="F"
MAX=0
MASTER_SLURM=""
status_="N/A"

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo " "
      echo "options:"
      echo "-h, --help        show brief help"
      echo "-f, --folder      The name of the folder containing the trajectories. Default=cwd"     
      echo "-r, --restart     If the maxium simulation time has not been reached, launch the run_amber job on the cluster (T/F). Default=F"
      echo "-k, --stack       Launch a new job even if the old one is still running. Default=F"
      echo "-s, --slurm       Name of the SLURM submission script for each individual simulation"
      echo "-m, --max)        Maximum simulation time. Default=1000 ns"
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
    -r|--restart)
      shift
      if test $# -gt 0; then
        export RESTART=$1
      else
        export RESTART="F"
      fi
      shift
      ;;
    -k|--stack)
      shift
      if test $# -gt 0; then
        export STACK=$1
      else
        export STACK="F"
      fi
      shift
      ;;
    -m|--max)
      shift
      if test $# -gt 0; then
        export MAX=$1
      else
        export MAX=0
      fi
      shift
      ;;
    -s|--slurm)
      shift
      if test $# -gt 0; then
        export MASTER_SLURM=$1
      else
        export MASTER_SLURM=""
      fi
      shift
      ;;
    *)
      break
      ;;
  esac
done

systms=($(find ${HOME} -path "*/${FOLDER}*" -prune | grep -v "SEEDS" | grep -v "PROCESSED_TRAJS" | grep -v "SNAPSHOTS" | sort -V ))

echo "" > ${summ_log}
echo "DATE: ${date_}" >> ${summ_log}
echo "USER: ${user}" >> ${summ_log}
echo "" >> ${summ_log}
echo "(C) = complete" >> ${summ_log}
echo "(I) = incomplete" >> ${summ_log}
echo "N/A = data not available" >> ${summ_log}
echo "" >> ${summ_log}
echo "[1]-SYSTEM   [2]-REPLICA   [3]-SIM.TIME(ns)  [4]-TARGET-TIME(ns)  [5]-JOB-STATUS" >> ${summ_log}
echo "--------------------------------------------------------------------------------" >> ${summ_log}

cnt=1
for sys in ${systms[@]}; do
   SLURM=`echo "${MASTER_SLURM}"`
   subdir_name=`echo $(basename $sys)`
   dir_name=`echo $(basename $(dirname $sys))`
   sim_fldr="${sys}"
   echo "---> Now processing ${sim_fldr} <---"
   echo ""

   cd ${sim_fldr}

   # START OF EDIT A <------------------------------

   # Grab the last production and equilibration output
   last_prod=`ls | grep -E "out" | grep "Prod" | sort -V | tail -1`
   last_eq=`ls | grep -E "out" | grep "Eq" | sort -V | tail -1`
   
   # END OF EDIT A <--------------------------------
   
   # Print the number of completed simulation steps
   if [ ! -z ${last_prod} ] && [ ! -z ${last_eq} ]  ; then
   	time_ps=`grep "TIME(PS)" ${last_prod} | tail -1 | awk '{print $6}'`
	if [ ! -z ${time_ps} ] ; then
		time_total=`awk -v a="$time_ps" 'BEGIN { printf "%f\n", a/1000 }'` # convert ps to ns
	fi

        time_ps=`grep "TIME(PS)" ${last_eq} | tail -1 | awk '{print $6}'` 
        if [ ! -z ${time_ps} ] ; then
		time_eq=`awk -v a="$time_ps" 'BEGIN { printf "%f\n", a/1000 }'` # convert ps to ns
	fi

	#subtract off the time up to the start of production
	if [ ! -z ${time_eq} ] && [ ! -z ${time_ps} ] ; then 
        	prod_time=`awk -v a="$time_total" -v b="$time_eq" 'BEGIN { printf "%f\n", a-b }'`
        	time_round=`echo "$prod_time" | xargs printf "%.*f\n" "0"`
		echo "Total production simulation time: ${time_round} ns"
	else
		echo "Simulation time for production and or equilibration not found --> ${dir_name}/${subdir_name}" >> ${err_log}
		echo "	Check individual output files"
		time_round="N/A"
	fi
   else
	echo "Cannot locate production and/or equilibration summary output files --> ${dir_name}/${subdir_name}" >> ${err_log}
	time_round=0
   fi


   if [ -z ${SLURM} ] ; then
	l_SLURM=($(grep -H "SBATCH" *.sh | cut -d : -f1 | uniq ))
	n_slurm=`echo ${#l_SLURM[@]}`
	echo "You did not specify a SLURM submission script."
	if [ "${n_slurm}" -gt "1" ] ; then
		echo "But the follwing SLURM compatible scripts were found:"
		n=0
		for i in ${l_SLURM[@]} ; do
			n=`echo "${n}+1" | bc -l`
			echo "	[${n}] ${i}"
		done
		while :; do
                        read -p "Please select the correct script by number. " num
			if  [[ $num =~ ^[[:digit:]]+$ ]] && [[ $num -gt 0 && $num -le ${n} ]] ; then
				adjusted=`echo "${num}-1" | bc -l`
				SLURM=`echo "${l_SLURM[${adjusted}]}"`
				break
			else
				echo "Please answer with a valid number."
			fi
                done

	elif [ "${n_slurm}" -eq "1" ] ; then	
		echo "One SLURM compatible script found: ${l_SLURM[0]}"
		while :; do
    			read -p "Is this correct? (Y/N) " yn
    			case $yn in
        			[Yy]* ) SLURM=`echo "${l_SLURM[0]}"`; break;;
        			[Nn]* ) SLURM=""; break;;
        			* ) echo "Please answer yes or no.";;
    			esac
		done	
	else
		echo "No SLURM compatible scripts found, cannot determine job status --> ${dir_name}/${subdir_name}" >> ${err_log}

	fi
   fi

   if [ ! -z ${SLURM} ] && [ -f ${SLURM} ] ; then
	name_=`grep "job-name" ${SLURM} | cut -d'=' -f 2` # | head -c 8`
	running=`squeue -o "%.18i %.9P %.30j %.8u %.8T %.10M %.9l %.6D %R" | grep "${user}" | awk '{print $3}' | grep -w ${name_} | head -1`

        if [ ! -z "${running}" ] && [ "${name_}" == "${running}" ] ; then
		if [ "${MAX}" -le "${time_round}" ]  ; then
			status_="running (C) -- stop this job? ID: ${running}"
		else
			status_="running (I)"
			if [ "$STACK" == "T" ]  ; then
                            echo "Submitting a stacked job now!"
                            #sbatch ${SLURM}
                        fi
		fi
       	else
		if [ "${MAX}" -gt "${time_round}" ]  ; then
			status_="dead (I)"
	       		if [ "$RESTART" == "T" ]  ; then
		   	    echo "Relaunching the job now!"
			    #sbatch ${SLURM}
		        fi
		else
			status_="dead (C)"
		fi
	fi
   else
	echo "SLURM submission script was not found --> ${dir_name}/${subdir_name}" >> ${err_log}
   fi

   # write final report for this simulation 
   echo "${dir_name}   ${subdir_name}   ${time_round}   ${MAX}   ${status_}" >> ${summ_log}

   cd ${HOME}


   echo ""
   cnt=`awk -v a="$cnt" 'BEGIN { printf "%f\n", a+1 }'`
done





