package main

import (
	"fmt"
	"github.com/PuerkitoBio/goquery"
	"github.com/gorilla/feeds"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var root = "../"
var baseUrl = "https://www.arthurkoziel.com"
var author = feeds.Author{Name: "Arthur Koziel", Email: "arthur@arthurkoziel.com"}

func FilePathWalkDir(root string) ([]string, error) {
	var files []string

	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			log.Printf("prevent panic by handling failure accessing a path %q: %v\n", path, err)
			return err
		}

		// skip git directory
		if info.IsDir() && info.Name() == ".git" {
			log.Println("Skipping .git dir")
			return filepath.SkipDir
		}

		// skip root index.html
		if path == "../index.html" {
			log.Println("skipping root index.html")
			return nil
		}

		// append only if filename is index.html
		if info.Name() == "index.html" {
			files = append(files, path)
		}

		return nil
	})

	return files, err
}

func GetFeedItem(filePath string) *feeds.Item {
	// Open file for reading
	f, err := os.Open(filePath)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	// Parse file with goquery
	doc, err := goquery.NewDocumentFromReader(f)
	if err != nil {
		log.Fatal(err)
	}

	// Get values from html
	header := doc.Find("article h1").Text()
	dateVal, exists := doc.Find("article time").Attr("datetime")
	if exists == false {
		log.Fatal("Couldn't get date in file", f.Name())
	}
	date, err := time.Parse("2006-01-02", dateVal)
	if err != nil {
		log.Fatal(err)
	}

	body, _ := doc.Find("article").Html()
	urlPath := strings.TrimRight(strings.TrimLeft(filePath, root), "index.html")

	// Create Feed item
	return &feeds.Item{
		Title:   header,
		Link:    &feeds.Link{Href: baseUrl + "/" + urlPath},
		Author:  &author,
		Created: date,
		Content: body,
	}
}

func main() {
	// Feed Metadata
	feed := &feeds.Feed{
		Title:       "Arthur Koziel's Blog",
		Link:        &feeds.Link{Href: baseUrl},
		Description: "Arthur Koziel's Blog",
		Author:      &author,
		Created:     time.Now(),
	}

	// get a list of all files to parse
	files, err := FilePathWalkDir(root)
	if err != nil {
		log.Fatal(err)
	}

	// Create feed items
	for _, file := range files {
		feed.Add(GetFeedItem(file))
	}

	// Sort by date
	feed.Sort(func(a, b *feeds.Item) bool {
		return a.Created.After(b.Created)
	})

	// Generate Atom feed
	rss, err := feed.ToAtom()
	if err != nil {
		log.Fatal(err)
	}

	// output feed to stdout
	fmt.Println(rss)
}
