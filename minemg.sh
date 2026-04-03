#!/bin/bash

### SCREEN TROUBLESHOOTING
# Sometimes I end up with the following error when starting the server:
# Cannot make directory '/run/screen': Permission denied
# Maybe I'll find a way to autofix that issue, for now I just manually use this command:
# sudo /etc/init.d/screen-cleanup start

#############################################################
####################### SUM VARIABLES #######################
#############################################################

mcServerUser="minecraft"
mcServiceName="minecraft_server"

serviceDir="/opt/minecraft"
serverDir="${serviceDir}/server"
serverFile="${serverDir}/server.jar"
javaDir="${serviceDir}/java"
worldDir="${serviceDir}/world"
tmpDirJSON="/tmp/minemg_tmp"
version_manifest="${tmpDirJSON}/version_manifest.json"
release_file="${tmpDirJSON}/release_file.json"

javaCompatible=0

INITIAL_MEMORY="1024M"
MAXIMUM_MEMORY="4096M"
WORLD_NAME="mc-server"

startMC=0
updateServer=0
serverStop=0
skipCheck=0
forceDownload=0

versionRegex="\b[0-9]+(\.[0-9]+){2}\b"

#############################################################
#############################################################
#############################################################

### COLORS

RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
GREEN="\033[1;32m"
#PURPLE="\033[1;35m"
#CYAN="\033[1;36m"
#UND_CYAN="\033[1;4;36m"
LIGTH_GRAY="\033[0;37m"
RESET="\033[0m"

### HELP PAGE

helpPage="MineManager is a bash wrapper developed to manage Minecract servers
This tool is used to start/stop the server, update the server.jar file, 
send admin commands, check on server status and clear server logs

Made with love by c0rgo (https://github.com/spacec0rgo)

Usage:
        ./minemg.sh [flags] ...
    
Flags:
        -h, --help				print this help page
        --start					start the MC server
        --stop					stop the MC server
        -c, --command <command>			send quote-enclosed command [eg. 'say Hello'] to the MC server
        -up, --update				update server.jar file if a new release is available
        --status				check MC server status
        -vv, --versions <num|all>		retrieve number of MC server versions available to install
        -iv, --install-version <version>	install a specific server release version
        -sku, --skip-up-check			skip automatic check for new releases
        -fd, --force-download			force download server.jar even if versions match
        -bak, --backup <path>			create a backup of the MC server world
        -cls, --clean-logs			remove old logs from the Java logs directory"

### FUNCTIONS

function printHelp () {
        echo "$helpPage"
}

function handleFlags () {
        if [ $# -eq 0 ]; then
        	echo -e "${BLUE}[#] Invoked MC setup ${RESET}"
        else
        	while [ $# -gt 0 ]; do
                        case $1 in
                                -h | --help)
                                        printHelp
                                        exit 0
                                        shift;;
				--start)
                                        startMC=1
                                        ;;
				--stop)
                                        serverStop=1
                                        serverCommand "stop"
                                        ;;
                                -c | --command)
                                        serverCommand "$2"
                                        shift;;
                                -up | --update)
                                        updateServer=1
                                        ;;
				--status)
                                        if [ $(serverStatus) -eq 1 ]; then
						echo -e "${GREEN}[+] MC server is up and running ${RESET}"
						echo -e "${BLUE}[+] Server version: ${LIGTH_GRAY}$(serverVersion) ${RESET}"
						exit 0
					else
						echo -e "${BLUE}[+] No active MC server instance ${RESET}"
						exit 0
					fi
                                        ;;
                                -vv | --versions)
                                        num_re='^[0-9]+$'
                                        if [[ "$2" == "all" ]]; then
                                        	retrieveVersions "0"
					elif [[ "$2" =~ ${num_re} ]]; then
						retrieveVersions "$2"
					elif [[ -z "$2" ]]; then
						retrieveVersions "0"
					else
						echo "Error: Invalid option \"$2\""
					fi
					printHelp
					exit 1
                                        shift;;
				-iv | --install-version)
					installVersion="$2"
                                        if [ -z $installVersion ]; then
						echo -e "${YELLOW}[!] No release version provided ${RESET}"
				        	echo -e "${RED}[\u00d7] Aborted ${RESET}"
						exit 1
					fi
                                        shift;;
				-sku |--skip-up-check)
                                        skipCheck=1
                                        ;;
                                -fd | --force-donwload)
                                        forceDownload=1
                                        ;;
                                -bak | --backup)
                                        createBackup "$2"
                                        shift;;
                                -cls | --clean-logs)
                                        removeLogs
                                        ;;
                                ### Wildcard
                                *)
                                        if [ ! -f "$1" ]; then
                                                echo "Invalid option: $1" >&2
                                                echo -n $'\n'
                                                printHelp
                                                exit 1
                                        else
                                                filename="$1"
                                        fi
                                        ;;
                        esac
                        shift
                done
        fi
}

function removeLogs() {
	echo -e "${BLUE}[+] Removing old '.gz' logs ${RESET}"
	rm -f "${javaDir}"/logs/*.log.gz > /dev/null 2>&1
	exit 0
}

function createBackup() {
	local backupPath="$1"
	# First of all, check that the variable contains a value
	# We first need to check if there is an instance of the MC server
	if [ -z "${backupPath}" ]; then
        echo -e "${YELLOW}[!] No backup path provided ${RESET}"
        echo -e "${RED}[\u00d7] Aborted ${RESET}"
		exit 1
	fi
	# backup must be performed when the server is stopped
	if [ $(serverStatus) -eq 1 ]; then
        echo -e "${YELLOW}[!] Cannot create backup when server is running ${RESET}"
        echo -e "${YELLOW}[+] Stop the MC server and retry ${RESET}"
		exit 1
	fi
	# Then we need to confirm the world directory indeed exists
	if [[ ! -d "${worldDir}/${WORLD_NAME}" ]]; then
		echo -e "${YELLOW}[!] Found no world named ${LIGTH_GRAY}$WORLD_NAME${YELLOW} inside ${LIGTH_GRAY}$worldDir ${RESET}"
        echo -e "${RED}[\u00d7] Aborted ${RESET}"
		exit 1
	fi
	# And finally, we want to confirm the backup path exists and is a directory
	if [ ! -d "$backupPath" ]; then
		if [ -f "$backupPath" ]; then
			echo -e "${YELLOW}[!] Backup path ${LIGTH_GRAY}$backupPath${YELLOW} is not a directory ${RESET}"
		else
			echo -e "${YELLOW}[!] Backup directory ${LIGTH_GRAY}$backupPath${YELLOW} does not exists ${RESET}"
		fi
        echo -e "${RED}[\u00d7] Aborted ${RESET}"
		exit 1
	fi
	
	# Now execute the command as the service user and check whether it succeed or not
	local backupName="$(date "+%Y-%m-%d")_${WORLD_NAME}_bak.tar.gz"
	tar -czf ${backupName} -C "${backupPath}" "${worldDir}/${WORLD_NAME}" > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo -e "${BLUE}[+] Successfully created ${LIGTH_GRAY}$backupName${YELLOW} at ${LIGTH_GRAY}$backupPath ${RESET}"
		chown "${mcServerUser}:${mcServerUser}" "${backupPath}/${backupName}"
	else
		echo -e "${YELLOW}[!] Error creating ${LIGTH_GRAY}$backupName${YELLOW}: something went wrong ${RESET}"
	fi
	exit 0
}

function serverCommand() {
        # Send commands to the MC world server
        local mc_cmd="$1"
        # Check that the command contains some value
        # would not disturb contacting the server for nothing
        if [ -z "${mc_cmd}" ]; then
        	echo -e "${YELLOW}[!] No MC server command provided ${RESET}"
        	echo -e "${RED}[\u00d7] Aborted ${RESET}"
			exit 1
		fi
        su ${mcServerUser} -s '/bin/bash' -c "screen -L -S ${mcServiceName} -p 0 -X stuff \"${mc_cmd}$(printf \\r)\"" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
        	if [ $(serverStatus) -eq 1 ] && [ "$serverStop" -eq 1 ]; then
	        	echo -e "${BLUE}[+] Stopping MC server ... ${RESET}"
				exit 0
		fi
        	echo -e "${BLUE}[+] Command '${mc_cmd}' sent successfully ${RESET}"
        	exit 0
        else
        	echo -e "${YELLOW}[!] Error sending '${mc_cmd}' to server ${RESET}"
			echo -e "${YELLOW}[+] Is the server running? ${RESET}"
			exit 1
        fi
}

function retrieveVersions() {
	local nums="$1"
	local manifestVersRe="^[0-9]+(\.[0-9]+){2}$"
	if [ ${nums} -eq 0 ]; then
		echo -e "${BLUE}[+] Retrieving all MC server versions available to install ${RESET}"
		curl --silent https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r '.versions[].id' | grep -E "${manifestVersRe}"
	else
		# strip excessive zeroes
		realNums="$(echo $nums | sed 's/^0\+//')"
		echo -e "${BLUE}[+] Retrieving last ${realNums} MC server versions available to install ${RESET}"
		curl --silent https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r '.versions[].id' | grep -E "${manifestVersRe}" | head -n "${realNums}"
	fi
	exit 0
}

function versionCheck() {
	# Single download of JSON files
	# this is a lot more stealthy
	echo -e "${BLUE} [+] Fetching version manifest ${RESET}"
	curl --silent "https://launchermeta.mojang.com/mc/game/version_manifest.json" -o "${version_manifest}" 2>/dev/null
	checkFile "${version_manifest}"

	if [ -z "$installVersion" ]; then
		echo -e "${BLUE} [+] Retrieving latest release version ${RESET}"
		local releaseVersion="$(jq -r '.latest.release' ${version_manifest})"
		echo -e "${BLUE} [+] Found release ${LIGTH_GRAY}$releaseVersion ${RESET}"
		local releaseIndex=$(jq -r ".versions | to_entries | .[] | select(.value.id == \"${releaseVersion}\") | .key" "${version_manifest}")
		local releaseURL=$(jq -r ".versions[${releaseIndex}].url" "${version_manifest}")
	else
		echo -e "${BLUE} [+] Retrieving details about release version ${LIGTH_GRAY}$installVersion ${RESET}"
		local releaseIndex=$(jq -r ".versions | to_entries | .[] | select(.value.id == \"${installVersion}\") | .key" "${version_manifest}" 2>/dev/null)
		if [ ! -z "$releaseIndex" ]; then
	        	echo -e "${BLUE} [+] Found release ${LIGTH_GRAY}$installVersion ${RESET}"
	        	local releaseURL=$(jq -r ".versions[${releaseIndex}].url" "${version_manifest}")
	        else
	        	echo -e "${YELLOW} [!] No release version ${LIGTH_GRAY}$installVersion${YELLOW} found ${RESET}"
			isRelease=0
			return
	        fi
	fi

	# Download the latest release JSON from the release URL
	echo -e "${BLUE} [+] Retrieving release information ${RESET}"
	curl --silent "${releaseURL}" -o "${release_file}" 2>/dev/null
	checkFile "${release_file}"
	releaseDownloadURL="$(jq -r '.downloads.server.url' ${release_file})"
	javaReleaseMajorVersion="$(jq -r '.javaVersion.majorVersion' ${release_file})"

	echo -e "${BLUE} [+] Veryfing Java version compatibility ${RESET}"
	javaCurrentVersion="$(java --version | grep -Eo -m 1 '\b[0-9]+(\.[0-9]+){1,2}\b')"
	javaCurrentMajorVersion=$(echo "${javaCurrentVersion}" | cut -d '.' -f1)

	echo -e "${BLUE} [+] Current Java version is ${LIGTH_GRAY}${javaCurrentVersion} ${RESET}"
	echo -e "${BLUE} [+] Release requires version ${LIGTH_GRAY}${javaReleaseMajorVersion} ${RESET}"
	if [ "$javaCurrentMajorVersion" -ne "$javaReleaseMajorVersion" ] && [ "$javaCurrentMajorVersion" -lt "$javaReleaseMajorVersion" ]; then
		echo -e "${YELLOW} [!] Current Java version is not compatible with latest release ${RESET}"
	    	javaCompatible=0
	else
		echo -e "${GREEN} [\u2713] Java version requirements satisfied ${RESET}"
		javaCompatible=1
	fi

	if [[ -f "$serverFile" ]] && [ "$javaCompatible" -eq 1 ]; then
		# File is present, look for updates
		echo -e "${BLUE} [+] Comparing server file hashes ${RESET}"
		currentSHA1="$(sha1sum ${serverFile} | cut -d ' ' -f1)"
		releaseSHA1="$(jq -r '.downloads.server.sha1' ${release_file})"
		echo -e "${BLUE} [+] Current server file hash is ${LIGTH_GRAY}${currentSHA1} ${RESET}"
		echo -e "${BLUE} [+] Release server file hash is ${LIGTH_GRAY}${releaseSHA1} ${RESET}"
		if [ "$releaseSHA1" == "$currentSHA1" ]; then
			echo -e "${GREEN} [\u2713] SHA1 hashes match: no action required ${RESET}"
			isRelease=0
		else
			echo -e "${YELLOW} [!] SHA1 hashes mismatch: version available for download ${RESET}"
			echo -e "${YELLOW} [+] Download URL: ${LIGTH_GRAY}$releaseDownloadURL ${RESET}"
			isRelease=1
		fi
	fi
}

function serverStatus() {
	if [ $(su ${mcServerUser} -s '/bin/bash' -c "cd ${javaDir} && screen -ls" > /dev/null 2>&1 ; echo $?) -eq 0 ]; then
		# server is active
		echo 1
	else
		# server is not running
		echo 0
	fi
}

function serverVersion() {
	local srvVersion
	srvVersion=$(grep -iEao -m 1 "server-${versionRegex}.jar" "${serverFile}" | grep -iEo "${versionRegex}")
	if [ ! -z "$srvVersion" ]; then
		echo "$srvVersion"
	else
		echo "?"
	fi
}

function checkFile() {
	local filepath="$1"
	if [ ! -f "$filepath" ]; then
		echo -e "${YELLOW} [!] Something went wrong: file ${LIGTH_GRAY}$filepath${YELLOW} not found ${RESET}"
		echo -e "${RED}[\u00d7] Aborted ${RESET}"
		exit 1
	else
		return
	fi
}

### PRE-SCRIPT CONTROLS

# Best for portability
# Might also use $EUID for bash/zsh
if [ "$(id -u)" -ne 0 ]; then
	echo -e "${YELLOW}[!] The MC management tool must be run with root privileges ${RESET}"
	echo -e "${RED}[\u00d7] Aborted ${RESET}"
    exit 1
fi

if [ "$(which curl &>/dev/null ; echo $?)" -ne 0 ]; then
    echo -e "${YELLOW}[!] cURL (curl) is NOT installed ${RESET}"
    echo -e "${YELLOW}[+] Install it by using the proper package manager ${RESET}"
    echo -e "${RED}[\u00d7] Aborted ${RESET}"
    exit 1
fi

if [ "$(which jq &>/dev/null ; echo $?)" -ne 0 ]; then
    echo -e "${YELLOW}[!] Jq (JSON query) is NOT installed ${RESET}"
    echo -e "${YELLOW}[+] Install it by using the proper package manager ${RESET}"
    echo -e "${RED}[\u00d7] Aborted ${RESET}"
    exit 1
fi

if [ "$(which screen &>/dev/null ; echo $?)" -ne 0 ]; then
    echo -e "${YELLOW}[!] Screen is NOT installed ${RESET}"
    echo -e "${YELLOW}[+] Install it by using the proper package manager ${RESET}"
    echo -e "${RED}[\u00d7] Aborted ${RESET}"
    exit 1
fi

if [ "$(which tar &>/dev/null ; echo $?)" -ne 0 ]; then
    echo -e "${YELLOW}[!] Tar is NOT installed ${RESET}"
    echo -e "${YELLOW}[+] Install it by using the proper package manager ${RESET}"
    echo -e "${RED}[\u00d7] Aborted ${RESET}"
    exit 1
fi

# Checking Java installation
if [ "$(java --version > /dev/null 2>&1 ; echo $?)" -ne 0 ]; then
	echo -e "${YELLOW}[!] No Java package installed ${RESET}"
	echo -e "${YELLOW}[+] Install either JDK or JRE: headless is preferred ${RESET}"
	echo -e "${RED}[\u00d7] Aborted ${RESET}"
   	exit 1
fi

### IF EVERYTHING IS OK
### TIME TO GO

### HANDLE FLAGS BEFORE STARTING SCRIPT

handleFlags "$@"

### FLAG COMPATIBILITY CHECK

if [[ "$skipCheck" -eq 1 && ( "$updateServer" -eq 1 || "$forceDownload" -eq 1 || ! -z "$installVersion" ) ]]; then
	echo "Invalid option: Can't download server.jar without checking release requirements" >&2
    echo -n $'\n'
    printHelp
    exit 1
fi

if [[ "$updateServer" -eq 1 && ! -z "$installVersion" ]]; then
	echo "Invalid option: Can't install specific version when requesting an update" >&2
    echo -n $'\n'
    printHelp
    exit 1
fi

### CHECK DIRECTORY EXISTENCE

if [[ ! -d "$serverDir" ]]; then
	mkdir -p "$serverDir"
fi

if [[ ! -d "$javaDir" ]]; then
	mkdir -p "$javaDir"
	echo "eula=true" > "${javaDir}/eula.txt"
fi

if [[ ! -d "$worldDir" ]]; then
	mkdir -p "$worldDir"
fi

# No need to create the temp directory if
# there is no check update
if [ ! -d "$tmpDirJSON" ] && [ "$skipCheck" -eq 0 ]; then
	mkdir -p "$tmpDirJSON"
fi

### START OF SCRIPT

echo -e "${BLUE}[+] Starting MC Server Management tool ... ${RESET}"
echo -e "${BLUE} [+] Server directory is ${LIGTH_GRAY}$serviceDir ${RESET}"

if [[ "$(grep -io ${mcServerUser} /etc/passwd)" == "" ]]; then
	echo -e "${YELLOW} [!] Missing default ${mcServerUser} server user${RESET}"
	echo -e "${BLUE} [+] Adding user ${mcServerUser} ${RESET}"
    useradd --system --no-create-home --shell '/bin/false' "${mcServerUser}"
fi

if [ "$skipCheck" -eq 0 ]; then
	versionCheck
else
	echo -e "${YELLOW} [!] Skipping release check ${RESET}"
	isRelease=0
	javaCompatible=0
fi


### Check server file existence
if [[ ! -f "$serverFile" ]] && [ "$javaCompatible" -eq 1 ]; then
	echo -e "${YELLOW} [!] Missing server file at ${LIGTH_GRAY}$serverDir ${RESET}"
	echo -e "${BLUE} [+] Downloading fresh server file from ${LIGTH_GRAY}$releaseDownloadURL ${RESET}"
	wget "${releaseDownloadURL}" -P "${serverDir}" -q --show-progress
	echo -e "${GREEN} [\u2713] Server file downloaded ${RESET}"

elif [[ "$isRelease" -eq 1 ]] && [[ "$javaCompatible" -eq 1 ]]; then
	if [ ! -z "$installVersion" ]; then
		echo -e "${BLUE} [+] Downloading release version ${LIGTH_GRAY}$installVersion ${BLUE}from ${LIGTH_GRAY}$releaseDownloadURL ${RESET}"
		rm -f "${serverFile}" 2>/dev/null
		wget "${releaseDownloadURL}" -P "${serverDir}" -q --show-progress
	elif [ "$updateServer" -eq 1 ]; then
		echo -e "${BLUE} [+] Downloading new release from ${LIGTH_GRAY}$releaseDownloadURL ${RESET}"
		rm -f "${serverFile}" 2>/dev/null
		wget "${releaseDownloadURL}" -P "${serverDir}" -q --show-progress
	else
		echo -e "${YELLOW} [!] SKipping update ${RESET}"
	fi

elif [[ "$isRelease" -eq 0 ]] && [[ "$javaCompatible" -eq 1 ]] && [[ "$forceDownload" -eq 1 ]]; then
	echo -e "${YELLOW} [!] Forcing download of server JAR file from ${LIGTH_GRAY}$releaseDownloadURL ${RESET}"
	rm -f "${serverFile}" 2>/dev/null
	wget "${releaseDownloadURL}" -P "${serverDir}" -q --show-progress

elif [[ -f "$serverFile" ]]; then
	echo -e "${YELLOW} [!] Keeping current server file ${RESET}"

else
	echo -e "${YELLOW} [!] Missing server file at ${LIGTH_GRAY}$serverDir ${RESET}"
	if [ "$skipCheck" -eq 1 ]; then
		echo -e "${YELLOW} [+] Cannot download server.jar without checking requirements ${RESET}"
	elif [ ! -z "$installVersion" ]; then
		echo -e "${YELLOW} [+] Could not install release version ${LIGTH_GRAY}$installVersion ${RESET}"
	elif [ "$javaCompatible" -eq 0 ]; then
		echo -e "${YELLOW} [+] Current Java will not run latest release server ${RESET}"
	else
		echo -e "${YELLOW} [+] Unkwon error ${RESET}"
	fi
	echo -e "${RED}[\u00d7] Aborted ${RESET}"
	exit 1
fi

### CLEANUP
# No need to remove the temp directory if
# no update check has been performed
if [ "$skipCheck" -eq 0 ]; then
	echo -e "${BLUE} [+] Cleanup temp files ${RESET}"
	rm -rf "${tmpDirJSON}"
fi

### SETTING PERMISSIONS
echo -e "${BLUE} [+] Checking file permissions ${RESET}"
if [[ "$(stat -c %U ${serviceDir})" != "${mcServerUser}" ]]; then
	echo -e "${BLUE} [+] Setting recursive permissions for ${serviceDir} ${RESET}"
	chown -R "${mcServerUser}:${mcServerUser}" "${serviceDir}"
elif [[ "$(stat -c %U ${javaDir})" != "${mcServerUser}" ]]; then
	echo -e "${BLUE} [+] Setting permissions for ${javaDir} ${RESET}"
	chown -R "${mcServerUser}:${mcServerUser}" "${javaDir}"
elif [[ "$(stat -c %U ${worldDir})" != "${mcServerUser}" ]] || [[ "$(stat -c %U ${worldDir}/${WORLD_NAME} 2>/dev/null)" != "${mcServerUser}" ]]; then
	echo -e "${BLUE} [+] Setting permissions for ${worldDir} ${RESET}"
	chown -R "${mcServerUser}:${mcServerUser}" "${worldDir}"
elif [[ "$(stat -c %U ${serverFile})" != "${mcServerUser}" ]]; then
	echo -e "${BLUE} [+] Setting permissions for new ${serverFile} ${RESET}"
	chown -R "${mcServerUser}:${mcServerUser}" "${serverDir}"
else
	echo -e "${GREEN} [+] File permissions looking good ${RESET}"
fi

### STARTUP
if [ "$startMC" -eq 1 ]; then
	if [ $(serverStatus) -eq 1 ]; then
		echo -e "${YELLOW} [!] A server instance is already running ${RESET}"
		echo -e "${YELLOW} [+] Server version: ${LIGTH_GRAY}$(serverVersion) ${RESET}"
		echo -e "${YELLOW} [+] Skipping startup ${RESET}"
		exit 1
	fi

	echo -e "${GREEN} [+] All ready: starting MC server ${RESET}"
	echo -e "${GREEN} [+] Server version: ${LIGTH_GRAY}$(serverVersion) ${RESET}"
	su ${mcServerUser} -s '/bin/bash' -c "cd ${javaDir} && screen -dmS ${mcServiceName} java -Xmx${MAXIMUM_MEMORY} -Xms${INITIAL_MEMORY} -jar ${serverFile} --world ${WORLD_NAME} --universe ${worldDir} --nogui"
	if [ $? -eq 0 ]; then
		echo -e "${GREEN}[\u2713] MC server started successfully ${RESET}"
		exit 1
	else
		echo -e "${RED}[+] Error starting MC server ${RESET}"
		echo -e "${RED}[\u00d7] Aborted ${RESET}"
		exit 1
	fi
fi

### END OF SCRIPT
