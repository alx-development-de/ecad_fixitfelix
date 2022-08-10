.PHONY : all clean clean-temp

all: pdf

pdf: ECAD-Export.tex aux toc
	pdflatex $<
	# Run it twice to handle the page numbers correctly
	pdflatex $<

aux: ECAD-Export.tex
	pdflatex $<

toc: ECAD-Export.tex
	pdflatex $<

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
