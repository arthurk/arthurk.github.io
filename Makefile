build:
	pandoc index.md -o index.html --self-contained --template=../_pandoc/pandoc-template.html --highlight-style ../_pandoc/pandoc-syntax-dracula.theme --css ../_pandoc/pandoc-style.css -f markdown-implicit_figures --syntax-definition ../_pandoc/pandoc-syntax.xml
