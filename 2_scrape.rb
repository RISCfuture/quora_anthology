require 'bundler'
Bundler.require
require './common'
require 'fileutils'

puts "Preparing..."

urls = File.read('build/answer_urls.txt').split("\n").map { |path| "https://www.quora.com#{path}" }
FileUtils.mkdir_p 'build/answers'

hydra = Typhoeus::Hydra.hydra
urls.each.with_index do |url, i|
  request = Typhoeus::Request.new(url, method: :get, headers: COMMON_HEADERS)

  request.on_complete do |response|
    if response.success?
      File.open("build/answers/#{i}.html", 'w') { |f| f.puts response.body }
    elsif response.timed_out?
      puts "Retry #{url}"
      hydra.queue response.request
    elsif response.code == 0
      puts "#{url}\t#{response.return_message}"
    else
      puts "#{url}\t#{response.code}"
    end
  end

  hydra.queue request
  
  ## and root question
  
  url.sub! /\/answer\/.+$/, ''
  request = Typhoeus::Request.new(url, method: :get, headers: COMMON_HEADERS)

  request.on_complete do |response|
    if response.success?
      File.open("build/answers/q-#{i}.html", 'w') { |f| f.puts response.body }
    elsif response.timed_out?
      puts "Retry #{url}"
      hydra.queue response.request
    elsif response.code == 0
      puts "#{url}\t#{response.return_message}"
    else
      puts "#{url}\t#{response.code}"
    end
  end

  hydra.queue request
end

puts "Downloading..."
hydra.run

puts "Done"
