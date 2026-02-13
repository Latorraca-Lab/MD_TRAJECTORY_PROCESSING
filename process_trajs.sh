#!/bin/bash 

# AUTHOR: Christina A. Stephens
# DATE:   20250618

# ------------------------------ PURPOSE -------------------------------------*
# Concatenate and reimage simulation trajectories systematically.    	      |
# For the given folder name, all directories matching                         |
# this name will be search and any trajectories found processed.              |
# Processed trajectories will be outputed to a new folder called              |
# "PROCESSED_TRAJS"						              |
#          [!] This is customized for amber simulation output [!]             |
#          [!] Expects the following format for simulation output:            |
#              Min*.rst(7) = minimization				      |
#	       Heat*.nc    = heating					      |		
#              Eq*.nc      = equilibration				      |
#              Prod*.nc    = production					      |
#          [!] if this does not match you naming system please edit 	      |
#              the line marked "EDIT A" 				      |
#  Recommended folder organization:                                           |
#                           $CWD/SYSNAME/REPLICA_#                            |
#  And processed output will be places in:                                    |
#                           $CWD/PROCESSED_TRAJS/SYSNAME/REPLICA_#            |
# ----------------------------------------------------------------------------*

# ------------------------------REQUIREMENTS ---------------------------------*
# make sure you have access to cpptraj 					      |
# it's provided by the AmberTools software           			      |
# This was written for AmberTools 25: 					      |
#    https://ambermd.org/AmberTools.php					      |
# See also cpptraj atom selection formating: 				      |
#    https://amberhub.chpc.utah.edu/atom-mask-selection-syntax/               |
# ----------------------------------------------------------------------------*

HOME=`pwd`


chars='abcdefghijklmnopqrstuvwxyz0123456789'
n=5
str=""
for ((i = 0; i < n; ++i)) ; do
    str+=${chars:RANDOM%${#chars}:1}
done
err_log="${HOME}/processing_warning.${str}.log"

FOLDER=`pwd`
only_prod="F"
ALIGN="F"
CENTER="F"
skip=1
master_ref=""
top=""
align_sel_ref=""
center_sel=""
align_sel=""
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo " "
      echo "options:"
      echo "-h, --help        Show brief help"
      echo "-f, --folder      The name of the folder containing the trajectories. Default=cwd"     
      echo "-p, --only_prod   Specify T/F to only include the production trajectories in the reimaged trajectory"  
      echo "-t, --topology    Specify the full path of the system topology, otherwise one will be located automatically"
      echo "-A, --align       Specify T/F for alignment, default=F"
      echo "-a, --align_sel   Cpptraj formatted selection for centering the system in the simulation box"
      echo "-R, --ref         Full location and name of reference structure for alignment"
      echo "-r, --ref_sel     Cpptraj formatted selection for the reference for alignment. [!] must have the same number of atoms as the alignment selection"
      echo "-C, --center      Specify T/F for centering on the protein, default=F"
      echo "-c, --center_sel  Cpptraj formatted selection for centering the system in the simulation box"
      echo "-s, --skip        Specify int skip rate for trajectory, default skip=1"
     
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
    -p|--only_prod)
      shift
      if test $# -gt 0; then
        export only_prod=$1
      else
        export only_prod="F"
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
    -s|--skip)
      shift
      if test $# -gt 0; then
        export skip=$1
      else
        skip=1
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
    -t|--topology)
      shift
      if test $# -gt 0; then
        export top=$1
      else
        top=""
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
    *)
      break
      ;;
  esac
done


if [ ! -d "$HOME/PROCESSED_TRAJS" ]; then
  mkdir $HOME/PROCESSED_TRAJS
fi

echo ""
echo "=============================="
echo "Trajectory Processing Starting"
echo "=============================="
echo ""

systms=($(find ${HOME} -path "*/${FOLDER}*" -prune | grep -v "SEEDS" | grep -v "PROCESSED_TRAJS" | grep -v "SNAPSHOTS" | sort -V ))

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

   if [ ! -d "$HOME/PROCESSED_TRAJS/${dir_name}/REF_TOPS" ]; then
        mkdir $HOME/PROCESSED_TRAJS/${dir_name}/REF_TOPS
   fi

   cd ${sim_fldr}
    
   # Grab a topology file
   if [ -z "${top}" ] ; then
  	 top=`ls | grep -E "psf|prmtop" | tail -1`
	 extra_top=`ls | grep -E "psf|prmtop" | tail -1`
	 if [ -z "${top}" ] ; then
	 	echo "Using found topology file: ${top}"
	 else
	        echo "ERROR! No suitable topology file found, please specify one using the -t option."
		echo "ERROR! No suitable topology file found, please specify one using the -t option." >> ${err_log}
		exit 1	
	 fi
   else
	 if [ -f "${top}" ] ; then
	 	ext="${top##*.}"
	 	if [ "${ext}" == "pdb" ] ; then
			echo "[!] You selected a pdb file as a topology for your system [!]"
			echo "-----------------------------------------------------------"
			echo "If this file does not contain CONECT lines, using this file"
			echo "to load your processed trajectory in vmd or PyMOL will cause"
			echo "visualization defects."
			
			extra_top=`ls | grep -E "psf|prmtop" | tail -1`
			if [ ! -z "${extra_top}" ] ; then
				echo "Found topology file ${extra_top} in simulation folder"
				echo "To correct the visualization defects caused by your pdb topology:"
				echo "(1) Load your pdb topology"
				echo "(2) Load ${extra_top} into the newly created molecule"
				echo "(3) Load your processed trajectory in the same molecule"
			fi
		 fi
 	 else
		echo "ERROR! Cannot locate specified topology file: ${top}"
		top=`ls | grep -E "psf|prmtop" | tail -1`
         	extra_top=`ls | grep -E "psf|prmtop" | tail -1`
         	if [ ! -z "${top}" ] ; then
                	echo "Using found topology file: ${top}"
	        else
        	        echo "ERROR! No suitable topology file found, please specify one using the -t option."
			echo "ERROR! No suitable topology file found, please specify one using the -t option." >> ${err_log}
                	exit 1
	        fi	
   
	 fi
   fi

   # START OF EDIT A <------------------------------

   # Grab the starting coordinates 
   ini_crds=`ls | grep -E "pdb|rst|rst7|inpcrd" | grep -v -E "Heat|Eq|Min|Prod" | tail -1`

   # Grab minimization output
   min=($(ls | grep -E "rst|rst7" | grep "Min" | sort -V))

   # Grab heating output
   heat=($(ls | grep -E "nc" | grep "Heat" | sort -V))

   # Grab equilibration output
   equil=($(ls | grep -E "nc" | grep "Eq" | sort -V))

   # Grab production output
   prod_trajs=($(ls | grep -E "nc" | grep "Prod" | sort -V))
   prod_out=`ls | grep -E "out" | grep "Prod" | sort -V | tail -1`

   # END OF EDIT A <-------------------------------


   # Build the cpptraj input file

   if [ ! -z "${top}" ] ; then
   	echo "parm ${top}" > temp.in
   else
	echo "Topology file with extension '.psf' not found --> ${dir_name}/${subdir_name}" >> ${err_log}
   fi
   
   if [ ! -z "${ini_crds}" ] ; then
   	echo "trajin ${ini_crds}" >> temp.in
   else
	echo "Initial coordinates with extension '.rst7' not found --> ${dir_name}/${subdir_name}" >> ${err_log}
   fi

   if [ "${only_prod}" == "F" ] ; then
   	if (( ${#min[@]} )); then
   		for r in ${min[@]}; do
			echo "trajin ${r}" >> temp.in
	   	done
	else
		echo "No minization coordinate files found --> ${dir_name}/${subdir_name}" >> ${err_log}
	fi
	
	if (( ${#heat[@]} )); then
        	for r in ${heat[@]}; do
                	echo "trajin ${r}" >> temp.in
        	done
	else
		echo "No heating coordinate files found --> ${dir_name}/${subdir_name}" >> ${err_log}
   	fi
   	
	if (( ${#equil[@]} )); then
        	for r in ${equil[@]}; do
                	echo "trajin ${r}" >> temp.in
	        done
	else
		echo "No equilibration coordinate files found --> ${dir_name}/${subdir_name}" >> ${err_log}
	fi
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
        #echo "center origin '${center_sel}'" >> temp.in
        #echo "image origin center" >> temp.in
	echo "autoimage '${center_sel}'" >> temp.in
        echo ""
    else
        echo "Cannot center system, no centering selection provided --> ${dir_name}/${subdir_name}" >> ${err_log}
    fi
   fi
	

   if [ "${ALIGN}" == "T" ] ; then
     if [ ! -z "${align_sel}" ] || [  ! -z "${align_sel_ref}"  ] ; then
        echo "parm ${master_ref} [ref_parm]" >> temp.in
        echo "reference ${master_ref} parm [ref_parm] [my_ref]" >> temp.in
        echo "align '${align_sel}' '${align_sel_ref}' move @* ref [my_ref]" >> temp.in
     else
        echo "Cannot align system, at least one of the alignment selections not provided --> ${dir_name}/${subdir_name}" >> ${err_log}
     fi
   fi

   

   
   if [ "${only_prod}" == "F" ] ; then
   	echo "trajout reimaged_min_to_prod_skip${skip}.trr offset ${skip}" >> temp.in
   else 
	echo "trajout reimaged_prod_only_skip${skip}.trr offset ${skip}" >> temp.in
   fi

   echo "go" >> temp.in

   cpptraj -i temp.in > ${HOME}/${dir_name}_${subdir_name}_cpptraj.${str}.log
   

   if [ "${only_prod}" == "T" ] ; then
   	mv reimaged_prod_only_skip${skip}.trr $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}
   else
	mv reimaged_min_to_prod_skip${skip}.trr $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}
   fi
   

   saved_tops=($(ls ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS))
   n_tops="${#saved_tops[@]}"
   if [ -f ${top} ] ; then
	local_top=`echo $(basename $top)`
	top_ext="${local_top##*.}"
	match=""
	if [ "${n_tops}" -gt "0" ] ; then
		for i in ${saved_tops[@]} ; do
			diff_wc=`diff -y --suppress-common-lines ${top} ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${i} | wc -l`
			if [ "${diff_wc}" -eq "0" ] ; then
				match="$i"
			fi
		done	
	fi
	if [ -z $match ] ; then
		if [ -f ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${local_top} ] ; then
			echo "There is already a topology names ${local_top} in PROCESSED_TRAJS/${dir_name}/REF_TOPS"
                        diff_wc=`diff -y --suppress-common-lines ${top} ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${local_top} | wc -l`
                        if [ "${diff_wc}" -eq "0" ] ; then
                                echo "And it is the same file."
                                ln -rs ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${local_top} $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}/${subdir_name}.${top_ext}
                        else
                                echo "Renaming '${local_top}' to '${subdir_name}.${top_ext}'"
                                cp ${extra_top} ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${subdir_name}.${top_ext}
                                ln -rs ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${subdir_name}.${top_ext} $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}/${subdir_name}.${top_ext}
                        fi	
		else
			cp ${top} ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS
			ln -rs ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${local_top} $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}/${subdir_name}.${top_ext}
		fi
	else
		ln -rs ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${match} $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}/${subdir_name}.${top_ext}
	fi
   fi

   saved_tops=($(ls ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS))
   n_tops="${#saved_tops[@]}"
   if [ -f ${extra_top} ] && [ "${extra_top}" != "${top}" ] ; then
   	local_top=`echo $(basename $extra_top)`
        top_ext="${local_top##*.}"
        match=""  
        if [ "${n_tops}" -gt "0" ] ; then
                for i in ${saved_tops[@]} ; do
                        diff_wc=`diff -y --suppress-common-lines ${extra_top} ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${i} | wc -l`
                        if [ "${diff_wc}" -eq "0" ] ; then
                                match="$i"
                        fi
                done
	fi
        if [ -z $match ] ; then
                if [ -f ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${local_top} ] ; then
                        echo "There is already a topology names ${local_top} in PROCESSED_TRAJS/${dir_name}/REF_TOPS"
			diff_wc=`diff -y --suppress-common-lines ${extra_top} ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${local_top} | wc -l`
                        if [ "${diff_wc}" -eq "0" ] ; then
                                echo "And it is the same file."
				ln -rs ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${local_top} $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}/${subdir_name}.${top_ext}
			else
				echo "Renaming '${local_top}' to '${subdir_name}.${top_ext}'"
				cp ${extra_top} ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${subdir_name}.${top_ext}
	                        ln -rs ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${subdir_name}.${top_ext} $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}/${subdir_name}.${top_ext}
                        fi
		else
			cp ${extra_top} ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS
		        ln -rs ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${extra_top} $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}/${subdir_name}.${top_ext}
		fi
        else
                ln -rs ${HOME}/PROCESSED_TRAJS/${dir_name}/REF_TOPS/${match} $HOME/PROCESSED_TRAJS/${dir_name}/${subdir_name}/${subdir_name}.${top_ext}
        fi     
   fi

   # clean up
   rm temp.in


   if [ ! -f "${HOME}/PROCESSED_TRAJS/${dir_name}/${subdir_name}/reimaged_min_to_prod_skip${skip}.trr" ] ; then
	echo "Expected final trajectory not generated! --> ${dir_name}/${subdir_name}" >> ${err_log}
   fi

   cd ${HOME}

   echo ""
   cnt=`awk -v a="$cnt" 'BEGIN { printf "%f\n", a+1 }'`
   
done


echo ""
echo "=============================="
echo "Trajectory Processing Complete"
echo "=============================="
echo ""

if [ -f ${err_log} ] ; then
	echo ""
	echo "[!] The following errors occured: "
	echo "-------------------------------"
	cat ${err_log}
	echo ""
	echo "Please also consult individual cppptraj log files (*_cpptraj.${str}.log) for potential errors."
	echo ""
fi




