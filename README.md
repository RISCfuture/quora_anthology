# Quora Anthology Generator

This Ruby project is a collection of scripts that generates a PDF book anthology
of all your Quora answers, using XeTeX. The resulting PDF is beautifully typeset
and ideal for reading in print or eBook form.

## Requirements

The Anthology Generator requires the following:

* A modern version of Ruby (2.4.2 is targeted);
* A TeX installation with XeTeX support, the `book` layout, and the following
  packages: `csquotes`, `graphicx`, `babel`, `tikz`, `imakeindex`, and
  `hyperref`;
* ImageMagick;
* Google Chrome;
* and the [ChromeDriver binary](http://chromedriver.storage.googleapis.com/index.html)
  for scraping the Quora website.
  
## Installation

The Gemfile lists all the project's dependencies. Simply type `bundle install`
to install all necessary gems (requires the Bundler gem to be installed first).

## Setup

To use the scraping feature, you must set up a `config.yml` file with your Quora
email and password. Use the `config.example.yml` file as a starting point.

You'll also want to edit the `config/sections.csv` and `config/topics.csv` 
files. These files are used to organize your answers into different parts and
chapters in the book. The `config/topics.csv` is a two-column CSV table that
maps a Quora topic to a book chapter. Quora topics are varied and 
overly-specific (e.g., "Ruby (programming language)") -- this CSV file maps each 
topic to a more general chapter name (e.g., "Software Development"). You can get 
a unique list of all topics you have answered questions under after getting to 
step 3 of the instructions with the following code:

```` ruby
require 'json'
JSON.parse(File.read('build/answers.json')).map { |a| a['topics'] }.flatten.uniq
````

Use this as the basis for your own `topics.csv` file.

The `sections.csv` file is used to organize the layout of your book. After
choosing chapters in the topics.csv file, you organize those chapters into parts
with this file. Each row is a part. The first element of the row is the name of
the part, and all remaining elements are the names of the chapters under that
part (in order). These chapters should be identical in name to the chapters used
in topics.csv.

You can create a "miscellaneous" chapter for all Quora answers under topics that
are not mapped in topics.csv. To do this, end the chapter name with a bang
("!"). That chapter (without the exclamation point) will include all other Quora 
answers not organized into a different chapter.

## Usage

This project contains four scripts which are to be executed in order, in order
to create your anthology. You can re-run a single script if it should fail. This
allows you to (for example) re-parse your already downloaded Quora answers 
without having to download them again, and risk running into rate limiting.

Each of these scripts can be run with no command-line options.

### Script the First: 1_list.rb

**Warning:** This script has not been fully tested, as I ran into security 
issues with my Quora account in the process of testing it. If you don't feel 
like using it, see **Alternate Instructions** below.

This script uses the Chrome driver to automatically log into Quora and download
a list of answer URLs from the Your Content page. When completed, the list
should be in `build/answer_urls.txt`. The `chromedriver` binary must be in your
PATH.

#### Alternate Instructions

Should you not want to deal with scraping and driving browsers, simply log in to
Quora on your own and go to the Your Content page, then click the Answers link.
Repeatedly hit Page Down and scroll to the end until the infinite scrolling
feature stops and you have all of your past answers displayed on the page at 
once. Open up a console window and type the following:

```` javascript
ls = []; document.querySelectorAll('a.question_link').forEach(function(a) { ls.push(a.getAttribute('href')) }); console.log(ls.join("\n"))
````

Place the output in a text file at `build/answer_urls.txt`.

### Script the Second: 2_scrape.rb

This script downloads the HTML for all of the answer pages in answer_urls.txt.
Answers are downloaded into the `build/answers` directory. It's recommended to
run this script only once if at all possible to avoid being rate-limited.

### Script the Third: 3_parse.rb

This script parses the answers downloaded into `build/answers` and extracts
information such as the question, answer, date written, and number of upvotes.
It also restructures and sanitizes the question and answer HTML in preparation
for conversaion to TeX.

The resulting answer information is stored in JSON format at
`build/answers.json`.

### Script the Fourth: 4_generate.rb

This script converts the question and answer HTML into XeTex and generates the
TeX file, then uses the `xelatex` binary to create the PDF. This binary must be
in your PATH.

Before running this script, ensure your name is properly set in the `config.yml`
file. (Use the `config.example.yml` file as a starting point.)

The finished TeX file will be at `build/latex/book.tex` and the final PDF will
be at `build/latex/book.pdf`.

As part of this process, the script downloads all images and YouTube embed
thumbnails into the `build/figures` directory. Images that have already been
downloaded into this directory are not re-downloaded on subsequent runs. 
ImageMagick is used to determine the proper file extension for these images, and
to convert incompatible image formats as necessary.

YouTube videos that do not have a thumbnail use a generic YouTube icon, located
at `figures/youtube.pdf`.

This script attempts to generate internal references if your answers include
links to other questions you've answered. To accomplish this, ensure that the
`quora_profile_slug` value is set correctly in `config.yml`. You can get your
profile slug by visiting your profile page on Quora and noting the URL.

## Known Issues and Improvements

* The very last page of the index has an incorrect header and footer. Need a
  TeXpert to help me with that one. 
* One of my answers intersperses Russian and English, so I support detecting
  Russian from text and wrapping it with the appropriate Babel command. That's
  the only language, however.
