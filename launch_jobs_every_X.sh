


X=100

for i in $(seq 1 ${X}); do
	echo "Waiting to launch the next job..."
	sleep 30m

	rm simtime_summary.*txt 

	bash check_simtime.sh -f <you-simulation-folder> -r T -k F -s run_amber_HMR.sh -m 10000

done


