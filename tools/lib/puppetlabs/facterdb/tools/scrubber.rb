# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::Scrubber
  # A rule is a Hash holding `value` plus `match` and/or `since`; any other value is a whole-value placeholder.
  def self.rule?(rule)
    rule.is_a?(Hash) && rule.key?('value') && (rule.key?('match') || rule.key?('since'))
  end

  def self.transform_for(rule)
    return ->(_old) { rule } unless rule?(rule)
    return ->(_old) { rule['value'] } unless rule.key?('match')

    pattern = Regexp.new(rule['match'])
    value = rule['value']
    ->(old) { old.is_a?(String) ? old.gsub(pattern) { value } : old }
  end

  def self.version_of(data)
    version = data['facterversion']
    version.is_a?(String) ? Gem::Version.new(version) : nil
  rescue ArgumentError
    nil
  end

  def initialize(policy)
    @rules = policy.map do |path, rule|
      since = (self.class.rule?(rule) && rule['since']) ? Gem::Version.new(rule['since'].to_s) : nil
      [path.split('.'), self.class.transform_for(rule), since]
    end
  end

  def scrub(data)
    copy = Marshal.load(Marshal.dump(data))
    active_rules(data).each do |segments, transform|
      each_match(copy, segments, []) { |node, key, _path| node[key] = transform.call(node[key]) }
    end
    copy
  end

  # Concrete paths whose value differs from the policy result (never the values).
  def leaks(data)
    found = []
    active_rules(data).each do |segments, transform|
      each_match(data, segments, []) { |node, key, path| found << path.join('.') unless transform.call(node[key]) == node[key] }
    end
    found.uniq
  end

  private

  # Rules with `since` apply only to files whose facterversion is known and at least that version.
  def active_rules(data)
    version = data.is_a?(Hash) ? self.class.version_of(data) : nil
    @rules.select { |_segments, _transform, since| since.nil? || (!version.nil? && version >= since) }
  end

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

  # `*` matches every key; `*!a,b` matches every key except `a` and `b`.
  def matching_keys(node, seg)
    return node.keys if seg == '*'
    return node.keys - seg.delete_prefix('*!').split(',') if seg.start_with?('*!')

    node.key?(seg) ? [seg] : []
  end
end
