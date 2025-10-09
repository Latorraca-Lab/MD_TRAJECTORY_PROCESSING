#!/bin/bash 

# AUTHOR: Christina A. Stephens
# DATE:   20250618

# ------------------------------ PURPOSE -------------------------------------*
# Concatenate and reimage simulation trajectories systematically.             |
# For the given folder name, all directories matching                         |
# this name will be search and any trajectories found processed.              |
# Saves individual snapshot pdbs of select atoms                              |
# Snapshots will be outputed to a new folder called                           |
# "SNAPSHOTS"                                                                 |
#          [!] This is customized for amber simulation output [!]             |
#          [!] Expects the following format for simulation output:            |
#              Prod*.nc = production trajectory                               |
#              Prod*.out = production output summary file                     |   
#          [!] if this does not match you naming system please edit           |
#              the line marked "EDIT A"                                       |
#  Recommended folder organization: 					      |
#                           $CWD/SYSNAME/REPLICA_#                            |
#  And processed output will be places in:                                    |
#                           $CWD/PROCESSED_TRAJS/SYSNAME/REPLICA_#            |
#  * This analysis assumes your used the same coordinate save rate in all     |
#    production runs							      |
# ----------------------------------------------------------------------------*

# ------------------------------REQUIREMENTS ---------------------------------*
# make sure you have access to cpptraj                                        |
# it's provided by the AmberTools software                                    |
# This was written for AmberTools 25:                                         |
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
err_log="${HOME}/snapshot_warning.${str}.log"


FOLDER=`pwd`
ALIGN="F"
CENTER="F"
frames=20
master_ref=""
top=""
align_sel_ref=""
center_sel=""
align_sel=""
strip_sel=""
reformat_fn=""
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo " "
      echo "options:"
      echo "-h, --help            Show brief help"
      echo "-f, --folder          The name of the folder containing the trajectories. Default=cwd"     
      echo "-n, --frames          Specify the number of frames to save to save single pdb files, will be even spaced apart in production"
      echo "-A, --align           Specify T/F for alignment, default=F"
      echo "-a, --align_sel       Cpptraj formatted selection for centering the system in the simulation box"
      echo "-R, --ref             Full location and name of reference structure for alignment"
      echo "-r, --ref_sel         Cpptraj formatted selection for the reference for alignment. [!] must have the same number of atoms as the alignment selection"
      echo "-t, --topology        Specify the full path of the system topology, otherwise one will be located automatically"
      echo "-C, --center          Specify T/F for centering on the protein, default=F"
      echo "-c, --center_sel      Cpptraj formatted selection for centering the system in the simulation box"
      echo "-s, --strip           Cpptraj formatted selection for atom removal from the saved snapshots"
      echo "-F, --reformat_list   File containing a list of full path cpptraj-formated files for any chain/residue/atom naming/numbering modifcations post atom stripping"
      echo ""
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
    -n|--frames)
      shift
      if test $# -gt 0; then
        export frames=$1
      else
        frames=20
      fi
      shift
      ;;
    -A|--align)
      shift
      if test $# -gt 0; then
        export ALIGN=$1
      else
        export ALIGN="F"
      fi
      shift
      ;;
    -C|--center)
      shift
      if test $# -gt 0; then
        export CENTER=$1
      else
        CENTER="F"
      fi
      shift
      ;;
    -R|--ref)
      shift
      if test $# -gt 0; then
        export master_ref=$1
      else
        master_ref=""
      fi
      shift
      ;;
    -r|--ref_sel)
      shift
      if test $# -gt 0; then
        export align_sel_ref=$1
      else
        align_sel_ref=""
      fi
      shift
      ;;
    -t|--topology)
      shift
      if test $# -gt 0; then
        export top=$1
      else
        top=""
      fi
      shift
      ;;
    -c|--center_sel)
      shift
      if test $# -gt 0; then
        export center_sel=$1
      else
        center_sel=""
      fi
      shift
      ;;
    -a|--align_sel)
      shift
      if test $# -gt 0; then
        export align_sel=$1
      else
        align_sel=""
      fi
      shift
      ;;
    -s|--strip)
      shift
      if test $# -gt 0; then
        export strip_sel=$1
      else
        strip_sel=""
      fi
      shift
      ;;
    -F|--reformat_list)
      shift
      if test $# -gt 0; then
        export reformat_fn=$1
      else
        reformat_fn=""
      fi
      shift
      ;;
    *)
      break
      ;;
  esac
done


if [ ! -d "$HOME/SNAPSHOTS" ]; then
  mkdir $HOME/SNAPSHOTS
fi

OUTFLDR="$HOME/SNAPSHOTS"

echo ""
echo "=============================="
echo "Starting to Save Snapshots"
echo "=============================="
echo ""



systms=($(find ${HOME} -path "*/${FOLDER}*" -prune | grep -v "SEEDS" | grep -v "PROCESSED_TRAJS" | grep -v "SNAPSHOTS" | sort -V))


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
   echo "$top"
   if [ -z "${top}" ] ; then
         top=`ls | grep -E "psf|prmtop" | tail -1`
         echo "Found topology file: ${top}"
   fi

   # Grab production output
   prod_trajs=($(ls | grep -E "nc" | grep "Prod" | sort -V))
   prod_outs=($(ls | grep -E "out" | grep "Prod" | sort -V))

   total_steps=0
   if (( ${#prod_outs[@]} )); then
	   for PO in ${prod_outs[@]} ; do
	      timesteps=`grep "NSTEP" ${PO} | tail -1 | awk '{print $3}'`
	      total_steps=`echo "$timesteps+$total_steps" | bc -l`
	      save_rate=`grep "ntwx=" ${PO} | cut -d',' -f1 | cut -d'=' -f2`
	   done

	   n_frames=`awk -v a="$total_steps" -v b="${save_rate}" 'BEGIN { printf "%f\n", a/b }'`
	   n_frames=${n_frames%.*}

	   echo "NUMBER OF STEPS: $total_steps   NUMBER OF FRAMES: ${n_frames}"
	   save_rate=`awk -v a="$n_frames" -v b="${frames}" 'BEGIN { printf "%f\n", a/b }'`

	   time_round=`echo "$save_rate" | xargs printf "%.*f\n" "0"`
	   echo "SAVE_RATE: ${time_round}"
   else
	   echo "No production output files found, frame save rate cannot be determined  --> ${dir_name}/${subdir_name}" >> ${err_log}
   fi

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
  
   if [ "${CENTER}" == "T" ] ; then
    if [ ! -z "${center_sel}" ] ; then
        echo "center origin '${center_sel}'" >> temp.in
        echo "image origin center" >> temp.in
        echo ""
    else
        echo "Cannot center system, no centering selection provided --> ${dir_name}/${subdir_name}" >> ${err_log}
    fi
   fi

   if [ "${ALIGN}" == "T" ] ; then
     if [ ! -z "${align_sel}" ] || [  ! -z "${align_sel_ref}"  ] ; then
        echo "parm ${master_ref} [ref_parm]" >> temp.in
        echo "reference ${master_ref} parm [ref_parm] [my_ref]" >> temp.in
        echo "align ${align_sel} ${align_sel_ref} move @* ref [my_ref]" >> temp.in
     else
        echo "Cannot align system, at least one of the alignment selections not provided --> ${dir_name}/${subdir_name}" >> ${err_log}
     fi
   fi

   if [ ! -z "${strip_sel}" ] ; then
	echo "strip ${strip_sel}" >> temp.in	
   else
        echo "No selection for atom exclusion provided, all system atoms will be retained --> ${dir_name}/${subdir_name}" >> ${err_log}
   fi

   if [ ! -z "${time_round}" ] ; then
   	f=0
	for t in $(seq 1 ${frames}); do
		f=`awk -v F="$f" -v G=$time_round 'BEGIN { printf "%f\n", F+G }'`
	   	int_f=`echo "$f" | xargs printf "%.*f\n" "0"`
		if [ ${int_f} -le ${n_frames} ] ; then
			echo "trajout frame_$int_f.pdb onlyframes ${int_f}" >> temp.in
  		fi 
	done

   	echo "go" >> temp.in

   
   	cpptraj -i temp.in > ${HOME}/${dir_name}_${subdir_name}_cpptraj.${str}.log

   	# Build the cpptraj input file to re-chain stripped pdb
   	f=0
   	for t in $(seq 1 ${frames}); do
        	f=`awk -v F="$f" -v G=$time_round 'BEGIN { printf "%f\n", F+G }'`
        	int_f=`echo "$f" | xargs printf "%.*f\n" "0"`
		if [ -f "frame_$int_f.pdb" ] ; then
			if [ ! -d "$OUTFLDR/${dir_name}/${subdir_name}" ]; then
                        	mkdir $OUTFLDR/${dir_name}/${subdir_name}
                        fi
			if [ ! -z "${reformat_fn}" ] && [ -f "${reformat_fn}" ]; then
        			this_reformat=`grep "${dir_name}_${subdir_name}_" ${reformat_fn}`
				if [ ! -z "${this_reformat}" ] && [ -f "${this_reformat}" ] ; then
					echo "parm frame_$int_f.pdb" > temp_rename.in
			        	echo "loadcrd frame_$int_f.pdb name edited" >> temp_rename.in
   					# write the resid/chain corrections for cpptraj
					cat ${this_reformat} >> temp_rename.in

					echo "crdout frame_$int_f.pdb snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb" >> temp_rename.in
					echo "go" >> temp_rename.in

					n_TER=`grep "TER" frame_$int_f.pdb | wc -l | awk '{print $1}'`
					for i in $(seq 1 $n_TER) ; do

					        l=`grep "TER" frame_$int_f.pdb | head -${i} | tail -1`
     					        sed -i.BAK "s/${l}/TER/g" frame_$int_f.pdb
					done
					rm frame_$int_f.pdb.BAK

					cpptraj -i temp_rename.in > cpptraj.out
					rm cpptraj.out
					rm temp_rename.in

         	               		if [ -f "snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb" ] ; then
						mv snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb $OUTFLDR/${dir_name}/${subdir_name}
						rm frame_$int_f.pdb
	                		else
        	                	      echo "Reformating for frame ${int_f} failed --> ${dir_name}/${subdir_name}" >> ${err_log}
					      mv frame_$int_f.pdb $OUTFLDR/${dir_name}/${subdir_name}/snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb 
                			fi
				else
					echo "Stripped snapshot reformating requested but cannot locate user provided cpptraj input file from ${reformat_fn} for ${dir_name}/${subdir_name}" >> ${err_log}
					mv frame_$int_f.pdb $OUTFLDR/${dir_name}/${subdir_name}/snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb
				fi
			elif  [ ! -z "${reformat_fn}" ] && [ ! -f "${reformat_fn}" ]; then
				 echo "Stripped snapshot reformating requested but cannot locate user provided list of cpptraj inputs: ${reformat_fn}" >> ${err_log}
                                 mv frame_$int_f.pdb $OUTFLDR/${dir_name}/${subdir_name}/snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb
			else
                                mv frame_$int_f.pdb $OUTFLDR/${dir_name}/${subdir_name}/snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb
			fi

		else
			echo "Snapshot for frame ${int_f} not generated --> ${dir_name}/${subdir_name}" >> ${err_log}
		fi
   	done

   fi

   # clean up
   rm temp.in

   cd ${HOME}

   echo ""
   cnt=`awk -v a="$cnt" 'BEGIN { printf "%f\n", a+1 }'`
done

echo ""
echo "=============================="
echo "Finished Saving Snapshots"
echo "=============================="
echo ""



