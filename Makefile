build:
	pandoc index.md -o index.html --standalone --template=../_pandoc/pandoc-template.html --highlight-style ../_pandoc/pandoc-syntax-dracula.theme -f markdown-implicit_figures --syntax-definition ../_pandoc/pandoc-syntax.xml
