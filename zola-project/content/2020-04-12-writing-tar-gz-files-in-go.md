+++
title = "Writing tar.gz files in Go"
date = "2020-04-12"
+++

In this blog post I'm going to explain how to use the Go `archive/tar` and `compress/gzip` packages to create a tar archive and compress it with gzip.

Below is the full example code and after that there's an explanation of the parts.

Full Code
---------

```go
package main

import (
	"io"
	"archive/tar"
	"compress/gzip"
	"log"
	"fmt"
	"os"
)

func main() {
	// Files which to include in the tar.gz archive
	files := []string{"example.txt", "test/test.txt"}

	// Create output file
	out, err := os.Create("output.tar.gz")
	if err != nil {
		log.Fatalln("Error writing archive:", err)
	}
	defer out.Close()

	// Create the archive and write the output to the "out" Writer
	err = createArchive(files, out)
	if err != nil {
		log.Fatalln("Error creating archive:", err)
	}

	fmt.Println("Archive created successfully")
}

func createArchive(files []string, buf io.Writer) error {
	// Create new Writers for gzip and tar
	// These writers are chained. Writing to the tar writer will
	// write to the gzip writer which in turn will write to
	// the "buf" writer
	gw := gzip.NewWriter(buf)
	defer gw.Close()
	tw := tar.NewWriter(gw)
	defer tw.Close()

	// Iterate over files and add them to the tar archive
	for _, file := range files {
		err := addToArchive(tw, file)
		if err != nil {
			return err
		}
	}

	return nil
}

func addToArchive(tw *tar.Writer, filename string) error {
	// Open the file which will be written into the archive
	file, err := os.Open(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	// Get FileInfo about our file providing file size, mode, etc.
	info, err := file.Stat()
	if err != nil {
		return err
	}

	// Create a tar Header from the FileInfo data
	header, err := tar.FileInfoHeader(info, info.Name())
	if err != nil {
		return err
	}

	// Use full path as name (FileInfoHeader only takes the basename)
	// If we don't do this the directory strucuture would
	// not be preserved
	// https://golang.org/src/archive/tar/common.go?#L626
	header.Name = filename

	// Write file header to the tar archive
	err = tw.WriteHeader(header)
	if err != nil {
		return err
	}

	// Copy file content to tar archive
	_, err = io.Copy(tw, file)
	if err != nil {
		return err
	}

	return nil
}
```

Explanation
-----------

In the main function we first declare `files` as a string slice. It contains the paths of the files that will be included in the archive.

For this example I've created two text files. I placed one of them in the same directory as the `main.go` file and the other one in a subdirectory. The purpose of this is to test that the directory structure will be correctly restored after extraction.

We then create the output file with `[os.Create()](https://golang.org/pkg/os/#Create)` and pass it to the `createArchive` function along with our file paths.

```go
func main() {
	// Files which to include in the tar.gz archive
	files := []string{"example.txt", "test/test.txt"}

	// Create output file
	out, err := os.Create("output.tar.gz")
	if err != nil {
		log.Fatalln("Error writing archive:", err)
	}
	defer out.Close()

	// Create the archive and write the output to the "out" Writer
	err = createArchive(files, out)
	if err != nil {
		log.Fatalln("Error creating archive:", err)
	}

	fmt.Println("Archive created successfully")
}
```

The `createArchive` function creates two Writer: The [tar Writer](https://golang.org/pkg/archive/tar/#NewWriter) and the [gzip Writer](https://golang.org/pkg/compress/gzip/#NewWriter). Both implement the [io.Writer](https://golang.org/pkg/io/#Writer) interface.

The Writers are chained which means that bytes written to the tar Writer `tw` will simultaneously be written to the gzip Writer `gw`.

We will then iterate over the files in the `files` slice and call the `addToArchive` function for each of them with the filename and the tar Writer as arguments.

```go
func createArchive(files []string, buf io.Writer) error {
	// Create new Writers for gzip and tar
	// These writers are chained. Writing to the tar Writer will
	// write to the gzip writer which in turn will write to
	// the "buf" writer
	gw := gzip.NewWriter(buf)
	defer gw.Close()
	tw := tar.NewWriter(gw)
	defer tw.Close()

	// Iterate over files and and add them to the tar archive
	for _, file := range files {
		err := addToArchive(tw, file)
		if err != nil {
			return err
		}
	}

	return nil
}
```

Inside the `addToArchive` function we open the file and get a `[FileInfo](https://golang.org/pkg/os/#FileInfo)`. The FileInfo contains information such as the file name, size or mode which is necessary for the next step.

```go
	// Open the file which will be written into the archive
	file, err := os.Open(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	// Get FileInfo about our file providing file size, mode, etc.
	info, err := file.Stat()
	if err != nil {
		return err
	}
```

Each file in a tar archive has a [header](https://golang.org/pkg/archive/tar/#Header) containing metadata about the file followed by the file content. In this step we create the header by calling [FileInfoHeader](https://golang.org/pkg/archive/tar/#FileInfoHeader) which will take our FileInfo `info` and generate a valid tar Header from it.

The os.FileInfo `info` only stores the base name of the file. For example if we pass in `test/test.txt` it will only store the filename `test.txt`. This is a problem when creating the tar archive as it would omit the directory structure of our files. To fix this we have to set `header.Name` to the full file path.

```go
	// Create a tar Header from the FileInfo data
	header, err := tar.FileInfoHeader(info, info.Name())
	if err != nil {
		return err
	}

	// Use full path as name (FileInfoHeader only takes the basename)
	// If we don't do this the directory strucuture would
	// not be preserved
	// https://golang.org/src/archive/tar/common.go?#L626
	header.Name = filename
```

Now we can write the header and the file content to the Writer.

```go
	// Write file header to the tar archive
	err = tw.WriteHeader(header)
	if err != nil {
		return err
	}

	// Copy file content to tar archive
	_, err = io.Copy(tw, file)
	if err != nil {
		return err
	}
```

Run the program
---------------

We can now run our program and check that the files can be extracted.

```
$ go run main.go
Archive created successfully

$ tar xzfv output.tar.gz
x example.txt
x test/test.txt

$ exa --tree
.
├── example.txt
├── output.tar.gz
└── test
   └── test.txt
```

Both files have been extracted successfully.
