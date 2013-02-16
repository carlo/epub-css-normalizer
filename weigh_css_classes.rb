#!/usr/bin/env ruby

require "nokogiri"
require "trollop"

opts = Trollop::options do
  opt :folder, "lolder containing unpacked EPUB", :type => :string
  opt :verbose, "list number of occurrences with class name", :type => :boolean
end

Trollop::die "--folder is mandatory" unless opts[:folder]

# Set up tally list
css_classes_occurence = {}
css_classes_weighed = {}

# Iterate over all HTML files in the folder
Dir.glob("#{ opts[:folder] }/**/*.html").each do |path|
  file = File.open("Blue Mars/Blue_Mars_split_000.html", "r") rescue nil
  next unless file

  doc = Nokogiri::HTML(file)
  file.close

  doc.css('body *').each do |node|
    css_class = node.attr(:class)
    next if css_class.empty?
    css_class = css_class.to_sym
    css_classes_occurence[css_class] = css_classes_occurence[css_class] || 0
    css_classes_occurence[css_class] += 1
  end
end

css_classes_weighed = Hash[ css_classes_occurence.sort_by {|css_class, count| count }.reverse ]

css_classes_weighed.each do |css_class, count|
  if opts[:verbose]
    puts "#{css_class}:#{count}"
  else
    puts css_class
  end
end
