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
	yes | sudo bash -c "$(curl -fsSL opensrc.pages.zephyr-software.com/turbo/cli-install.sh)"
	sudo bash -c 'echo core >/proc/sys/kernel/core_pattern'

	# docker run starts a container.  since we started with --restart, it should come back up
	# docker run -d --restart unless-stopped -p 55155:55155 git.zephyr-software.com:4567/opensrc/turbo/turbo:latest

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
	local proj_id=$CI_PROJECT_ID
	local proj_urld=$CI_PROJECT_URL

	echo "The report is: "
	mkdir -p artifacts
	echo "$report" | tee artifacts/fuzz_report.yaml

	local declare crash_count=$(echo "$report"|shyaml get-value failing-input-count)

	if [[ $crash_count == 0 ]]; then
		echo "No crashes found"
		echo "See [job details]($proj_url/-/jobs/$CI_JOB_ID), look at the artifacts for the full report."
		exit 0
	else
		# upload the report.
		#local upload_report=$(curl --request POST --header "PRIVATE-TOKEN: PXLgVFpgjmmugAiHTJzx " --form "file=@artifacts/fuzz_report.yaml" https://git.zephyr-software.com/api/v4/projects/$proj_id/uploads)
		local date=$(date)
		local mach=$(uname -a)
		local host=$(hostname)
		local md=$(echo $upload_report | shyaml get-value markdown)
		local desc=""
		read -r -d '' desc || true << EOM
Turbo automatically found $crash_count crashes!

Host: $host

Date: $date

Machine details: $mach

See [job details]($proj_url/-/jobs/$CI_JOB_ID), look at the artifacts for the full report.
and [pipeline details]($proj_url/pipelines/$CI_PIPELINE_ID).

EOM
		local title="Turbo found $crash_count bugs in libEHP on $date"
		local assignee_id="$GITLAB_USER_ID"

		# finally post an issue
		# curl --request POST --data-urlencode "description=$desc" --data-urlencode "title=$title" --header "PRIVATE-TOKEN: PXLgVFpgjmmugAiHTJzx " "https://git.zephyr-software.com//api/v4/projects/$proj_id/issues?&labels=bug,turbo&assignee_ids[]=$assignee_id"

		echo "$crash_count count crashes found!"
		exit 1
	fi

}

main "$@"
