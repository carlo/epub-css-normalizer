#!/usr/bin/env ruby
# coding: UTF-8

require "rubygems"
require "bundler/setup"
require "nokogiri"
require "pp"
require "trollop"
require "sass"
require "./sass_css3_extension"
require "tmpdir"
require "shellwords"


def unzip_file(epub_filename, output_folder)
  cmd = "unzip #{Shellwords.escape(epub_filename)} -d #{Shellwords.escape(output_folder)}"
  puts cmd
  system(cmd)
end


def zip_folder(input_folder, filename)
  filename_esc = Shellwords.escape(filename)
  folder_esc = Shellwords.escape(input_folder)

  cmd = [
    "cd #{folder_esc}",
    File.exist?("mimetype") ? "zip -X0 -b #{folder_esc} #{filename_esc} mimetype" : nil,
    "zip -rDX9 #{filename_esc} * -x *.DS_Store -x mimetype"
  ].compact.join(" && ")
  puts cmd
  system(cmd);
end


def get_options_or_die
  opts = Trollop::options do
    opt :epub, "filename EPUB", :type => :string
  end

  Trollop::die "--epub is mandatory" unless opts[:epub]
  opts[:epub] = File.expand_path(opts[:epub])
  opts
end


def compute_most_common_selectors(folder)
  # Set up tally lists
  css_classes_occurence = {}
  css_classes_weighed = {}

  # Iterate over all (X)HTML files in the folder
  Dir.glob("#{folder}/**/*.{htm,html,xhtml,xml}").each do |path|
    next if path.match("META-INF")
    file = File.open(path, "r") rescue nil
    next unless file

    doc = Nokogiri::HTML(file)
    file.close

    # Count all tag names & classes.
    doc.css("body *").each do |node|
      next unless node.description
      descriptor = node.description.name
      descriptor += "." + node.attr(:class) if node.attr(:class)

      current_node = node
      selector_tree = [ descriptor ]

      while parent_node = current_node.parent
        break if parent_node == doc.root

        descriptor = parent_node.description.name
        descriptor += "." + parent_node.attr(:class) if parent_node.attr(:class)
        selector_tree << descriptor

        current_node = parent_node
      end

      css_class = selector_tree.compact.reverse.join(" ")

      css_classes_occurence[css_class] = css_classes_occurence[css_class] || 0
      css_classes_occurence[css_class] += 1
    end
  end

  css_classes_weighed = Hash[ css_classes_occurence.sort_by {|css_class, count| count }.reverse ]
  css_classes_weighed.first.first
end


def get_base_font_size(folder, selector)
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
        next if !href || href.empty? || href.match("normalized_font_sizes")

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
  selectors_to_check_for = [ "html", "body" ] + selector.split(/\s+/)
  selectors_to_check_for.uniq!

  # Find applicable rules for passed selector.
  selectors_to_check_for.each do |passed_selector|
    matched_rules = css_rules.find do |sel, props|
      pattern = sel.start_with?(".") \
        ? "^\\b*[a-z]+\\#{sel}$" \
        : "^\\b*#{sel}$"
      sel == passed_selector || passed_selector.match(pattern)
    end
    next unless matched_rules

    rules = Hash[*matched_rules]
    rules.each do |sel, props|
      final_properties.merge!(props)
    end
  end

  # Return the font size used for the most common selector
  final_properties["font-size"] || "1em (default)"
end


def normalize_css(folder, base_size)
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
        next if !href || href.empty? || href.match("normalized_font_sizes")

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
  sizes_are_numeric = !!base_size.match(/^[\d\.]/)
  base_size = sizes_are_numeric ? base_size.to_f : base_size

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
  factor = 1 / base_size

  # Parse & normalize CSS.
  css_rules = {}
  css_properties.each do |prop|
    next unless prop[:selector]

    sel = prop[:selector]
    property = prop[:property]
    value = prop[:value]

    if property == "font-size"
      unit = "em"

      if sizes_are_numeric
        if value.match("%")
          old_size = value.to_f
          new_size = ( old_size * factor / 100 ).round(2)
        elsif value.match(/px/)
          old_size = value.to_f
          new_size = ( old_size * factor / 16 ).round(2)
        elsif value.match(/small/)
          new_size = "75"
          unit = "%"
        elsif value.match(/large/)
          new_size = "125"
          unit = "%"
        else
          old_size = value.to_f
          new_size = ( old_size * factor ).round(2)
        end

        puts "#{value} * #{factor.round(3)} ➔ #{new_size}#{unit}"
      else
        relative_index = font_sizes_used.index(value).to_i - index_of_old_base_size
        new_size = TRADITIONAL_FONT_SIZES[ index_of_new_base_size + relative_index ]
      end

      css_rules[sel] ||= {}
      css_rules[sel]["-cz-old-font-size"] = value
      css_rules[sel]["font-size"] = "#{new_size}#{unit}"
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
    next unless doc.css("link[href='normalized_font_sizes.css']").empty?

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
    next unless doc.css("item[href='normalized_font_sizes.css']").empty?

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
end


# Create tmp folder.
tmp_dir = Dir.mktmpdir

begin
  opts = get_options_or_die()
  unzip_file(opts[:epub], tmp_dir)
  most_common_selector = compute_most_common_selectors(tmp_dir)
  base_font_size = get_base_font_size(tmp_dir, most_common_selector)
  zip_folder(tmp_dir, opts[:epub].gsub(/\.epub$/, ".normalized.epub"))
ensure
  # remove the tmp directory.
  FileUtils.remove_entry_secure(tmp_dir)
end
