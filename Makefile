build:
	pandoc index.md -o index.html --self-contained --template=../template.html --highlight-style ../dracula.theme --css ../custom-pandoc.css -f markdown-implicit_figures
