# sb-utils
##### Utilities to manage Secure Boot signatures

This repository is intended to offer a variety of easy-to-use helper utilities
in order to manage Secure Boot signatures in a faster way. As of now, there is
only `signmod.sh`, a simple script aiming to automate the signing of kernel
modules object files.


### Installation

There is no particular configuration required when downloading this repository,
just run `git clone https://github.com/PositivePaulo/sb-utils.git` from a shell
and it will get the entire repository. If you don't have access to shell or don't
have git installed on your current system, you can also use the "Download as ZIP"
button to download the tracked files only.

Then, optionnaly, you can run `make install` from a shell in the repository
directory in order to copy the script file to `/usr/bin/` and give it proper
execution rights, thus making it available to all, without having to use the path
leading to the repository.

In case a file `signmod.sh` already exists in `/usr/bin/`, then it will first try
to `stat` it to determine if its modification date is newer than the local file
stored in the repo: if it is not, then it will warn you and ask if it should force
the copying or not - i.e. replace the file named `signmod.sh` in `/usr/bin/` by
the one in the repo.



## signmod.sh

`signmod.sh` is a small shell script that will help you generate a new public-
private key pair, sign a kernel module with it and add if to the MOK manager in
order to facilitate certification of modules for Secure Boot. As of now, it is
meant to be used with the bash shell, but options will soon be assessed to make
it compatible with the standard sh shell.

Current functionalities include:
   * Standard arguments parsing, run `./signmod.sh -h` to get started.
   * Testing the existence on the current system of a given kernel module,
     checking if older key files are present in the directory and if the
	 public DER key is registered in the MOK manager.
   * Generating a new public-private key pair, signing a module with it and
     enrolling it to the MOK manager.

#### Requirements

This script needs to be able to execute `openssl`, `mokutil`, `sign-file` (from
`/usr/src/linux-headers-$(uname -r)/scripts/`) and `modinfo` as root, and `getopt`
(from the util-linux package) in order to function properly. However, it is **NOT**
meant to be ran itself as root, as files written will then be owned by root. Simply
run it from your account and it will `sudo` the necessary calls.
