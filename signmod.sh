#! /bin/bash


argErrorCode=1
intErrorCode=2
intErrorDoc="Internal error. Exiting now."
missModNameErrorDoc="Missing kernel module's name. Exiting now."
myName="$(basename $0)"
txtFileType="text/plain; charset=us-ascii"
binFileType="application/octet-stream; charset=binary"

read -r -d '' usageDoc << EOF
Usage:  $myName  -h | --help
	$myName [-t | --test]
		    -m | --module <kernelModuleName>
EOF

read -r -d '' paramsDoc << EOF
Parameters:
	-h | --help: Prints the help message and stops.
	-t | --test: Optionally, tests a few things: if the given kernel module
		name references	an existing module on the current system; if a
		<kernelModuleName>.der signature data file exists in the current
		directory; the current state of the .der file in the MOK manager.
	-m | --module <kernelModuleName>: The kernel module's name, mandatory
		when managing a kernel module.
EOF

read -r -d '' descDoc << EOF
Description:
	This script will help you sign a kernel module in order to use it when
	SecureBoot is enabled. Provide the kernel module's name and the script
	will, in order:
		* Check if the module was previously signed by testing if a file
		  <kernelModuleName>.der exists or not in the current directory
		  and was used to register a key to the MOK manager. If it does,
		  then it removes the previous signature from the MOK manager.
		* Generate a new public-private 4096b RSA key pair and write it
		  to <kernelModuleName>.der and <kernelModuleName>.priv files.
		* Sign the module's kernel object file itself.
		* Register the new key to the MOK manager.
	
	When it is done and that no error was thrown, you can reboot the system.
EOF

read -r -d '' helpDoc << EOF
$usageDoc

$paramsDoc

$descDoc
EOF


argsTmp=$(getopt -o "h,t,m:" -l "help,test,module:" -n "$myName" -s "bash" -- "$@")

if [[ "$?" -ne "0" ]]; then
	echo -e "\n$usageDoc" >&2
	exit $argErrorCode
fi

eval set -- "$argsTmp"
unset argsTmp

while true; do
	case "$1" in
		"-h"|"--help")
			echo "$helpDoc"
			exit 0
		;;
		"-t"|"--test")
			toTest="true"
			shift
			continue
		;;
		"-m"|"--module")
			modName="$2"
			shift 2
			continue
		;;
		"--")
			shift
			break
		;;
		*)
			echo "$intErrorDoc" >&2
			exit $intErrorCode
		;;
	esac
done

for otherArg; do
	echo "Unknown argument: '$otherArg'" >&2
	unknArgDet="true"
done
if [[ "$unknArgDet" = "true" ]]; then
	echo -e "\n$usageDoc" >&2
	exit $argErrorCode
fi

if [[ -z "${modName+x}" ]]; then
	echo "$missModNameErrorDoc" >&2
	exit $argErrorCode
fi


exit 0
function signMod() {
	set -e

	if [[ -f "$modName.der" ]] && ! sudo mokutil -t "$modName.der"; then
		echo "[*] Deleting $modName's previous signing key..."
		sudo mokutil --delete "$modName.der"
		echo '[*] Done.'
	fi
	
	echo "[*] Generating new $modName signing keys..."
	openssl req -new -x509 -newkey rsa:4096 -keyout "$modName.priv" -outform DER -out "$modName.der" -nodes -days 3650 -subj "/CN=$modName kernel module signing key/"
	echo '[*] Done.'
	
	echo '[*] Signing module ...'
	sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file sha256 "./$modName.priv" "./$modName.der" "$(sudo modinfo -n $modName)"
	echo '[*] Done.'
	
	echo '[*] Registering keys to the MOK manager...'
	sudo mokutil --import "./$modName.der"
	echo -e '[*] Done.\n'
	
	echo '[*] You should now reboot the system and enroll the new MOK.'
}

function testMod() {
	echo '[*] Starting tests...'
	modInfo="$(sudo modinfo $modName)"

	if [[ "$?" -eq "0" ]]; then
		echo -e "[*] The given module is:\n\n$modInfo\n"
	else
		echo -e "[*] The given module doesn't seem to exist on the current system." >&2
	fi

	if [[ -f "$modName.priv" ]]; then
		echo "[*] $modName.priv is a file in the current directory."
		local fileInfo="$(file -b -i $modName.priv)"

		if [[ "$fileInfo" = "$txtFileType" ]]; then
			echo -e "\tIt seems to be a text file."
		else
			echo -e "\tBut it doesn't seem to be a text file: '$fileInfo'." >&2
		fi
	fi

	if [[ -f "$modName.der" ]]; then
		echo "[*] $modName.der is a file in the current directory."
		local fileInfo="$(file -b -i $modName.der)"
		
		if [[ "$fileInfo" = "$binFileType" ]]; then
			echo -e "\tIt seems to be a binary data file."
		else
			echo -e "\tBut it doesn't seem to be a binary data file: '$fileInfo'." >&2
		fi
		
		echo "$(sudo mokutil -t $modName.der)"
	fi

	echo "[*] Done."
}


if [[ "$toTest" = "true" ]]; then
	testMod
else
	signMod
fi
