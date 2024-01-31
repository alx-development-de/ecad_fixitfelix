DOCS = pdf/ECAD-Export.pdf

SRC_DIR   := src/
BUILD_DIR := pdf/

SRCS = $(wildcard $(SRC_DIR)*.tex)
IMGS = $(wildcard src/*.png)

# You want latexmk to *always* run, because make does not have all the info.
# Also, include non-file targets in .PHONY so they are run regardless of any
# file of the given name existing.
.PHONY: all checkdirs clean

# The first rule in a Makefile is the one executed by default ("make"). It
# should always be the "all" rule, so that "make" and "make all" are identical.
all: checkdirs $(DOCS)

# MAIN LATEXMK RULE
$(BUILD_DIR)%.pdf: $(SRCS) $(IMGS)
	latexmk -pdf -cd -lualatex -use-make $<
	latexmk -c

checkdirs: $(BUILD_DIR)

$(BUILD_DIR):
	@mkdir -p $@

clean:
	@rm -rf $(BUILD_DIR)
