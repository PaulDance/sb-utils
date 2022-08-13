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
ARG_ERROR_CODE=1
INT_ERROR_CODE=2
INT_ERROR_DOC="Internal error. Exiting now."
MISS_MOD_ERROR_DOC="Missing kernel module's name. Exiting now."
WRONG_DIR_ERROR_DOC="is not an existing directory. Exiting now."
INV_KEY_SIZE_ERROR_DOC="The given key size is not valid. Exiting now."
INV_CERT_DUR_ERROR_DOC="The given certificate duration is not valid. Exiting now."
INV_SIGN_ALGO_ERROR_DOC="The given signature hash algorithm is not valid. Exiting now."
TXT_MIME_TYPE="text/plain; charset=us-ascii"
BIN_MIME_TYPE="application/octet-stream; charset=binary"
SIGN_ALGOS_LIST="sha1 sha224 sha256 sha384 sha512"
MIN_KEY_SIZE=512
MAX_KEY_SIZE=4096
LOG_HEADER="[*] "
KEY_STEM="cert"
PUB_KEY_EXT="pub.der"
PRIV_KEY_EXT="priv.pem"
MY_NAME="$(basename $0)"

# Default parameters.
base_dir="$HOME/.mok"
dir_adj="default"
key_size="4096"
cert_dur="1825"
sign_algo="sha512"
ossl_encrypt=""
ossl_verbosity=""
mok_verbosity="false"

# Documentation strings.
read -r -d '' USAGE_DOC << EOF
Usage:  $MY_NAME  -h | --help
    [-t | --test]
    [-v | --verbose]
    [-n | --no-encrypt]
    [-d | --directory] <dir_name>
    [-s | --key-size] <key_size>
    [-c | --cert-dur] <cert_dur>
    [-a | --sign-algo] <sign_algo>
     -m | --module <module_name>
EOF

read -r -d '' PARAMS_DOC << EOF
Parameters:
    -h | --help: Prints the help message and stops.
    -t | --test: Optionally, tests a few things: if the given kernel module
        name references    an existing module on the current system; if a
        <module_name>.$PUB_KEY_EXT signature data file exists in the current
        directory; the current state of the .$PUB_KEY_EXT file in the MOK manager.
    -v | --verbose: Activate further output verbosity.
    -n | --no-encrypt: Do not encrypt the private key. Private key encryption
        is the default, a password will be prompted in this case.
    -d | --directory <dir_name>: The directory where the script should cd into
        in order to read and write files necessary for its functionalities.
        If not provided, it defaults the current working directory, i.e.
        where the script is called and not where it is stored.
    -s | --key-size <key_size>: The RSA key size to use when generating a
        new public-private key pair to sign the module with. Considering the
        tools used, the provided value must be included between $MIN_KEY_SIZE
        and $MAX_KEY_SIZE. This option is not used when only testing. If not
        provided, it defaults to $key_size.
    -c | --cert-dur <cert_dur>: The duration in days the generated certificate
        - i.e. the RSA key pair - should be valid for. If not provided, it
        defaults to 5 * 365 = 1825 days.
    -a | --sign-algo <sign_algo>: The hash algorithm that should be used to
        sign the module with. Supported values are: sha1, sha224, sha256,
        sha384 and sha512. If not provided, it defaults to $sign_algo.
    -m | --module <module_name>: The kernel module's name, mandatory
        when managing a kernel module.
EOF

read -r -d '' DESC_DOC << EOF
Description:
    This script will help you sign a kernel module in order to use it when
    SecureBoot is enabled. Provide the kernel module's name and the script
    will, in order:
    * Check if the module was previously signed by testing if a file
      <module_name>.$PUB_KEY_EXT exists or not in the current or given
      directory and was used to register a key to the MOK manager. If it does,
      then it removes the previous signature from the MOK manager.
    * Generate a new public-private (by default $key_size bits) RSA key pair and
      write it to <module_name>.$PUB_KEY_EXT and <module_name>
      .$PRIV_KEY_EXT files.
    * Sign the module's kernel object file.
    * Enroll the new key to the MOK manager.

    When it is done and that no error was thrown, you should reboot the system
    in order to perform the registered MOK managing actions.
EOF

read -r -d '' HELP_DOC << EOF
$USAGE_DOC

$PARAMS_DOC

$DESC_DOC
EOF

# Usage string and error when there is no argument.
if [[ "$#" -eq "0" ]]; then
    echo "$USAGE_DOC" >&2
    exit $ARG_ERROR_CODE
fi

# Arguments parsing, reports its own errors.
args_tmp=$(getopt -o "h,t,v,n,d:,s:,c:,a:,m:"\
            -l "help,test,verbose,no-encrypt,directory:,key-size:,cert-dur:,sign-algo:,module:"\
            -n "$MY_NAME"\
            -s "bash"\
            -- "$@")

# Usage string and error if parsing throws an error.
if [[ "$?" -ne "0" ]]; then
    echo -e "\n$USAGE_DOC" >&2
    exit $ARG_ERROR_CODE
fi

# Set the parsed arguments as ours.
eval set -- "$args_tmp"
unset args_tmp

# Tests if $2 is in list $1.
function contains() {
    [[ "$1" =~ (^| )$2($| ) ]] && return 0 || return 1
}

# Main argument handling.
while true; do
    case "$1" in
        "-h" | "--help")
            echo "$HELP_DOC"
            exit 0
        ;;
        "-t" | "--test")
            to_test="true"
            shift
            continue
        ;;
        "-v" | "--verbose")
            ossl_verbosity="-verbose"
            mok_verbosity="true"
            shift
            continue
        ;;
        "-n" | "--no-encrypt")
            ossl_encrypt="-noenc"
            shift
            continue
        ;;
        "-d" | "--directory")
            base_dir="$2"
            dir_adj="given"

            # Report an error if the given directory is missing.
            if ! [[ -d "$base_dir" ]]; then
                echo "$base_dir $WRONG_DIR_ERROR_DOC" >&2
                exit $ARG_ERROR_CODE
            fi

            shift 2
            continue
        ;;
        "-s" | "--key-size")
            key_size="$2"

            # The RSA key size should be a 1-to-4-digit integer (max 4096).
            if ! [[ "$key_size" =~ ^[0-9]{1,4}$ ]]\
                    || [[ $key_size -lt $MIN_KEY_SIZE ]]\
                    || [[ $key_size -gt $MAX_KEY_SIZE ]]; then
                echo "$INV_KEY_SIZE_ERROR_DOC" >&2
                exit $ARG_ERROR_CODE
            fi

            shift 2
            continue
        ;;
        "-c" | "--cert-dur")
            cert_dur="$2"

            # The duration should be at least one digit long.
            if ! [[ "$cert_dur" =~ ^[0-9]+$ ]]\
                    || [[ $cert_dur -eq 0 ]]; then
                echo "$INV_CERT_DUR_ERROR_DOC" >&2
                exit $ARG_ERROR_CODE
            fi

            shift 2
            continue
        ;;
        "-a" | "--sign-algo")
            sign_algo="$2"

            # Check if the given algorithm is the list of supported algorithms.
            if ! contains "$SIGN_ALGOS_LIST" "$sign_algo"; then
                echo "$INV_SIGN_ALGO_ERROR_DOC" >&2
                exit $ARG_ERROR_CODE
            fi

            shift 2
            continue
        ;;
        "-m" | "--module")
            mod_name="$2"
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
            echo "$INT_ERROR_DOC" >&2
            exit $INT_ERROR_CODE
        ;;
    esac
done

# Give an error for each remaining unexpected argument and print the usage.
for rem_arg; do
    echo "Unknown argument: '$rem_arg'" >&2
    unkn_arg_det="true"
done
if [[ "$unkn_arg_det" = "true" ]]; then
    echo -e "\n$USAGE_DOC" >&2
    exit $ARG_ERROR_CODE
fi

# The module name is mandatory for the rest of the execution.
if [[ -z "${mod_name+x}" ]]; then
    echo "$MISS_MOD_ERROR_DOC" >&2
    exit $ARG_ERROR_CODE
fi

sudo mokutil --set-verbosity "$mok_verbosity"


# Handles the signing itself.
function sign_mod() {
    set -e
    local mod_file="$(modinfo --filename "$mod_name")"

    # Using OpenSSL directly is necessary in order to handle optional private
    # key encryption.
    echo "$LOG_HEADER""Signing module..."
    local tmp_priv_key_file="$(mktemp --tmpdir=/dev/shm/)"
    openssl rsa -in "$base_dir/$KEY_STEM.$PRIV_KEY_EXT" -out "$tmp_priv_key_file" >/dev/null 2>&1
    sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file "$sign_algo"\
        "$tmp_priv_key_file" "$base_dir/$KEY_STEM.$PUB_KEY_EXT" "$mod_file"
    rm "$tmp_priv_key_file"
    echo "$LOG_HEADER""Done."
}

# Generates a new public-private key pair.
function gen_cert() {
    # Generate the new key pair.
    echo "$LOG_HEADER""Generating new signing keys..."
    openssl req -new -x509 -outform DER -newkey rsa:"$key_size" -utf8 $ossl_encrypt\
                -keyout "$base_dir/$KEY_STEM.$PRIV_KEY_EXT" -days "$cert_dur"\
                -out "$base_dir/$KEY_STEM.$PUB_KEY_EXT" -"$sign_algo"\
                -subj "/CN=$USER's MOK certificate/" $ossl_verbosity
    echo "$LOG_HEADER""Done."

    # Register the certificate in the MOK keyring.
    echo "$LOG_HEADER""Registering keys to the MOK manager..."
    sudo mokutil --import "$base_dir/$KEY_STEM.$PUB_KEY_EXT"
    echo "$LOG_HEADER""Done."
}

# Tests the presence of a valid X.509 certificate at the default location and
# checks its state according to the MOK manager.
#
# $1: "true" | "false": whether the function should failfast or run all tests
#   and log things.
function test_cert() {
    # Check if a private key file exists and is correct.
    if openssl rsa -in "$base_dir/$KEY_STEM.$PRIV_KEY_EXT" -noout; then
        if [[ "$1" = "false" ]]; then
            echo "$LOG_HEADER$KEY_STEM.$PRIV_KEY_EXT in the base directory is"\
                "a valid RSA private key file."
        fi
    elif [[ "$1" = "true" ]]; then
        return 1
    else
        echo "$LOG_HEADER$KEY_STEM.$PRIV_KEY_EXT in the base directory does"\
            "not seem to be a valid RSA private key file."
    fi

    # Check if a public key file exists and is correct.
    if openssl x509 -in "$base_dir/$KEY_STEM.$PUB_KEY_EXT" -noout; then
        if [[ "$1" = "false" ]]; then
            echo "$LOG_HEADER""$KEY_STEM.$PUB_KEY_EXT in the base directory is"\
                "a valid X.509 certificate (public key) file."
        fi
    elif [[ "$1" = "true" ]]; then
        return 1
    else
        echo "$LOG_HEADER""$KEY_STEM.$PUB_KEY_EXT in the base directory does"\
            "not seem to be a valid X.509 certificate (public key) file."
    fi

    # Check its state according to the MOK manager.
    local cert_enrollment="$(sudo mokutil --test-key "$base_dir/$KEY_STEM.$PUB_KEY_EXT")"
    echo "$cert_enrollment"

    if [[ "$cert_enrollment" =~ is\senrolled$ ]]; then
        if [[ "$1" = "false" ]]; then
            echo "$LOG_HEADER""$KEY_STEM.$PUB_KEY_EXT in the base directory is"\
                "known by the MOK manager."
        fi
    elif [[ "$1" = "true" ]]; then
        return 1
    else
        echo "$LOG_HEADER""$KEY_STEM.$PUB_KEY_EXT in the base directory does"\
            "not seem to be known by the MOK manager."
    fi
}

# Runs a few helper tests.
function test_mod() {
    echo "$LOG_HEADER""Starting tests..."
    local mod_info="$(modinfo $mod_name)"

    # Determine if the module exists.
    if [[ "$?" -eq "0" ]]; then
        echo -e "$LOG_HEADER""The given module is:\n\n$mod_info\n"
    else
        echo "$LOG_HEADER""The given module doesn't seem to exist on the current system." >&2
    fi

    # Check if a private key file exists and is a text file.
    if [[ -f "$base_dir/$mod_name.$PRIV_KEY_EXT" ]]; then
        echo "$LOG_HEADER""$mod_name.$PRIV_KEY_EXT is a file in the $dir_adj directory."
        local file_info=$(file --brief --mime "$base_dir/$mod_name.$PRIV_KEY_EXT")

        if [[ "$file_info" = "$TXT_MIME_TYPE" ]]; then
            echo -e "\tIt seems to be a text file."
        else
            echo -e "\tBut it doesn't seem to be a text file: '$file_info'." >&2
        fi
    else
        echo "$LOG_HEADER""$mod_name.$PRIV_KEY_EXT is NOT a file in the $dir_adj directory."
    fi

    # Check if a public key exists as a "binary" file (DER) and display its
    # state according to the MOK manager.
    if [[ -f "$base_dir/$mod_name.$PUB_KEY_EXT" ]]; then
        echo "$LOG_HEADER""$mod_name.$PUB_KEY_EXT is a file in the $dir_adj directory."
        local file_info=$(file --brief --mime "$base_dir/$mod_name.$PUB_KEY_EXT")

        if [[ "$file_info" = "$BIN_MIME_TYPE" ]]; then
            echo -e "\tIt seems to be a binary data file."
        else
            echo -e "\tBut it doesn't seem to be a binary data file: '$file_info'." >&2
        fi

        # Has its own output.
        sudo mokutil --test-key "$base_dir/$mod_name.$PUB_KEY_EXT"
    else
        echo "$LOG_HEADER""$mod_name.$PUB_KEY_EXT is NOT a file in the $dir_adj directory."
    fi

    echo "$LOG_HEADER""Done."
}


# Main operation.
if [[ "$to_test" = "true" ]]; then
    test_cert false
    test_mod
else
    if ! test_cert true; then
        mkdir --parents "$base_dir"
        gen_cert
    fi

    sign_mod
fi
