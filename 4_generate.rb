require 'bundler'
Bundler.require
require './common'
require 'csv'
require 'fileutils'
require 'open-uri'
require 'digest/md5'
require 'securerandom'

require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/string/inflections'
require 'active_support/dependencies/autoload'
require 'active_support/concern'
require 'action_view/helpers'
include ActionView::Helpers::NumberHelper
include ActionView::Helpers::SanitizeHelper

$config         = YAML.load_file('config/config.yml')
$section_labels = Hash.new

def escape_tex(str)
  out = RubyPants.new(str, [2], {
      single_left_quote:  '‘',
      double_left_quote:  '“',
      single_right_quote: '’',
      double_right_quote: '”',
      em_dash:            '–',
      en_dash:            '—',
      ellipsis:           '…'
  }).to_html

  out.gsub!("\n", '') # newlines don't matter

  out.gsub!('\\', '\\textbackslash{}')
  out.gsub!(/(?<!\\textbackslash)\{/, '\\{')
  out.gsub!(/(?<!\\textbackslash\{)\}/, '\\}')
  out.gsub!('#', '\\#')
  out.gsub!('$', '\\$')
  out.gsub!('%', '\\%')
  out.gsub!('&') { '\\&' }
  out.gsub!('_', '\\_')
  out.gsub!('^', '\\textasciicircum{}')
  out.gsub!('~', '\\textasciitilde{}')
  out.gsub!('>', '\\textgreater{}')
  out.gsub!('<', '\\textless{}')
  out.gsub!('`', '\\textprime{}')
  out.gsub!('[', '{[}')
  out.gsub!(']', '{]}')

  out.gsub!("\u200b", '') # zero width space
  # out.gsub!("\u2002", '{\\enspace}') # en space
  out.gsub!("\u0097", '') # bullshit
  # out.gsub!("\u2a09", '$\\times$') # n-ary times

  # ruby pants stuff
  out.gsub! '‘', '`'
  out.gsub! '’', "'"
  out.gsub! '“', '``'
  out.gsub! '”', "''"
  out.gsub! '”', "''"
  out.gsub! '–', "\\textendash{}"
  out.gsub! '—', "\\textemdash{}"
  out.gsub! '…', "\\textellipsis{}"

  # cryllic is russian
  out.gsub! /([\u{0400}-\u{04F9}]+)/, "\\foreignlanguage{russian}{\\1}"

  return out
end

class HTMLParser < Nokogiri::XML::SAX::Document
  attr_accessor :latex

  def initialize
    self.latex = String.new
  end

  def characters(string)
    if @math_mode
      latex << string
    else
      latex << escape_tex(string)
    end
  end

  def start_element(name, attrs = [])
    case name
      when 'p'
      when 'br'
        latex << "\n\n"
      when 'b'
        latex << "\\textbf{"
      when 'i'
        latex << "\\textit{"
      when 'a'
        url = attrs.to_h['href']
        if url.end_with?("/answer/#{$config['quora_profile_slug']}") # internal reference
          if (answer = $answers.detect { |a| a.permalink == url })
            @current_link = answer
          end
          latex << "\\textbf{{"
        elsif url.start_with?('/') # quora link
          # try seeing if we can make it an answer link
          test_url = url + "/answer/#{$config['quora_profile_slug']}"
          if (answer = $answers.detect { |a| a.permalink == test_url })
            @current_link = answer
            latex << "\\textbf{{"
          else
            latex << "\\href{https://quora.com" << url << "}{\\textbf{"
          end
        else
          latex << "\\href{" << url << "}{\\textbf{"
        end
      when 'ul'
        latex << "\\begin{itemize}\n"
      when 'ol'
        latex << "\\begin{enumerate}\n"
      when 'li'
        latex << "\\item "
      when 'embed'
        source      = "https://www.youtube.com/watch?v=#{attrs.to_h['src']}"
        thumb       = attrs.to_h['thumbnail']
        filename, _ = download_image(thumb, placeholder: 'figures/youtube.pdf')
        label       = SecureRandom.uuid
        latex << <<-LATEX

\\begin{figure}
  \\centering
  \\includegraphics[width=3in,height=2in]{#{filename}}
  \\caption{Embedded \\href{#{source}}{\\textbf{YouTube video}}}
  \\label{fig:#{label}}
\\end{figure}

(See figure \\ref{fig:#{label}})

        LATEX
      when 'img'
        source            = attrs.to_h['src']
        filename, was_gif = download_image(source)
        label             = SecureRandom.uuid
        if filename.nil?
          latex << <<-LATEX

\\begin{figure}
  \\centering
  \\begin{tikzpicture}
  \\draw[dashed] (0,0) -- (2,0) -- (2,3) -- (0,3) -- (0,0);
  \\end{tikzpicture}
  \\caption{Missing or corrupt image}
  \\label{fig:#{label}}
\\end{figure}

(See figure \\ref{fig:#{label}})

          LATEX
        elsif was_gif
          latex << <<-LATEX

\\begin{figure}
  \\centering
  \\includegraphics[width=3in,height=2in,keepaspectratio]{#{filename}}
  \\caption{Embedded \\href{#{source}}{\\textbf{Animated GIF}}}
  \\label{fig:#{label}}
\\end{figure}

(See figure \\ref{fig:#{label}})

          LATEX
        else
          latex << <<-LATEX

\\begin{figure}
  \\centering
  \\includegraphics[width=3in,height=2in,keepaspectratio]{#{filename}}
  \\caption{}
  \\label{fig:#{label}}
\\end{figure}

(See figure \\ref{fig:#{label}})

          LATEX
        end
      when 'hr'
        latex << "\n\n\\noindent\\hfil\\rule{0.5\\textwidth}{.4pt}\\hfil\n\n"
      when 'blockquote'
        latex << "\\begin{displayquote}\n"
      when 'wbr'
      when 'h2'
        latex << "\\subsection{"
      when 'math'
        @math_mode = true
        latex << '$'
      when 'pre'
        @math_mode = true
        latex << "\n\\begin{lstlisting}\n"
      when 'code'
        latex << "\\texttt{" unless @math_mode
      when 'html', 'body'
      else
        latex << "<#{name} #{attrs.map { |(a, b)| "#{a}=\"#{b}\"" }.join(' ')}>"
    end
  end

  def end_element(name)
    case name
      when 'p'
        latex << "\n\n"
      when 'br'
      when 'b'
        latex << '}'
      when 'i'
        latex << '}'
      when 'a'
        latex << '}}'
        if @current_link
          latex << " (section \\ref{sec:#{Digest::MD5.hexdigest @current_link.permalink}})"
        end
        @current_link = nil
      when 'ul'
        latex << "\n\\end{itemize}\n\n"
      when 'ol'
        latex << "\n\\end{enumerate}\n\n"
      when 'li'
        latex << "\n"
      when 'embed'
      when 'img'
      when 'hr'
      when 'blockquote'
        latex << "\n\\end{displayquote}\n\n"
      when 'wbr'
      when 'h2'
        latex << "}\n"
      when 'math'
        @math_mode = false
        latex << '$'
      when 'pre'
        @math_mode = false
        latex << "\n\\end{lstlisting}\n\n"
      when 'code'
        latex << "}" unless @math_mode
      when 'html', 'body'
      else
        latex << "</#{name}>"
    end
  end

  private

  IMAGES_PATH = 'build/figures/'

  def download_image(url, placeholder: nil)
    filename   = Digest::MD5.hexdigest(url)
    candidates = Dir.glob(IMAGES_PATH + filename + '*')
    if candidates.empty?
      puts " -- Downloading #{url} ..."
      begin
        File.open(IMAGES_PATH + filename, 'wb') { |outfile| IO.copy_stream open(url), outfile }
      rescue OpenURI::HTTPError
        FileUtils.rm "#{IMAGES_PATH}#{filename}"
        puts "   Got error #{$!}; using placeholder"
        if placeholder
          FileUtils.cp placeholder, IMAGES_PATH + File.basename(placeholder)
          return File.basename(placeholder), false
        else
          raise
        end
      end

      if (identity = `identify #{IMAGES_PATH}#{filename}`.presence)
        extension = identity.split(' ')[1].downcase
        FileUtils.mv "#{IMAGES_PATH}#{filename}", "#{IMAGES_PATH}#{filename}.#{extension}"
        if extension == 'gif'
          # first check if it's animated
          was_animated = `identify -format "%n" "#{IMAGES_PATH}#{filename}.gif`.to_i > 1
          system 'convert', "#{IMAGES_PATH}#{filename}.gif[0]", "#{IMAGES_PATH}#{filename}.png"
          return "#{IMAGES_PATH}#{filename}.png", was_animated
        end
        return "#{filename}.#{extension}", false
      else
        return filename, false
      end
    else
      was_animated = false
      if (gif = candidates.detect { |c| c.end_with? '.gif'})
        was_animated = `identify -format "%n" #{gif}`.to_i > 1
      end
      return File.basename(candidates.detect { |c| !c.end_with?('.gif') }), was_animated
    end
  end
end

def html2tex(html, one_line: false)
  handler = HTMLParser.new
  parser  = Nokogiri::HTML::SAX::Parser.new(handler)
  parser.parse(html)

  latex = handler.latex.strip

  # \LaTeX is not really a math mode thing
  latex.gsub! '$\\LaTeX$', '\\LaTeX'

  return latex
end

template = File.read('template.tex')
topics   = Hash[*CSV.read('config/topics.csv').flatten]
parts = CSV.read('config/sections.csv').map { |row| [row.first, row[1..-1]] }

answers_json = JSON.parse(File.read('build/answers.json'))
$answers     = answers_json.map { |a| Answer.from_json a }

# normalize topics
$answers.each do |answer|
  answer.topics = answer.topics.map { |t| topics[t] }.compact.mode
end

FileUtils.mkdir_p 'build/figures'
content = "\\graphicspath{{#{File.absolute_path 'build/figures'}/}}\n\n"

parts.each do |(part, chapters)|
  content << "\\part{#{part}}\n\n"
  content << "\\renewcommand{\\parttitle}{#{part}}"
  chapters.each do |chapter|
    chapter_answers = $answers.select { |a| chapter.end_with?('!') ? a.topics.nil? : a.topics == chapter }.sort_by { |a| strip_tags a.title }
    content << "\\chapter{#{chapter.sub(/!$/, '')}}\n\n"

    chapter_answers.each do |answer|
      content << "\\section{#{html2tex(answer.title, one_line: true)}}\n"
      content << "\\index{#{html2tex(answer.title, one_line: true)}}\n"
      content << "\\label{sec:#{Digest::MD5.hexdigest answer.permalink}}\n"
      if answer.description
        content << "\\nopagebreak\n"
        content << "\\begin{sffamily}\n"
        content << "\\begin{footnotesize}\n"
        content << html2tex(answer.description) << "\n"
        content << "\\end{footnotesize}\n"
        content << "\\end{sffamily}\n"
      end
      content << "\n"

      content << html2tex(answer.answer) << "\n\n\\nopagebreak\n\n"
      content << "\\textit{\\footnotesize{Written on #{answer.date.strftime '%B %-d, %Y'}. Received #{number_with_delimiter answer.upvotes} #{'upvote'.pluralize answer.upvotes}.}}\n\n"
    end
  end
end

content.gsub!(/\n{3,}/, "\n\n")

template.gsub!('%content%') { content }
template.gsub!('%name%') { $config['name'] }
File.open('build/book.tex', 'w') { |f| f.puts(template) }

FileUtils.rm_rf 'build/latex'
FileUtils.mkdir_p 'build/latex'
Dir.chdir 'build/latex'
File.open('book.tex', 'w') { |f| f.puts(template) }
system 'xelatex', 'book.tex' # once for main layout
system 'xelatex', 'book.tex' # again for xrefs and TOC
system 'makeindex', 'book.idx'
system 'xelatex', 'book.tex' # again for index
Dir.chdir '../..'
