#!/usr/bin/env ruby
# coding: UTF-8

require "rubygems"
require "bundler/setup"
require "nokogiri"
require "pp"
require "trollop"
require "sass"
require "./sass_css3_extension"

TRADITIONAL_FONT_SIZES = [ 0.5, 0.5833, 0.666, 0.75, 0.8333, 0.9167, 1, 1.1667, 1.333, 1.5, 1.75, 2, 3, 4, 5, 6 ]
CSS_FONT_SIZES = %w( xx-small x-small small medium large x-large xx-large )

opts = Trollop::options do
  banner <<-EOTEXT
Return the font size for the passed CSS selector of an unpacked EPUB.
EOTEXT
  opt :folder, "folder containing unpacked EPUB", :type => :string
  opt :base_size, "base font size, the one that is supposed to be 1em", :type => :string
end

Trollop::die "--folder is mandatory" unless opts[:folder]
Trollop::die "--base_size is mandatory" unless opts[:base_size]

folder = File.expand_path(opts[:folder])
stylesheets = []
css_original = ""
documents = Dir.glob("#{folder}/**/*.{htm,html,xhtml,xml}").reject {|p| p.match("META-INF") }
document_subfolders = []

# Iterate over all HTML files in the folder
documents.each do |path|
  file = File.open(path, "r") rescue nil
  next unless file

  document_subfolders << File.dirname(path)
  doc = Nokogiri::HTML(file)
  file.close

  # Iterate over all applicable <link> tags and get their stylesheet
  # references.
  doc.css("link[href$='css'], style").each do |node|
    # Read inline <style> tags.
    if node.description.name == "style"
      stylesheets << node.text unless stylesheets.index(node.text)

    elsif node.description.name == "link"
      href = node.attr(:href)
      next if !href || href.empty?

      href.strip!
      href.prepend("../") unless href.start_with?("./")
      full_path = "ss!" + File.expand_path("#{path}/#{href}")

      stylesheets << full_path unless stylesheets.index(full_path)
    end
  end
end

# Discern the target folder for the CSS file to be written.
document_subfolders.uniq!
output_folder = document_subfolders[0]

# Exchange references with actual CSS.
stylesheets.map! do |string|
  if string.start_with?("ss!")
    File.read(string.gsub(/^ss!/, ""))
  else
    string
  end
end

# Concatenate all CSS files.
css_original = stylesheets.join("\n")

# Determine what rules we need to apply to the font sizes.
sizes_are_numeric = !!opts[:base_size].match(/^[\d\.]/)
base_size = sizes_are_numeric ? opts[:base_size].to_f : opts[:base_size]

# Parse CSS.
css_properties = Sass::Engine.new(css_original, :syntax => :scss).to_tree.to_a

# Gather list of used font sizes.
font_sizes_used = [base_size]

css_properties.each do |prop|
  next unless prop[:selector]
  next unless prop[:property] == "font-size"
  font_sizes_used << ( sizes_are_numeric ? prop[:value].to_f : prop[:value] )
end

# Normalize list of font sizes used.
if sizes_are_numeric
  font_sizes_used.sort!
else
  font_sizes_used = CSS_FONT_SIZES & font_sizes_used
end

font_sizes_used.uniq!
index_of_old_base_size = font_sizes_used.index(base_size)
index_of_new_base_size = TRADITIONAL_FONT_SIZES.index(1)

# Parse & normalize CSS.
css_rules = {}
css_properties.each do |prop|
  next unless prop[:selector]

  sel = prop[:selector]
  property = prop[:property]
  value = prop[:value]

  if property == "font-size"
    old_size = sizes_are_numeric ? value.to_f : value
    relative_index = font_sizes_used.index(old_size).to_i - index_of_old_base_size
    new_size = TRADITIONAL_FONT_SIZES[ index_of_new_base_size + relative_index ]

    css_rules[sel] ||= {}
    css_rules[sel]["-cz-old-font-size"] = value
    css_rules[sel]["font-size"] = "#{new_size}em"
  elsif property == "line-height"
    css_rules[sel] ||= {}
    css_rules[sel]["line-height"] = "auto"
  end
end

# Write CSS file.
output_filename = "#{output_folder}/normalized_font_sizes.css"
File.open( output_filename, "w" ) do |f|
  css_rules.each do |selector, props|
    line = "#{selector} { "
    line += props.map {|prop, value| "#{prop}: #{value};" }.join(" ")
    line += " }"
    f.puts line
  end
  f.close
end

puts "Created #{output_filename}."

# Add CSS reference to all pages.
documents.each do |path|
  file = File.open(path, "r") rescue nil
  next unless file
  doc = Nokogiri::XML(file)
  file.close

  link_node = Nokogiri::XML::Node.new "link", doc
  link_node["rel"] = "stylesheet"
  link_node["href"] = "normalized_font_sizes.css"
  link_node["type"] = "text/css"
  doc.at_css("head").add_child(link_node)

  short_path = path.gsub(folder, "")
  print "Writing #{short_path}… "
  File.open(path, "w") do |f|
    f.puts doc.to_s
    f.close
  end
  puts " done."
end

# Update OPF manifest.
Dir.glob("#{folder}/**/*.opf") do |path|
  file = File.open(path, "r") rescue nil
  next unless file

  doc = Nokogiri::XML(file)
  file.close

  item_node = Nokogiri::XML::Node.new "item", doc
  item_node["id"] = "css-normalized"
  item_node["href"] = "normalized_font_sizes.css"
  item_node["media-type"] = "text/css"
  doc.at_css("manifest").add_child(item_node)

  short_path = path.gsub(folder, "")
  print "Writing updated manifest to #{short_path}… "
  File.open(path, "w") do |f|
    f.puts doc.to_s
    f.close
  end
  puts " done."
end

