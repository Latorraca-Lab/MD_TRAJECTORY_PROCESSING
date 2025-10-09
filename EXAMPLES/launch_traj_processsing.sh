#!/bin/bash
# Author:   Christina Stephens
# Date:     20250912
# Purpose:  Launch AMEBR trajectory processing for all-atom LRRC8 simulation - Naomi's version

HOME=`pwd`

master_ref="${HOME}/PACKMOL_prep_ref_box_centered.pdb"
master_top="${HOME}/v4_system_ref.pdb"

# cpptraj formated selection for centering the system in the simulation box
center_sel="(::A,B,C,D,E,F@CA)"

# cpptraj formated selection for the simulation to align to the reference
align_sel="::A,B,C,D@CA"

# cpptraj formation selection for the reference for alignment
# [!] must have the same number of atoms as $align_sel 
align_sel_ref="::A,B,C,D@CA"


strip_sel="!(::A,B,C,D|:PEE)"

# Process the trajectory, skipping every 5 frames
bash process_trajs.sh -f "LRRC8AD_J894_Model129_Ref055_v6_CYX-fixed/run_" -p "F" -A "T" -a ${align_sel} -R ${master_ref} -t ${master_top} -r ${align_sel_ref} -C "T" -c ${center_sel} -s "5"


# save 100 snapshots evenly spaced across the snapshot
bash save_snapshots.sh -f "LRRC8AD_J894_Model129_Ref055_v6_CYX-fixed/run_" -A "T" -a ${align_sel} -R ${master_ref} -t ${master_top} -r ${align_sel_ref} -C "T" -c ${center_sel} -n 100 -s ${strip_sel} -F ${HOME}/list_of_cpptraj_reformating_inputs.txt 
