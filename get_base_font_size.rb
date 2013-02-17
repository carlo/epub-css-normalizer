#!/usr/bin/env ruby

require "csspool"
require "nokogiri"
require "pp"
require "trollop"

opts = Trollop::options do
  banner <<-EOTEXT
Return the font size for the passed CSS selector of an unpacked EPUB.
EOTEXT
  opt :folder, "folder containing unpacked EPUB", :type => :string
  opt :selector, "selector, e.g. '.calibre div.calibre4'", :type => :string
  opt :verbose, "print computed CSS properties for selector", :type => :boolean
end

Trollop::die "--folder is mandatory" unless opts[:folder]
Trollop::die "--selector is mandatory" unless opts[:selector]

folder = File.expand_path(opts[:folder])
stylesheets = []
css_original = ""

# Iterate over all HTML files in the folder
Dir.glob("#{folder}/**/*.html").each do |path|
  file = File.open(path, "r") rescue nil
  next unless file

  doc = Nokogiri::HTML(file)
  file.close

  # Iterate over all applicable <link> tags and get their stylesheet
  # references
  doc.css("link[href$='css']").each do |node|
    href = node.attr(:href)
    next if !href || href.empty?

    href.strip!
    href.prepend("../") unless href.start_with?("./")
    full_path = File.expand_path("#{path}/#{href}")

    stylesheets << full_path unless stylesheets.index(full_path)
  end
end

# Concatenate all CSS files.
stylesheets.each do |path|
  css_original << File.read(path)
  css_original << "\n"
end

# Strip `@page` directive, CSSPool doesn't like it.
css_original.gsub!(/@[a-z]+\s*[^\}]+\}/, "")
doc = CSSPool::CSS(css_original)

final_properties = {}
opts[:selector].split(/\s+/).each do |passed_selector|
  begin
    rule = doc.rule_sets.select do |set|
      set.selectors.any? do |sel|
        sel_s = sel.to_s
        pattern = sel_s.start_with?(".") ? "^\\b*[a-z]+\\#{sel_s}$" : "^\\b*[a-z]+#{sel_s}$"
        sel_s == passed_selector || passed_selector.match(pattern)
      end
    end.first
  rescue
    rule = nil
  end

  next unless rule

  rule.declarations.each do |decl|
    final_properties[decl.property.downcase] = decl.expressions.join(" ")
  end
end

# Return the font size used for the most common selector
puts final_properties["font-size"]

if opts[:verbose]
  puts
  pp final_properties
end
