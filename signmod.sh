#! /bin/bash
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.


argErrorCode=1										# Constants.
intErrorCode=2
intErrorDoc="Internal error. Exiting now."
missModNameErrorDoc="Missing kernel module's name. Exiting now."
wrongDirErrorDoc="is not an existing directory. Exiting now."
invalidKeySizeErrorDoc="The given key size is not valid. Exiting now."
invalidCertDurErrorDoc="The given certificate duration is not valid. Exiting now."
invalidSignAlgoErrorDoc="The given signature hash algorithm is not valid. Exiting now."
txtFileType="text/plain; charset=us-ascii"
binFileType="application/octet-stream; charset=binary"
signAlgosList="sha1 sha224 sha256 sha384 sha512"

myName="$(basename $0)"								# Default parameters.
baseDir="."
dirAdj="current"
keySize="4096"
certDur="1825"
signAlgo="sha512"

# Documentation strings.
read -r -d '' usageDoc << EOF
Usage:  $myName  -h | --help
	$myName [-t | --test]
		   [-d | --directory] <dirName>
		   [-s | --key-size] <keySize>
		   [-c | --cert-dur] <certDur>
		   [-a | --sign-algo] <signAlgo>
		    -m | --module <kernelModuleName>
EOF

read -r -d '' paramsDoc << EOF
Parameters:
	-h | --help: Prints the help message and stops.
	-t | --test: Optionally, tests a few things: if the given kernel module
		name references	an existing module on the current system; if a
		<kernelModuleName>.der signature data file exists in the current
		directory; the current state of the .der file in the MOK manager.
	-d | --directory <dirName>: The directory where the script should cd into
		in order to read and write files necessary for its functionalities.
		If not provided, it defaults the current working directory, i.e.
		where the script is called and not where it is stored.
	-s | --key-size <keySize>: The RSA key size to use when generating a
		new public-private key pair to sign the module with. This option
		is not used when only testing. If not provided, it defaults to 4096.
	-c | --cert-dur <certDur>: The duration in days the generated certificate
		- i.e. the RSA key pair - should be valid for. If not provided, it
		defaults to 5 * 365 = 1825 days.
	-a | --sign-algo <signAlgo>: The hash algorithm that should be used to
		sign the module with. Supported values are: sha1, sha224, sha256,
		sha384 and sha512. If not provided, it defaults to sha512.
	-m | --module <kernelModuleName>: The kernel module's name, mandatory
		when managing a kernel module.
EOF

read -r -d '' descDoc << EOF
Description:
	This script will help you sign a kernel module in order to use it when
	SecureBoot is enabled. Provide the kernel module's name and the script
	will, in order:
		* Check if the module was previously signed by testing if a file
		  <kernelModuleName>.der exists or not in the current or given
		  directory and was used to register a key to the MOK manager. If
		  it does, then it removes the previous signature from the MOK
		  manager.
		* Generate a new public-private (by default 4096b) RSA key pair
		  and write it to <kernelModuleName>.der and <kernelModuleName>
		  .priv files.
		* Sign the module's kernel object file.
		* Enroll the new key to the MOK manager.
	
	When it is done and that no error was thrown, you should reboot the system
	in order to perform the registered MOK managing actions.
EOF

read -r -d '' helpDoc << EOF
$usageDoc

$paramsDoc

$descDoc
EOF


if [[ "$#" -eq "0" ]]; then							# If there are no arguments given,
	echo "$usageDoc" >&2							# give the usage documentation.
	exit $argErrorCode
fi

# Arguments parsing, reports its own errors.
argsTmp=$(getopt -o "h,t,m:,d:,s:,c:,a:"\
			-l "help,test,module:,directory:,key-size:,cert-dur:,sign-algo:"\
			-n "$myName"\
			-s "bash"\
			-- "$@")

if [[ "$?" -ne "0" ]]; then							# In case the parsing threw an error,
	echo -e "\n$usageDoc" >&2						# just report the usage because it is
	exit $argErrorCode								# often due to misuse of arguments.
fi

eval set -- "$argsTmp"								# Making the parsed arguments mine.
unset argsTmp										# Freeing the temporary variable.

function contains() {								# Tests if $2 is in list $1.
    [[ "$1" =~ (^| )$2($| ) ]] && return 0 || return 1
}

while true; do										# Arguments management:
	case "$1" in
		"-h" | "--help")							# Help
			echo "$helpDoc"
			exit 0
		;;
		"-t" | "--test")							# Test module
			toTest="true"
			shift
			continue
		;;
		"-m" | "--module")							# Module name
			modName="$2"
			shift 2
			continue
		;;
		"-d" | "--directory")						# Working directory
			baseDir="$2"
			dirAdj="given"
			
			if [[ -d "$baseDir" ]]; then			# Check if the given directory exists:
				cd "$baseDir"						# if so, then go in it,
			else
				echo "$baseDir $wrongDirErrorDoc" >&2
				exit $argErrorCode					# otherwise report an error.
			fi
			
			shift 2
			continue
		;;
		"-s" | "--key-size")						# RSA key size
			keySize="$2"
			
			if ! [[ "$keySize" =~ ^[0-9]{1,4}$ ]]; then
				echo "$invalidKeySizeErrorDoc" >&2	# The key size should be a 1 to 4 digits
				exit $argErrorCode					# integer (max 4096), otherwise throw error.
			fi
			
			shift 2
			continue
		;;
		"-c" | "--cert-dur")						# Certificate duration
			certDur="$2"
			
			if ! [[ "$certDur" =~ ^[0-9]+$ ]]; then
				echo "$invalidCertDurErrorDoc" >&2	# The duration should be at least one digit
				exit $argErrorCode					# long, otherwise throw an error.
			fi
			
			shift 2
			continue
		;;
		"-a" | "--sign-algo")						# Signature hash algorithm
			signAlgo="$2"
			
			if ! contains "$signAlgosList" "$signAlgo"; then
				echo "$invalidSignAlgoErrorDoc" >&2	# Only a value from a precise list of
				exit $argErrorCode					# algorithms is expected, else error.
			fi
			
			shift 2
			continue
		;;
		"--")										# This case is used by getopt to inform
			shift									# us that no more option arguments are
			break									# to be expected, so we can stop here,
		;;
		*)											# but if "--" wasn't encountered after
			echo "$intErrorDoc" >&2					# checking for all the options, then it
			exit $intErrorCode						# means there is a programming mistake.
		;;
	esac
done

for otherArg; do									# When more arguments are given,
	echo "Unknown argument: '$otherArg'" >&2		# give an error for each of them
	unknArgDet="true"
done
if [[ "$unknArgDet" = "true" ]]; then
	echo -e "\n$usageDoc" >&2						# and give the usage, as no further
	exit $argErrorCode								# arguments are expected.
fi

if [[ -z "${modName+x}" ]]; then					# If execution has gone this far,
	echo "$missModNameErrorDoc" >&2					# the module name is mandatory.
	exit $argErrorCode
fi


function signMod() {								# Handles the signing itself.
	set -e											# It stops as soon as an error pops;
	
	if [[ -f "$modName.der" ]] && ! sudo mokutil -t "$modName.der"; then
		echo "[*] Deleting $modName's previous signing key..."
		sudo mokutil --delete "$modName.der"		# if an older key is registered in
		echo '[*] Done.'							# the MOK manager, delete it;
	fi
	
	echo "[*] Generating new $modName signing keys..."
	openssl req -new -x509 -newkey rsa:"$keySize" -keyout "$modName.priv"\
				-outform DER -out "$modName.der" -nodes -days "$certDur"\
				-subj "/CN=$modName kernel module signing key/"
	echo '[*] Done.'								# generate a new key pair,
	
	echo '[*] Signing module ...'
	sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file "$signAlgo"\
		"./$modName.priv" "./$modName.der" "$(sudo modinfo -n $modName)"
	echo '[*] Done.'								# sign the module with it
	
	echo '[*] Registering keys to the MOK manager...'
	sudo mokutil --import "./$modName.der"			# and import it in the MOK manager.
	echo -e '[*] Done.\n'
	
	echo '[*] You should now reboot the system and enroll the new MOK.'
}

function testMod() {								# Runs a few helper tests.
	echo '[*] Starting tests...'
	modInfo="$(sudo modinfo $modName)"				# Trying if the module exists;
	
	if [[ "$?" -eq "0" ]]; then
		echo -e "[*] The given module is:\n\n$modInfo\n"
	else
		echo -e "[*] The given module doesn't seem to exist on the current system." >&2
	fi
	
	if [[ -f "$modName.priv" ]]; then				# checking if a private key file exists
		echo "[*] $modName.priv is a file in the $dirAdj directory."
		local fileInfo="$(file -b -i $modName.priv)"
		
		if [[ "$fileInfo" = "$txtFileType" ]]; then	# and is a text file;
			echo -e "\tIt seems to be a text file."
		else
			echo -e "\tBut it doesn't seem to be a text file: '$fileInfo'." >&2
		fi
	else
		echo "[*] $modName.priv is NOT a file in the $dirAdj directory."
	fi
	
	if [[ -f "$modName.der" ]]; then				# checking if a DER public key file exists,
		echo "[*] $modName.der is a file in the $dirAdj directory."
		local fileInfo="$(file -b -i $modName.der)"
		
		if [[ "$fileInfo" = "$binFileType" ]]; then # is a binary data file
			echo -e "\tIt seems to be a binary data file."
		else
			echo -e "\tBut it doesn't seem to be a binary data file: '$fileInfo'." >&2
		fi
		
		echo "$(sudo mokutil -t $modName.der)"		# and its state in the MOK manager.
	else
		echo "[*] $modName.der is NOT a file in the $dirAdj directory."
	fi
	
	unset modInfo									# Cleaning variables.
	echo "[*] Done."
}


if [[ "$toTest" = "true" ]]; then					# Choosing between test and signing.
	testMod
else
	signMod
fi
