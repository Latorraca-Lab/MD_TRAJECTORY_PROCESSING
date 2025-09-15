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

if [ ! -d "$HOME/SNAPSHOTS" ]; then
  mkdir $HOME/SNAPSHOTS
fi

OUTFLDR="$HOME/SNAPSHOTS"

center_sel="::PROD,PROE,PROF,PROG,PROH,PROI,PROA,PROB,PROC,PROJ,PROK,PROL,PROM,PRON,PROO,PROP,PROQ,PROR&!(:PE,WAT,Na+,Cl-,OL,PA,PC)"

align_sel="::PROD,PROE,PROF,PROG,PROH,PROI,PROA,PROB,PROC,PROJ,PROK,PROL@CA"
align_sel_ref="::A,B,C,D@CA"

auto_sel="WAT,Na+,Cl-"

# This script will strip everything BUT the matches to this/these selection(s)
declare -a SELS=( "::PROD,PROE,PROF,PROG,PROH,PROI,PROA,PROB,PROC,PROJ,PROK,PROL :14-145,258-348"
                 "::PROM,PRON,PROO,PROP,PROQ,PROR :14-187,303-391"
                 "::HETA :900-902" )


strip_sel="!(::PROD,PROE,PROF,PROG,PROH,PROI,PROA,PROB,PROC,PROJ,PROK,PROL,PROM,PRON,PROO,PROP,PROQ,PROR,HETA)"


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
      echo "-n, --frames      Specify the number of frames to save to save single rst7 files, will be even spaced apart in production"
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
    -n|--frames)
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

systms=($(find ${HOME} -path "*/${FOLDER}*" -prune | grep -v "SEEDS" | grep -v "PROCESSED_TRAJS" | grep -v "SNAPSHOTS" | sort -V))

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
   pdb=`ls | grep -E "pdb" | tail -1`


   # Grab production output
   prod_trajs=($(ls | grep -E "nc" | grep "Prod" | sort -V))
   prod_outs=($(ls | grep -E "out" | grep "Prod" | sort -V))

   total_steps=0
   for PO in ${prod_outs[@]} ; do
      timesteps=`grep "NSTEP" ${PO} | tail -1 | awk '{print $3}'`
      total_steps=`echo "$timesteps+$total_steps" | bc -l`
   done

   n_frames=`awk -v a="$total_steps" 'BEGIN { printf "%f\n", a/50000 }'` # HARD SET TRAJ SAVE RATE [!]

   echo "NUMBER OF STEPS: $total_steps   NUMBER of==OF FRAMES: ${n_frames}"
   save_rate=`awk -v a="$n_frames" -v b="${frames}" 'BEGIN { printf "%f\n", a/b }'`

   time_round=`echo "$save_rate" | xargs printf "%.*f\n" "0"`
   echo "SAVE_RATE: ${time_round}"


   # Build the cpptraj input file to save stripped pdb
   echo "parm ${top}" > temp.in
   for r in ${prod_trajs[@]}; do
        echo "trajin ${r}" >> temp.in
   done
   
   echo "center origin '${center_sel}'" >> temp.in
   echo "image origin center" >> temp.in
   echo "parm ${HOME}/${master_ref} [ref_parm]" >> temp.in
   echo "reference ${HOME}/${master_ref} parm [ref_parm] [my_ref]" >> temp.in
   echo "align ${align_sel} ${align_sel_ref} move @* ref [my_ref]" >> temp.in
   echo "strip ${strip_sel}" >> temp.in
   f=0
   for t in $(seq 1 ${frames}); do
	f=`awk -v F="$f" -v G=$time_round 'BEGIN { printf "%f\n", F+G }'`
   	int_f=`echo "$f" | xargs printf "%.*f\n" "0"`
	echo "trajout frame_$int_f.pdb onlyframes ${int_f}" >> temp.in
   done

   echo "go" >> temp.in
   cat temp.in
   cpptraj -i temp.in

   # Build the cpptraj input file to re-chain stripped pdb
   f=0
   for t in $(seq 1 ${frames}); do
        f=`awk -v F="$f" -v G=$time_round 'BEGIN { printf "%f\n", F+G }'`
        int_f=`echo "$f" | xargs printf "%.*f\n" "0"`
        echo "parm frame_$int_f.pdb" > temp_rename.in
        echo "loadcrd frame_$int_f.pdb name edited" >> temp_rename.in
   	# write the resid/chain corrections for cpptraj
	echo "change crdset edited chainid to C of @1-5341" >> temp_rename.in
	echo "change crdset edited chainid to A of @5342-10675" >> temp_rename.in
	echo "change crdset edited chainid to B of @10676-16016" >> temp_rename.in
	echo "change crdset edited chainid to D of @16017-21253" >> temp_rename.in
	echo "change crdset edited chainid to E of @21254-26451" >> temp_rename.in
	echo "change crdset edited chainid to F of @26452-31649" >> temp_rename.in
	echo "change crdset edited chainid to X of @31650-32037" >> temp_rename.in
	echo "change crdset edited oresnums of @31650-31699 min 900 max 900" >> temp_rename.in
	echo "change crdset edited oresnums of @31700-31728 min 901 max 901" >> temp_rename.in
	echo "change crdset edited oresnums of @31729-31778 min 902 max 902" >> temp_rename.in
	echo "change crdset edited oresnums of @31779-31828 min 903 max 903" >> temp_rename.in
	echo "change crdset edited oresnums of @31829-31857 min 904 max 904" >> temp_rename.in
	echo "change crdset edited oresnums of @31858-31907 min 905 max 905" >> temp_rename.in
	echo "change crdset edited oresnums of @31908-31957 min 906 max 906" >> temp_rename.in
	echo "change crdset edited oresnums of @31958-31986 min 907 max 907" >> temp_rename.in
	echo "change crdset edited oresnums of @31987-32037 min 908 max 908" >> temp_rename.in

	echo "crdout frame_$int_f.pdb snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb" >> temp_rename.in
	echo "go" >> temp_rename.in
        cat temp_rename.in

        cpptraj -i temp_rename.in
	rm frame_$int_f.pdb
   done

   f=0
   for t in $(seq 1 ${frames}); do
        f=`awk -v F="$f" -v G=$time_round 'BEGIN { printf "%f\n", F+G }'`
        int_f=`echo "$f" | xargs printf "%.*f\n" "0"`
        if [ -f "snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb" ] ; then
                if [ ! -d "$OUTFLDR/${dir_name}/${subdir_name}" ]; then
                        mkdir $OUTFLDR/${dir_name}/${subdir_name}
                fi
                mv snapshot_ex_${dir_name}_${subdir_name}_frame_$int_f.pdb $OUTFLDR/${dir_name}/${subdir_name}
        fi
   done

   cd ${HOME}

   echo ""
   cnt=`awk -v a="$cnt" 'BEGIN { printf "%f\n", a+1 }'`
done





