build:
	pandoc index.md -o index.html --self-contained --template=../pandoc-template.html --highlight-style ../pandoc-syntax-dracula.theme --css ../pandoc-style.css -f markdown-implicit_figures --syntax-definition ../pandoc-syntax.xml
