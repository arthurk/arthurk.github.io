#!/usr/bin/env bash

pandoc -s index.md -fmarkdown-implicit_figures --template=../template.html -o index.html
