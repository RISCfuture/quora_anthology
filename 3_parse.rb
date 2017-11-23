require 'bundler'
Bundler.require
require 'active_support/core_ext/numeric/time'
require './common'

def translate_qtext(html)
  return nil unless html
  out = html.dup

  # replace div.qtext_para with paragraphs
  out.css('div.qtext_para').each do |div|
    p            = Nokogiri::XML::Node.new('p', html)
    p.inner_html = div.inner_html
    div.add_next_sibling p
    div.remove
  end

  # unwrap images
  out.css('div.qtext_image_wrapper').each do |div|
    div.add_next_sibling div.children
    div.remove
  end

  # fix up images
  out.css('img').each do |img|
    if img['master_src'].present?
      img['src'] = img['master_src']
    elsif img['data-src'].present?
      img['src'] = img['data-src']
    end
    img['src'] = img['src'].sub(/\?convert_to_webp=true$/, '')
    img.attributes['master_src'].try! :remove
    img.attributes['data-src'].try! :remove
    img.attributes['class'].try! :remove
    img.attributes['master_w'].try! :remove
    img.attributes['master_h'].try! :remove
  end

  # Change Quora links to an emphasized style
  out.css('span.qlink_container').each do |span|
    a         = Nokogiri::XML::Node.new('a', html)
    a.content = span.css('a').first.text
    a['href'] = span.css('a').first['href']
    span.add_next_sibling a
    span.remove
  end

  # Find math tags and make them more HTML-y
  out.search('text()').each do |text|
    mapped_text = text.content.gsub(/\[math\](.+?)\[\/math\]/, "<math>\\1</math>")
    text.add_next_sibling mapped_text
    text.remove
  end

  # unwrap span.render_latext
  out.css('span.render_latex').each do |span|
    span.add_next_sibling span.children
    span.remove
  end

  # clean up preformatted code
  out.css('pre.prettyprint').each do |pre|
    pre.attributes['class'].remove
  end

  # clean up youtube embeds
  out.css('div.qtext_embed').each do |div|
    embed              = Nokogiri::XML::Node.new('embed', html)
    embed['type']      = div['data-video-provider']
    embed['src']       = div['data-yt-id']
    embed['thumbnail'] = div['style'].match(/background(?:-image)?: url\('(.+?)'\)/)[1]
    div.add_next_sibling embed
    div.remove
  end

  # remove class names from HRs
  out.css('hr.qtext_hr').each do |hr|
    hr.attributes['class'].remove
  end

  # remove GIF wrappers
  out.css('div.gif_noclick_wrapper').each do |div|
    img = Nokogiri::XML::Node.new('img', html)
    if div['gif-embedded'].present?
      img['src'] = div['gif-embedded'].sub(/\?convert_to_webp=true$/, '')
    elsif div.css('div.gif_embed_noclick').first
      img['src'] = div.css('div.gif_embed_noclick').first['master_src'].sub(/\?convert_to_webp=true$/, '')
    else
      img['src'] = div.css('img').first['src'].sub(/\?convert_to_webp=true$/, '')
    end
    div.add_next_sibling img
    div.remove
  end

  # remove empty tags
  out.css('p, b, i, pre, blockquote').each do |div|
    div.remove if div.children.all? { |node| (node.text? && node.content.blank?) || (node.element? && node.name == 'br') }
  end

  return out.children
end

def parse_file(file, q_file)
  html = Nokogiri::HTML(File.read(file))
  q_html = Nokogiri::HTML(File.read(q_file)) if File.exist?(q_file)

  return nil unless html.css('span.question_text span.rendered_qtext').first # for some reason one of my answers became a review??

  title       = translate_qtext(html.css('h1 span.QuestionText span.rendered_qtext').first) or return nil # question redirect
  description = translate_qtext(html.css('div.question_details span.rendered_qtext').first).presence
  answer      = translate_qtext(html.css('div.ExpandedAnswer span.rendered_qtext').first).presence
  upvotes     = if (node = html.css('a.VoterListModalLink.AnswerVoterListModalLink').first)
                  node.text.match(/^(\d+)/)[1].to_i
                else
                  0
                end
  date_str    = html.css('div.AnswerHeader a.answer_permalink').first.text.sub(/^(Written|Updated) /, '').sub(/ ago$/, '')
  date        = if date_str =~ /(\d+)w/
                  $1.to_i.weeks.ago.to_date
                elsif date_str =~ /(\d+)d/
                  $1.to_i.days.ago.to_date
                elsif date_str =~ /(\d+)h/
                  $1.to_i.hours.ago.to_date
                end
  permalink   = html.css('a.answer_permalink').first['href']

  topics = q_html ? q_html.css('div.TopicList span.TopicName').map(&:text) : []

  return Answer.new(title, description, answer, upvotes, date, topics, permalink)
end

answers = Dir.glob('build/answers/*.html').map do |file|
  next if File.basename(file).start_with?('q-')
  parse_file file, file.sub(/(\d+)\.html$/, "q-\\1.html")
end.compact
File.open('build/answers.json', 'w') { |f| f.puts JSON.pretty_generate(answers) }
