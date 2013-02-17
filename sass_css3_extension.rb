# From https://coderwall.com/p/fbawrq

require 'sass'

class Sass::Tree::Visitors::ToArray < Sass::Tree::Visitors::Base
  protected

  def initialize
    @array = []
  end

  def visit(node, parent = false)
    if node_name(parent) == "root"
      @media = "all"
    end

    method = "visit_#{node_name(node)}"

    if self.respond_to?(method, true)
      self.send(method, node)
    else
      visit_children(node)
    end

    @array
  end

  def visit_children(parent)
    parent.children.map {|c| visit(c, parent)}
  end

  def visit_root(node)
    visit_children(node)
  end

  def visit_media(node)
    @media = node.query.join('')
    visit_children(node)
  end

  def visit_rule(node)
    @selector = node.rule[0]
    visit_children(node)
  end

  def visit_prop(node)
    return unless node.value

    @array << {
      media: @media,
      selector: @selector,
      property: node.name[0],
      value: node.value.to_sass
    }
  end
end

class Sass::Tree::Node
  def to_a
    Sass::Tree::Visitors::ToArray.visit(self)
  end
end
