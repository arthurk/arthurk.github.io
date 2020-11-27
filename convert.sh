#!/usr/bin/env bash

pandoc -s "$PWD/$1" \
	-f markdown-implicit_figures \
	--template `dirname "$0"`/template.html
