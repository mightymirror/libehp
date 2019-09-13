#!/bin/bash 

function main()
{
	set -e 
	# build software
	git submodule sync --recursive
	git submodule update --recursive --init

	scons -j3
	cd test
	scons 
	cd ..

	# force reinstall tools so we are always up-to-date
	yes | sudo bash -c "$(curl -fsSL allzp.zephyr-software.io/turbo/cli-install.sh)"

	# better done with boost add -q -i 
	turbo-cli boost add libehp || true
	local bid=$(turbo-cli boost list|grep libehp|cut -d"	" -f1)

	# add seeds, ignore errors if they already exist.
	turbo-cli seed add $bid cicd_testing/ehp-seed.yaml || true
	turbo-cli seed add $bid cicd_testing/ehp-seed2.yaml || true
	turbo-cli seed add $bid cicd_testing/ehp-seed3.yaml || true
	turbo-cli seed add $bid cicd_testing/ehp-seed4.yaml || true

	local vid=$(turbo-cli version add -q $bid lib/libehp.so)
	turbo-cli fuzz --fuzz-config cicd_testing/afl.yaml --app-config cicd_testing/ehp-config.yaml --ver-id $vid

	local report="$(turbo-cli log get report $vid)"

	echo "The report is: "
	echo "$report" | tee report.txt


	local declare crash_count=$(echo "$report"|shyaml get-value failing-input-count)

	if [[ $crash_count == 0 ]]; then
		echo "No crashes found"
		exit 0
	else
		# upload the report.
		local upload_report=$(curl --request POST --header "PRIVATE-TOKEN: PXLgVFpgjmmugAiHTJzx " --form "file=@report.txt" https://git.zephyr-software.com/api/v4/projects/159/uploads)

		local date=$(date)
		local mach=$(uname -a)
		local host=$(hostname)
		local md=$(echo $upload_report | shyaml get-value markdown)
		local desc=""
		read -r -d '' desc << EOM
Turbo automatically found $crash_count crashes!

Host: $host

Date: $date

Machine details: $mach

Full crash report is available here: $md

EOM
		local title="Turbo found $crash_count bugs in libEHP on $date"

		curl --request POST --data-urlencode "desc=$desc" --data-urlencode "title=$title" --header "PRIVATE-TOKEN: PXLgVFpgjmmugAiHTJzx " "https://git.zephyr-software.com//api/v4/projects/159/issues?&labels=bug&assignee_ids[]=3")

		echo "$crash_count count crashes found!"
		exit 1
	fi

}

main "$@"
