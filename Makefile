SCR="signmod.sh"										# SCRipt name.
OHD="[make]"											# Output HeaDer.

.DEFAULT_GOAL := install								# Default is install for now;
.PHONY := install										# it is a phony target.

install:
	@echo "$(OHD) Copying '$(SCR)' to '/usr/bin/'..."	# Installing here is just
	@sudo cp -f -i -u "$(SCR)" /usr/bin/				# copying the script file
	@echo "$(OHD) Done."
	@echo "$(OHD) Adding execution rights..."
	@sudo chmod 755 "/usr/bin/$(SCR)"					# and giving it proper right.
	@echo "$(OHD) Done."

