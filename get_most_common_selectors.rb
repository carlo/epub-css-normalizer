#!/usr/bin/env ruby

require "rubygems"
require "bundler/setup"
require "nokogiri"
require "trollop"

opts = Trollop::options do
  opt :folder, "folder containing unpacked EPUB", :type => :string
  opt :verbose, "list number of occurrences with class name", :type => :boolean
end

Trollop::die "--folder is mandatory" unless opts[:folder]

folder = File.expand_path(opts[:folder])

# Set up tally lists
css_classes_occurence = {}
css_classes_weighed = {}

# Iterate over all HTML files in the folder
Dir.glob("#{folder}/**/*.html").each do |path|
  file = File.open(path, "r") rescue nil
  next unless file

  doc = Nokogiri::HTML(file)
  file.close

  doc.css("body *").each do |node|
    css_class = node.attr(:class)
    next if !css_class || css_class.empty?

    current_node = node
    selector_tree = [ "#{node.description.name}.#{css_class}" ]

    while parent_node = current_node.parent
      break if parent_node == doc.root

      if parent_node.attr(:class)
        selector_tree << "#{parent_node.description.name}.#{ parent_node.attr(:class) }"
      end
      current_node = parent_node
    end

    css_class = selector_tree.compact.reverse.join(" ")

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
