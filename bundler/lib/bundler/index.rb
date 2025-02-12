# frozen_string_literal: true

module Bundler
  class Index
    include Enumerable

    def self.build
      i = new
      yield i
      i
    end

    attr_reader :specs, :duplicates, :sources
    protected :specs, :duplicates

    RUBY = "ruby"
    NULL = "\0"

    def initialize
      @sources = []
      @cache = {}
      @specs = Hash.new {|h, k| h[k] = {} }
      @duplicates = {}
    end

    def initialize_copy(o)
      @sources = o.sources.dup
      @cache = {}
      @specs = Hash.new {|h, k| h[k] = {} }
      @duplicates = {}

      o.specs.each do |name, hash|
        @specs[name] = hash.dup
      end
      o.duplicates.each do |name, array|
        @duplicates[name] = array.dup
      end
    end

    def inspect
      "#<#{self.class}:0x#{object_id} sources=#{sources.map(&:inspect)} specs.size=#{specs.size}>"
    end

    def empty?
      each { return false }
      true
    end

    def search_all(name)
      all_matches = specs_by_name(name) # always returns a new Array
      dupes = @duplicates[name]
      all_matches.concat(dupes) if dupes
      @sources.each do |source|
        all_matches.concat(source.search_all(name))
      end
      all_matches
    end

    # Search this index's specs, and any source indexes that this index knows
    # about, returning all of the results.
    def search(query)
      results = local_search(query)
      return results unless @sources.any?

      @sources.each do |source|
        results.concat(source.search(query))
      end
      results.uniq(&:full_name)
    end

    def local_search(query)
      case query
      when Gem::Specification, RemoteSpecification, LazySpecification, EndpointSpecification then search_by_spec(query)
      when String then specs_by_name(query)
      when Array then specs_by_name_and_version(*query)
      else
        raise "You can't search for a #{query.inspect}."
      end
    end

    alias_method :[], :search

    def add(spec)
      @specs[spec.name][spec.full_name] = spec
      spec
    end
    alias_method :<<, :add

    def each(&blk)
      return enum_for(:each) unless blk
      specs.values.each do |spec_sets|
        spec_sets.values.each(&blk)
      end
      sources.each {|s| s.each(&blk) }
      self
    end

    def spec_names
      names = specs.keys + sources.map(&:spec_names)
      names.uniq!
      names
    end

    def unmet_dependency_names
      dependency_names.select do |name|
        search(name).empty?
      end
    end

    def dependency_names
      names = []
      each do |spec|
        spec.dependencies.each do |dep|
          next if dep.type == :development
          names << dep.name
        end
      end
      names.uniq
    end

    # Combines indexes proritizing existing specs, like `Hash#reverse_merge!`
    # Duplicate specs found in `other` are stored in `@duplicates`.
    def use(other)
      return unless other
      other.each do |spec|
        exist?(spec) ? add_duplicate(spec) : add(spec)
      end
      self
    end

    # Combines indexes proritizing specs from `other`, like `Hash#merge!`
    # Duplicate specs found in `self` are saved in `@duplicates`.
    def merge!(other)
      return unless other
      other.each do |spec|
        if existing = find_by_spec(spec)
          add_duplicate(existing)
        end
        add spec
      end
      self
    end

    def size
      @sources.inject(@specs.size) do |size, source|
        size += source.size
      end
    end

    # Whether all the specs in self are in other
    # TODO: rename to #include?
    def ==(other)
      all? do |spec|
        other_spec = other[spec].first
        other_spec && dependencies_eql?(spec, other_spec) && spec.source == other_spec.source
      end
    end

    def dependencies_eql?(spec, other_spec)
      deps       = spec.dependencies.select {|d| d.type != :development }
      other_deps = other_spec.dependencies.select {|d| d.type != :development }
      deps.sort == other_deps.sort
    end

    def add_source(index)
      raise ArgumentError, "Source must be an index, not #{index.class}" unless index.is_a?(Index)
      @sources << index
      @sources.uniq! # need to use uniq! here instead of checking for the item before adding
    end

    private

    def add_duplicate(spec)
      (@duplicates[spec.name] ||= []) << spec
    end

    def specs_by_name_and_version(name, version)
      specs_by_name(name).select {|spec| spec.version == version }
    end

    def specs_by_name(name)
      @specs[name].values
    end

    EMPTY_SEARCH = [].freeze

    def search_by_spec(spec)
      spec = find_by_spec(spec)
      spec ? [spec] : EMPTY_SEARCH
    end

    def find_by_spec(spec)
      @specs[spec.name][spec.full_name]
    end

    def exist?(spec)
      @specs[spec.name].key?(spec.full_name)
    end
  end
end
