require 'bundler'
Bundler.require
require 'yaml'
require './common'

config = YAML.load_file('config/config.yml')

browser = Watir::Browser.new(:chrome, switches: %w[--disable-popup-blocking --disable-translate])

puts "Logging in..."
browser.goto 'https://www.quora.com'
Watir::Wait.until { browser.form(class: 'inline_login_form').text_field(name: 'email').enabled? }
browser.form(class: 'inline_login_form').text_field(name: 'email').set config['quora_email']
Watir::Wait.until { browser.form(class: 'inline_login_form').text_field(name: 'password').enabled? }
browser.form(class: 'inline_login_form').text_field(name: 'password').set config['quora_password']
Watir::Wait.until { browser.form(class: 'inline_login_form').button(type: 'submit').enabled? }
browser.form(class: 'inline_login_form').submit

puts "Going to answers..."
browser.a(text: 'Your Content').when_present.click
browser.a(text: 'Answers').when_present.click

puts "Loading answers..."
count      = browser.elements(css: 'a.question_link').count
last_count = count
begin
  count == last_count
  puts "-- Loading page (found #{count} so far)"
  browser.scroll.to :bottom
  sleep 2
  last_count = count
  count      += browser.elements(css: 'a.question_link').count
end until count == last_count

urls = browser.links(css: 'a.question_link').map(&:href)
File.open('build/answer_urls.txt', 'w') { |f| f.puts urls.join("\n") }

browser.close
