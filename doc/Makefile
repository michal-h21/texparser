doc_base = texparser-doc
tex_source = $(doc_base).tex
html_doc = $(doc_base).html
pdf_doc = $(doc_base).pdf

ifeq ($(strip $(shell git rev-parse --is-inside-work-tree 2>/dev/null)),true)
	VERSION:= $(shell git --no-pager describe --abbrev=0 --tags --always )
	DATE:= $(firstword $(shell git --no-pager show --date=short --format="%ad" --name-only))
endif

All: $(pdf_doc) $(html_doc)

$(pdf_doc): $(tex_source)
	latexmk -pdf -pdflatex='lualatex "\def\version{${VERSION}}\def\gitdate{${DATE}}\input{%S}"' $<

$(html_doc): $(tex_source)
	make4ht -ulm draft -c config.cfg -f html5+tidy+latexmk_build  ${HTML_DOC_DIR} $< "" "" "" "\"\def\version{${VERSION}}\def\gitdate{${DATE}}\""
