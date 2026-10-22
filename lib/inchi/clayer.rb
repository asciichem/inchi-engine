# frozen_string_literal: true

module Inchi
  # The /c connection layer: parsing the oracle's segment into an
  # edge list over canonical ranks, and emitting the segment from
  # canonical ranks (M2).
  module Clayer
    Error = Class.new(StandardError)

    module_function

    # "1-6(10)13-8-5..." -> { ranks: [..all numbers seen..],
    # edges: [[a, b], ...] } over canonical ranks (1-based). Numbers
    # bond to the current atom; "-" is only a separator; "(" pushes
    # the branch point, ")" restores it; a number naming a seen atom
    # is a ring closure (the current atom stays).
    def parse(segment)
      tokens = segment.scan(/\d+|[()\-]/)
      edges = []
      current = nil
      stack = []
      seen = {}

      tokens.each do |token|
        case token
        when /\A\d+\z/
          rank = Integer(token, 10)
          if current.nil?
            raise Error, "the first atom of the segment" if stack.any?

            seen[rank] = true
            current = rank
            next
          end
          edges << [current, rank].sort
          unless seen[rank]
            seen[rank] = true
            current = rank
          end
        when "("
          stack << current
        when ")"
          raise Error, "unbalanced parentheses" if stack.empty?

          current = stack.pop
        when "-"
          # separator only — numbers bond to the current atom
        end
      end

      raise Error, "unbalanced parentheses" unless stack.empty?

      { ranks: seen.keys.sort, edges: edges.uniq }
    end
  end
end
