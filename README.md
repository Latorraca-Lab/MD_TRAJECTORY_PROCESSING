# MD_TRAJECTORY_PROCESSING_PRIVATE
Scripts for automating MD simulation trajectory concatenation, alignment, centering, and wrapping (PRIVATE)

Will use this as editing/staging space for scripts which will       
eventually be pushed to a public repo either on my own github or on the  
Latorraca github.                                                   


-------------------------------------------------------------------
This repo should contain the following:
-------------------------------------------------------------------

1. process_trajs.sh --> Save a new NetCDF trajectory by concatenateing seperate simulation trajectories
                        with option to adjust save rate, center, align and exclude pre-production data.

2. save_snapshots.sh

3. seed_new_sims.sh

4. check_simtime.sh

5. TEST/ ------------->  An example/test dataset and input scripts


-------------------------------------------------------------------
To test that the processing is working in your system:
-------------------------------------------------------------------
   1. navigate to the TEST/ folder
   2. Run the test:
        $ bash test_traj_processing.sh

   3. This should have created three new folders:
        SEEDS/
        SNAPSHOTS/
        PROCESSED_TRAJS/

