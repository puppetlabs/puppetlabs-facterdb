# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::Scrubber
  def initialize(policy)
    @rules = policy.map { |path, value| [path.split('.'), value] }
  end

  def scrub(data)
    copy = Marshal.load(Marshal.dump(data))
    @rules.each do |segments, value|
      each_match(copy, segments, []) { |node, key, _path| node[key] = value }
    end
    copy
  end

  # Concrete paths whose value differs from the placeholder (never the values).
  def leaks(data)
    found = []
    @rules.each do |segments, value|
      each_match(data, segments, []) { |node, key, path| found << path.join('.') unless node[key] == value }
    end
    found.uniq
  end

  private

  def each_match(node, segments, trail, &block)
    return node.each { |item| each_match(item, segments, trail, &block) } if node.is_a?(Array)
    return unless node.is_a?(Hash)

    seg, *rest = segments
    matching_keys(node, seg).each do |key|
      if rest.empty?
        yield node, key, trail + [key]
      else
        each_match(node[key], rest, trail + [key], &block)
      end
    end
  end

  def matching_keys(node, seg)
    return node.keys if seg == '*'

    node.key?(seg) ? [seg] : []
  end
end
