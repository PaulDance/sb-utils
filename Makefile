# Use this Makefile with the GNU program make. Just run `make install` from a shell
# in order to copy `signmod.sh` to `/usr/bin/` and give it proper execution rights.
# In case a file `signmod.sh` already exists in `/usr/bin/`, then it will first try
# to `stat` it to determine if its modification date is newer than the local file
# stored in the repo: if it is not, then it will warn you and ask if it should force
# the copying or not - i.e. replace the file named `signmod.sh` in `/usr/bin/` by
# the one in the repo.


# SCRipt name.
SCR="signmod.sh"

# Output HeaDer
OHD="[make]"


# Default target is install for now and it is a phony target.
.DEFAULT_GOAL := install
.PHONY := install

# Installing here is just copying the script file and giving it proper rights.
install:
	@echo "$(OHD) Copying '$(SCR)' to '/usr/bin/'..."
	@sudo cp -f -i -u "$(SCR)" /usr/bin/
	@echo "$(OHD) Done."
	@echo "$(OHD) Adding execution rights..."
	@sudo chmod 755 "/usr/bin/$(SCR)"
	@echo "$(OHD) Done."

