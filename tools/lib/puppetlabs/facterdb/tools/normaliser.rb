# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::Normaliser
  def self.sort_keys(obj)
    case obj
    when Hash then obj.keys.sort.to_h { |k| [k, sort_keys(obj[k])] }
    when Array then obj.map { |v| sort_keys(v) }
    else obj
    end
  end

  # json < 2.7 (Ruby 3.2) spreads empty arrays and hashes over several lines; collapse them so output is identical on every Ruby.
  def self.format(obj)
    "#{JSON.pretty_generate(sort_keys(obj)).gsub(%r{([\[{])\n\s*([\]}])}, '\1\2')}\n"
  end

  def initialize(scrubber)
    @scrubber = scrubber
  end

  def render(data)
    self.class.format(@scrubber.scrub(data))
  end
end
