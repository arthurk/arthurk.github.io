+++
title = "Convert Markdown to HTML with Pandoc"
+++

In this post I'll describe how to use [Pandoc](https://pandoc.org/) to convert Markdown to a full HTML page (including header/footer).

The Pandoc version used for the examples below is 2.11.2.

## What is Pandoc?

Pandoc is an open-source document converter that is written in Haskell. It was initially
released in 2006 and has been under active development since then.

The goal of Pandoc is to convert a document from one markup format to another. It distinguishes
between input formats and output formats. As of writing this it supports [38 input formats](https://pandoc.org/MANUAL.html#input-formats) and
[59 output formats](https://pandoc.org/MANUAL.html#output-formats).

In this post we'll use Markdown as an input format and HTML as an output format.

## Preparing the HTML template

To generate a full HTML page we have to use Pandoc's standalone mode which will use a [template](https://pandoc.org/MANUAL.html#templates) to add header and footer.

Pandoc ships with a default template, if you wish to use that skip this section and omit the `--template` argument.

The template we'll use is this (save it to `template.html`):

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="date" content='$date-meta$'>
    <title>$title$</title>
  </head>
  <body>
    <p>Date: $date$</p>
$body$
  </body>
</html>
```

Pandoc's template variables can have [different formats](https://pandoc.org/MANUAL.html#interpolated-variables),
the one we're using here start and end with a dollar sign:

- `$date$`: A date in a parsable format. See the [date-meta docs](https://pandoc.org/MANUAL.html#variables-set-automatically) for a list of recognized formats for the `date` variable. We use this to show when the document was created
- `$date-meta$`: The `date` parsed to ISO 8601 format. This is automatically done
- `$title$`: The document title
- `$body$`: The document body in HTML (the converted Markdown)

We only need to set the `date` and `title` in the Markdown document via a metadata block.

## Writing the Markdown file

Create a Markdown file `doc.md` with the following content:

```
---
title: My Document
date: September 22, 2020
---

## Test
some text
```

The beginning of the document is the metadata block with required `date` and `title` variables mentioned above.

Several Markdown variants are [supported](https://pandoc.org/MANUAL.html#Markdown-variants) such as GitHub-Flavored markdown. This example uses [Pandoc's extended markdown](https://pandoc.org/MANUAL.html#pandocs-markdown) which is the default input for files with the `md` extension. 

## Converting the document

Run the following command to generate the HTML page:

```
pandoc --standalone --template template.html doc.md
```

Pandoc will try to guess the input format from the file extension (`.md` will use the Markdown input format) and output
it to HTML (the default output format). 

The output will be printed to the terminal:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="date" content='2020-09-22'>
    <title>My Document</title>
  </head>
  <body>
    <p>Date: September 22, 2020</p>
<h2 id="test">Test</h2>
<p>some text</p>
  </body>
</html>
```

To save the document to a file we can either redirect stdout or use the `-o` argument:

```
pandoc --standalone --template template.html doc.md -o doc.html
```

## Conclusion

In this example we've converted Markdown to a standalone HTML page that is using a custom template.

This was just a simple example of what Pandoc is capable to do. The standalone mode coupled with the
bundled default templates makes it easy to generate a wide variety of outputs such as HTML presentations, Jupyter notebooks or PDF documents.
