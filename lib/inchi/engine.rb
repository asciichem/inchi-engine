# frozen_string_literal: true

module Inchi
  # The reference InChI engine: layer emission driven by the oracle
  # corpus (inchi-tests). Every layer this engine emits must agree
  # byte-for-byte with the recorded oracle strings before its
  # milestone claims the gate (TODO.v2/16).
  #
  # M1 — the formula layer (plus the ±1 proton standardization the
  # charged corpus cases carry).
  class Engine
    Atom = Struct.new(:element, :h_count, :charge, keyword_init: true)
    Bond = Struct.new(:from, :to, :order, keyword_init: true)
    Structure = Struct.new(:atoms, :bonds, keyword_init: true)

    class Error < StandardError; end

    class << self
      # Parses the V2000 subset the corpus identity molfiles use (the
      # gem writer's output): counts line, atom block, bond block,
      # `M  CHG` property lines.
      def parse_molfile(input)
        lines = input.lines.map(&:chomp)
        raise Error, "molfile too short" if lines.length < 5

        counts = lines[3]
        atom_count = counts[0, 3].to_i
        bond_count = counts[3, 3].to_i

        atoms = atom_count.times.map do |i|
          line = lines[4 + i] or raise Error, "truncated atom block"
          element = line[31, 3].to_s.strip
          raise Error, "atom #{i} has no element symbol" if element.empty?

          code = line[42, 3].to_s.strip.to_i
          Atom.new(element: element, h_count: code.positive? ? code - 1 : 0, charge: 0)
        end

        bonds = bond_count.times.map do |i|
          line = lines[4 + atom_count + i] or raise Error, "truncated bond block"
          from = line[0, 3].to_i - 1
          to = line[3, 3].to_i - 1
          order = BOND_ORDER.fetch(line[6, 3].to_i) { raise Error, "unsupported bond type" }
          Bond.new(from: from, to: to, order: order)
        end

        lines.each do |line|
          next unless line.start_with?("M  CHG")

          parts = line[6..].split
          parts[1..].each_slice(2) do |index, charge|
            atoms[index.to_i - 1].charge = charge.to_i
          end
        end

        Structure.new(atoms: atoms, bonds: bonds)
      end

      # The `/formula` layer plus the ±1 proton standardization: an
      # anion is recorded as its neutral parent with one MORE hydrogen
      # (`/p-1`), a cation with one LESS (`/p+1`).
      def formula_layer(structure)
        composition = composition_of(structure)
        charge = structure.atoms.sum(&:charge)
        proton =
          case charge
          when 0 then nil
          when -1
            composition["H"] = composition["H"].to_i + 1
            "-1"
          when 1
            raise Error, "cation without hydrogen to standardize" if composition["H"].to_i.zero?

            composition["H"] -= 1
            "+1"
          else
            raise Error, "|charge| = #{charge} beyond the ±1 corpus gate"
          end
        [hill_string(composition), proton]
      end

      private

      BOND_ORDER = { 1 => 1.0, 2 => 2.0, 3 => 3.0, 4 => 1.5 }.freeze
      VALENCE = { "C" => 4.0, "N" => 3.0, "O" => 2.0, "S" => 6.0, "P" => 5.0,
                  "F" => 1.0, "Cl" => 1.0, "Br" => 1.0, "I" => 1.0,
                  "H" => 1.0 }.freeze

      def composition_of(structure)
        sums = Hash.new(0.0)
        structure.bonds.each do |bond|
          sums[bond.from] += bond.order
          sums[bond.to] += bond.order
        end
        composition = Hash.new(0)
        structure.atoms.each_with_index do |atom, index|
          composition[atom.element] += 1
          hydrogens = if atom.h_count.positive?
                        atom.h_count
                      elsif atom.charge.negative?
                        # An anionic heteroatom carries no implicit H
                        # (O- of an acetate/carboxylate: the recorded
                        # formula standardizes via the /p layer).
                        0
                      else
                        (VALENCE.fetch(atom.element, 0.0) - sums[index]).clamp(0.0, Float::INFINITY).to_i
                      end
          composition["H"] += hydrogens if hydrogens.positive?
        end
        composition
      end

      # Hill order with the InChI twist: carbon first (when present),
      # then hydrogen, then the rest alphabetically; counts omitted
      # when 1. Without carbon: pure alphabetical.
      def hill_string(composition)
        composition.delete_if { |_, count| count.zero? }
        entries = composition.to_a
        entries.sort_by! { |(element, _)| element }
        if composition.key?("C")
          entries.sort_by! { |(element, _)| element == "C" ? 0 : element == "H" ? 1 : 2 }
        end
        entries.map do |(element, count)|
          count > 1 ? "#{element}#{count}" : element
        end.join
      end
    end
  end
end
