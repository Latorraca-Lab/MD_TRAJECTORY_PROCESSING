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

if [ ! -d "$HOME/PROCESSED_TRAJS" ]; then
  mkdir $HOME/PROCESSED_TRAJS
fi

FOLDER=""
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo " "
      echo "options:"
      echo "-h, --help        show brief help"
      echo "-f, --folder      The name of the folder containing the trajectories. Default=cwd"     
      echo "-r, --restart     If the maxium simulation time has not been reached, launch the run_amber job on the cluster (T/F). Default=F"
      echo "-m, --max)        Maximum simulation time. Default=1000 ns"
      exit 0
      ;;

    -f|--folder)
      shift
      if test $# -gt 0; then
        export FOLDER=$1
      else
        export FOLDER=""
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
    -m|--max)
      shift
      if test $# -gt 0; then
        export MAX=$1
      else
        export MAX="1000"
      fi
      shift
      ;;
    *)
      break
      ;;
  esac
done

systms=($(find ${HOME} -path "*/${FOLDER}*" -prune | grep -v "PROCESSED_TRAJS" | sort -V))

cnt=1
for sys in ${systms[@]}; do
   subdir_name=`echo $(basename $sys)`
   dir_name=`echo $(basename $(dirname $sys))`
   sim_fldr="${sys}"
   echo "---> Now processing ${sim_fldr} <---"
   echo ""

   if [ ! -d "$HOME/PROCESSED_TRAJS/${dir_name}" ]; then
  	mkdir $HOME/PROCESSED_TRAJS/${dir_name}
   fi

   if [ ! -d "$HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}" ]; then
        mkdir $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}
   fi

   if [ "${cnt}" == "1" ] ; then
        echo "REPLICA   SIM. TIME(ns)" > $HOME/PROCESSED_TRAJS/${dir_name}/simtime_summary.txt
   fi

   cd ${sim_fldr}
   
   # Grab production output
   any_prod=`ls | grep -E "out" | grep "Prod"`
   # Print the number of completed simulation steps
   if [ "$any_prod" != "" ]  ; then
   	prod_out=`ls | grep -E "out" | grep "Prod" | sort -V | tail -1`
   	time_ps=`grep "TIME(PS)" ${prod_out} | tail -1 | awk '{print $6}'`
        time_total=`awk -v a="$time_ps" 'BEGIN { printf "%f\n", a/1000 }'`
	
	any_eq=`ls | grep -E "out" | grep "Eq"`
   	if [ "$any_eq" != "" ]  ; then
		eq_out=`ls | grep -E "out" | grep "Eq" | sort -V | tail -1`
        	time_ps=`grep "TIME(PS)" ${eq_out} | tail -1 | awk '{print $6}'`
        	time_eq=`awk -v a="$time_ps" 'BEGIN { printf "%f\n", a/1000 }'`
        	prod_time=`awk -v a="$time_total" -v b="$time_eq" 'BEGIN { printf "%f\n", a-b }'`
	else 
		prod_time=${time_total}
	fi

        time_round=`echo "$prod_time" | xargs printf "%.*f\n" "0"`
	echo "Total production simulation time: ${time_round} ns"
	echo "${subdir_name} ${time_round}" >> $HOME/PROCESSED_TRAJS/${dir_name}/simtime_summary.txt
       
        if [ -f "run_amber.sh" ] ; then
           name_=`grep "job-name" run_amber.sh | cut -d'=' -f 2 | head -c 8`
           running=`squeue | grep "${name_}" | awk '{print $1}'`
	   if [ ! -z "${running}" ]; then
              echo "This job (${name_}) is already running, check back later :)"
	      if [ "${MAX}" -le "${time_round}" ]  ; then
	         echo "But you've maxed out your desired simulation time, consider stopping the job."
	      fi
           else
	      if [ "${MAX}" -gt "${time_round}" ]  ; then
	         echo "This job (${name_}) is currently not running but has not reached the max. sim. time"
	         if [ "$RESTART" == "T" ]  ; then
	   	    echo "Relaunching the job now!"
		    sbatch run_amber.sh
	         fi
	      fi
           fi
	fi
   else
 	echo "This simulation does not have any production simulation data"
   	echo "${subdir_name} NONE" >> $HOME/PROCESSED_TRAJS/${dir_name}/simtime_summary.txt
   fi


   cd ${HOME}


   echo ""
   cnt=`awk -v a="$cnt" 'BEGIN { printf "%f\n", a+1 }'`
done





