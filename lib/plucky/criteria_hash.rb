module Plucky
  class CriteriaHash
    attr_reader :source

    def initialize(hash={}, options={})
      @source, @options = {}, options
      hash.each { |key, value| self[key] = value }
    end

    def []=(key, value)
      normalized_key = normalized_key(key)
      if key.is_a?(SymbolOperator)
        operator = "$#{key.operator}"
        normalized_value = normalized_value(normalized_key, operator, value)
        source[normalized_key] ||= {}
        source[normalized_key][operator] = normalized_value
      else
        if key == :conditions
          value.each { |k, v| self[k] = v }
        else
          normalized_value = normalized_value(normalized_key, normalized_key, value)
          source[normalized_key] = normalized_value
        end
      end
    end

    def ==(other)
      source == other.source
    end

    def to_hash
      source
    end

    def merge(other)
      target = source.dup
      other.source.each_key do |key|
        value, other_value = target[key], other[key]
        target[key] =
          if target.key?(key)
            value_is_hash = value.is_a?(Hash)
            other_is_hash = other_value.is_a?(Hash)

            if value_is_hash && other_is_hash
              value.update(other_value) do |key, old_value, new_value|
                Array(old_value).concat(Array(new_value)).uniq
              end
            elsif value_is_hash && !other_is_hash
              if modifier_key = value.keys.detect { |k| k.to_s[0, 1] == '$' }
                value[modifier_key].concat(Array(other_value)).uniq!
              else
                # kaboom! Array(value).concat(Array(other_value)).uniq
              end
            elsif other_is_hash && !value_is_hash
              if modifier_key = other_value.keys.detect { |k| k.to_s[0, 1] == '$' }
                other_value[modifier_key].concat(Array(value)).uniq!
              else
                # kaboom! Array(value).concat(Array(other_value)).uniq
              end
            else
              Array(value).concat(Array(other_value)).uniq
            end
          else
            other_value
          end
      end
      self.class.new(target)
    end

    def object_ids
      @options[:object_ids]
    end

    def object_ids=(value)
      @options[:object_ids] = value
    end

    private
      def method_missing(method, *args, &block)
        @source.send(method, *args, &block)
      end

      def object_id?(key)
        return false if object_ids.nil?
        object_ids.include?(key.to_sym)
      end

      def normalized_key(key)
        key = key.to_sym                 if key.respond_to?(:to_sym)
        return normalized_key(key.field) if key.respond_to?(:field)
        return :_id                      if key == :id
        key
      end

      def normalized_value(parent_key, key, value)
        case value
          when Array, Set
            value.map! { |v| Plucky.to_object_id(v) } if object_id?(parent_key)
            parent_key == key ? {'$in' => value.to_a} : value.to_a
          when Time
            value.utc
          when String
            return Plucky.to_object_id(value) if object_id?(key)
            value
          when Hash
            value.each { |k, v| value[k] = normalized_value(key, k, v) }
            value
          else
            value
        end
      end
  end
end