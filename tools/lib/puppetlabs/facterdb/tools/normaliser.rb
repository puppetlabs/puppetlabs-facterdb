# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::Normaliser
  def self.sort_keys(obj)
    case obj
    when Hash then obj.keys.sort.to_h { |k| [k, sort_keys(obj[k])] }
    when Array then obj.map { |v| sort_keys(v) }
    else obj
    end
  end

  def self.format(obj)
    "#{JSON.pretty_generate(sort_keys(obj))}\n"
  end

  def initialize(scrubber)
    @scrubber = scrubber
  end

  def render(data)
    self.class.format(@scrubber.scrub(data))
  end
end
