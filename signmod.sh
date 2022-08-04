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


# Constants.
argErrorCode=1
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
minKeySize=512
maxKeySize=4096
logHeader="[*] "
pubKeyExt="pub.der"
privKeyExt="priv.pem"

# Default parameters.
myName="$(basename $0)"
baseDir="."
dirAdj="current"
keySize="4096"
certDur="1825"
signAlgo="sha512"
osslEncrypt="true"
osslVerbosity=""
muVerbosity="false"

# Documentation strings.
read -r -d '' usageDoc << EOF
Usage:  $myName  -h | --help
    $myName [-t | --test]
            [-v | --verbose]
            [-n | --no-encrypt]
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
        name references    an existing module on the current system; if a
        <kernelModuleName>.$pubKeyExt signature data file exists in the current
        directory; the current state of the .$pubKeyExt file in the MOK manager.
    -v | --verbose: Activate further output verbosity.
    -n | --no-encrypt: Do not encrypt the private key. Private key encryption
        is the default, a password will be prompted in this case.
    -d | --directory <dirName>: The directory where the script should cd into
        in order to read and write files necessary for its functionalities.
        If not provided, it defaults the current working directory, i.e.
        where the script is called and not where it is stored.
    -s | --key-size <keySize>: The RSA key size to use when generating a
        new public-private key pair to sign the module with. Considering the
        tools used, the provided value must be included between $minKeySize
        and $maxKeySize. This option is not used when only testing. If not
        provided, it defaults to $keySize.
    -c | --cert-dur <certDur>: The duration in days the generated certificate
        - i.e. the RSA key pair - should be valid for. If not provided, it
        defaults to 5 * 365 = 1825 days.
    -a | --sign-algo <signAlgo>: The hash algorithm that should be used to
        sign the module with. Supported values are: sha1, sha224, sha256,
        sha384 and sha512. If not provided, it defaults to $signAlgo.
    -m | --module <kernelModuleName>: The kernel module's name, mandatory
        when managing a kernel module.
EOF

read -r -d '' descDoc << EOF
Description:
    This script will help you sign a kernel module in order to use it when
    SecureBoot is enabled. Provide the kernel module's name and the script
    will, in order:
    * Check if the module was previously signed by testing if a file
      <kernelModuleName>.$pubKeyExt exists or not in the current or given
      directory and was used to register a key to the MOK manager. If it does,
      then it removes the previous signature from the MOK manager.
    * Generate a new public-private (by default $keySize bits) RSA key pair and
      write it to <kernelModuleName>.$pubKeyExt and <kernelModuleName>
      .$privKeyExt files.
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

# Usage string and error when there is no argument.
if [[ "$#" -eq "0" ]]; then
    echo "$usageDoc" >&2
    exit $argErrorCode
fi

# Arguments parsing, reports its own errors.
argsTmp=$(getopt -o "h,t,v,n,d:,s:,c:,a:,m:"\
            -l "help,test,verbose,no-encrypt,directory:,key-size:,cert-dur:,sign-algo:,module:"\
            -n "$myName"\
            -s "bash"\
            -- "$@")

# Usage string and error if parsing throws an error.
if [[ "$?" -ne "0" ]]; then
    echo -e "\n$usageDoc" >&2
    exit $argErrorCode
fi

# Set the parsed arguments as ours.
eval set -- "$argsTmp"
unset argsTmp

# Tests if $2 is in list $1.
function contains() {
    [[ "$1" =~ (^| )$2($| ) ]] && return 0 || return 1
}

# Main argument handling.
while true; do
    case "$1" in
        "-h" | "--help")
            echo "$helpDoc"
            exit 0
        ;;
        "-t" | "--test")
            toTest="true"
            shift
            continue
        ;;
        "-v" | "--verbose")
            osslVerbosity="-verbose"
            muVerbosity="true"
            shift
            continue
        ;;
        "-n" | "--no-encrypt")
            osslEncrypt="false"
            shift
            continue
        ;;
        "-d" | "--directory")
            baseDir="$2"
            dirAdj="given"

            # Report an error if the given directory is missing.
            if [[ -d "$baseDir" ]]; then
                cd "$baseDir"
            else
                echo "$baseDir $wrongDirErrorDoc" >&2
                exit $argErrorCode
            fi

            shift 2
            continue
        ;;
        "-s" | "--key-size")
            keySize="$2"

            # The RSA key size should be a 1-to-4-digit integer (max 4096).
            if ! [[ "$keySize" =~ ^[0-9]{1,4}$ ]]\
                    || [[ $keySize -lt $minKeySize ]]\
                    || [[ $keySize -gt $maxKeySize ]]; then
                echo "$invalidKeySizeErrorDoc" >&2
                exit $argErrorCode
            fi

            shift 2
            continue
        ;;
        "-c" | "--cert-dur")
            certDur="$2"

            # The duration should be at least one digit long.
            if ! [[ "$certDur" =~ ^[0-9]+$ ]]\
                    || [[ $certDur -eq 0 ]]; then
                echo "$invalidCertDurErrorDoc" >&2
                exit $argErrorCode
            fi

            shift 2
            continue
        ;;
        "-a" | "--sign-algo")
            signAlgo="$2"

            # Check if the given algorithm is the list of supported algorithms.
            if ! contains "$signAlgosList" "$signAlgo"; then
                echo "$invalidSignAlgoErrorDoc" >&2
                exit $argErrorCode
            fi

            shift 2
            continue
        ;;
        "-m" | "--module")
            modName="$2"
            shift 2
            continue
        ;;
        # This case is given by `getopt` when there are no more arguments.
        "--")
            shift
            break
        ;;
        # This should only be reached in case of a programming mistake.
        *)
            echo "$intErrorDoc" >&2
            exit $intErrorCode
        ;;
    esac
done

# Give an error for each remaining unexpected argument and print the usage.
for otherArg; do
    echo "Unknown argument: '$otherArg'" >&2
    unknArgDet="true"
done
if [[ "$unknArgDet" = "true" ]]; then
    echo -e "\n$usageDoc" >&2
    exit $argErrorCode
fi

# The module name is mandatory for the rest of the execution.
if [[ -z "${modName+x}" ]]; then
    echo "$missModNameErrorDoc" >&2
    exit $argErrorCode
fi

sudo mokutil --set-verbosity "$muVerbosity"


# Handles the signing itself.
function signMod() {
    set -e

    # Delete an older key if it exists.
    if [[ -f "$modName.$pubKeyExt" ]] && ! sudo mokutil -t "$modName.$pubKeyExt"; then
        echo "$logHeader""Deleting $modName's previous signing key..."
        sudo mokutil --delete "$modName.$pubKeyExt"
        echo "$logHeader""Done."
    fi

    # Generate a new key pair.
    echo "$logHeader""Generating new $modName signing keys..."
    openssl req -new -x509 -newkey rsa:"$keySize" -keyout "$modName.$privKeyExt"\
                -outform DER -out "$modName.$pubKeyExt" -nodes -days "$certDur"\
                -subj "/CN=$modName kernel module signing key/" -utf8\
                -"$signAlgo" $osslVerbosity
    echo "$logHeader""Done."

    # Sign the module with it.
    echo "$logHeader""Signing module..."
    sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file "$signAlgo"\
        "./$modName.$privKeyExt" "./$modName.$pubKeyExt" "$(sudo modinfo -n $modName)"
    echo "$logHeader""Done."

    # Encrpyt the private key if requested.
    if [[ "$osslEncrypt" = "true" ]]; then
        echo "$logHeader""Encrypting private key..."
        openssl pkcs8 -in "./$modName.$privKeyExt" -topk8 -out "./$modName.$privKeyExt.tmp"
        mv -f "./$modName.$privKeyExt.tmp" "./$modName.$privKeyExt"
        echo "$logHeader""Done."
    fi

    # Register the certificate in the MOK keyring.
    echo "$logHeader""Registering keys to the MOK manager..."
    sudo mokutil --import "./$modName.$pubKeyExt"
    echo -e "$logHeader""Done.\n"

    echo "$logHeader""You should now reboot the system and enroll the new MOK."
}

# Runs a few helper tests.
function testMod() {
    echo "$logHeader""Starting tests..."
    modInfo="$(sudo modinfo $modName)"

    # Determine if the module exists.
    if [[ "$?" -eq "0" ]]; then
        echo -e "$logHeader""The given module is:\n\n$modInfo\n"
    else
        echo "$logHeader""The given module doesn't seem to exist on the current system." >&2
    fi

    # Check if a private key file exists and is a text file.
    if [[ -f "$modName.$privKeyExt" ]]; then
        echo "$logHeader""$modName.$privKeyExt is a file in the $dirAdj directory."
        local fileInfo="$(file -b -i $modName.$privKeyExt)"

        if [[ "$fileInfo" = "$txtFileType" ]]; then
            echo -e "\tIt seems to be a text file."
        else
            echo -e "\tBut it doesn't seem to be a text file: '$fileInfo'." >&2
        fi
    else
        echo "$logHeader""$modName.$privKeyExt is NOT a file in the $dirAdj directory."
    fi

    # Check if a public key exists as a "binary" file (DER) and display its
    # state according to the MOK manager.
    if [[ -f "$modName.$pubKeyExt" ]]; then
        echo "$logHeader""$modName.$pubKeyExt is a file in the $dirAdj directory."
        local fileInfo="$(file -b -i $modName.$pubKeyExt)"

        if [[ "$fileInfo" = "$binFileType" ]]; then
            echo -e "\tIt seems to be a binary data file."
        else
            echo -e "\tBut it doesn't seem to be a binary data file: '$fileInfo'." >&2
        fi

        echo "$(sudo mokutil -t $modName.$pubKeyExt)"
    else
        echo "$logHeader""$modName.$pubKeyExt is NOT a file in the $dirAdj directory."
    fi

    unset modInfo
    echo "$logHeader""Done."
}


if [[ "$toTest" = "true" ]]; then
    testMod
else
    signMod
fi
