.PHONY : all clean clean-temp
filename=ECAD-Export

all: pdf

pdf: ${filename}.tex aux toc bbl
	pdflatex $<
	# Run it twice to handle the page numbers correctly
	pdflatex $<

aux: ${filename}.tex
	pdflatex $<

toc: ${filename}.tex
	pdflatex $<

bbl: aux bib
	bibtex $*
	
clean: clean-temp
	-rm *.pdf

clean-temp:
	-rm *.ps
	-rm *.dvi
	-rm *.toc
	-rm *.aux
	-rm *.log
	-rm *.out
	-rm *.lof
	-rm *.bib~*
	-rm *.bbl
	-rm *.blg
	-rm *.lol
	-rm *.lot
	-rm *.synctex.gz
