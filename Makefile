# Makefile

ECHO = $(PERL) -l -e "binmode STDOUT, qq{:raw}; print qq{@ARGV}" --

NOOP = rem
NOECHO = @
DEV_NULL = > NUL

# --- Special targets section:
.PHONY : all clean

# --- Check if the OS is Windows
ifeq ($(OS),Windows_NT)
    MAKE_WINDOWS := $(MAKE) -f Makefile.win
else
    MAKE_WINDOWS := $(NOECHO) $(ECHO) Actually only configured to be build on Windows systems
endif

all:
	$(MAKE_WINDOWS) $@

clean:
	$(MAKE_WINDOWS) $@
