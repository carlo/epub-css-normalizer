#!/usr/bin/env ruby

require "rubygems"
require "bundler/setup"
require "nokogiri"
require "pp"
require "trollop"
require "sass"
require "./sass_css3_extension"

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
Dir.glob("#{folder}/**/*.{htm,html,xhtml,xml}").each do |path|
  next if path.match("META-INF")
  file = File.open(path, "r") rescue nil
  next unless file

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

# Parse CSS.
css_rules = {}
Sass::Engine.new(css_original, :syntax => :scss).to_tree.to_a.each do |prop|
  next unless prop[:selector]

  split_selectors = prop[:selector].split(/\s*,\s*/)
  split_selectors.each do |ss|
    css_rules[ss] ||= {}
    css_rules[ss][ prop[:property] ] = prop[:value]
  end
end

# Assemble final list of properties.
final_properties = {}
selectors_to_check_for = [ "html", "body" ] + opts[:selector].split(/\s+/)
selectors_to_check_for.uniq!

# Find applicable rules for passed selector.
selectors_to_check_for.each do |passed_selector|
  matched_rules = css_rules.find do |selector, props|
    pattern = selector.start_with?(".") \
      ? "^\\b*[a-z]+\\#{selector}$" \
      : "^\\b*#{selector}$"
    selector == passed_selector || passed_selector.match(pattern)
  end
  next unless matched_rules

  rules = Hash[*matched_rules]
  rules.each do |selector, props|
    final_properties.merge!(props)
  end
end

# Return the font size used for the most common selector
puts final_properties["font-size"] || "1em (default)"

if opts[:verbose]
  puts
  pp final_properties
end
