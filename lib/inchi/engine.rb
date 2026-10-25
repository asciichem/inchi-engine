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
    Atom = Struct.new(:element, :h_count, :charge, :h_pinned, keyword_init: true)
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

        structure = Structure.new(atoms: atoms, bonds: bonds)
        normalize_internal_salts!(structure)
        structure
      end

      # The `/formula` layer plus the ±1 proton standardization: an
      # anion is recorded as its neutral parent with one MORE hydrogen
      # (`/p-1`), a cation with one LESS (`/p+1`).
      # The oracle's M1-visible standardization, decoded empirically:
      #   - anions: the charge's hydrogens come back as mobile H
      #     (`/p-n`) when the charge sits on O/N (acetate -> acetic
      #     acid's C2H4O2/p-1); a carbanion keeps its composition.
      #   - cations: only VALENCE-EXCESS hydrogens leave (ammonium's
      #     4th H -> H3N/p+1); a methylpyridinium keeps its full
      #     composition with `/p+1`.
      def formula_layer(structure)
        composition = composition_of(structure)
        charge = structure.atoms.sum(&:charge)
        proton =
          case charge
          when 0 then nil
          when 1
            if cation_carries_hydrogen?(structure)
              # A proton-carrying cation: one H is the proton the /p
              # layer accounts for (ammonium -> H3N/p+1; a protonated
              # amine loses one H).
              composition["H"] = composition["H"].to_i - 1
              "+1"
            else
              # A bond-charged cation (quaternary N): the composition
              # is the identity — no proton moved, no /p layer.
              nil
            end
          when -1
            # An anion standardizes to its protonated parent when the
            # charge sits on O/N (acetate -> C2H4O2/p-1); a carbanion
            # keeps its composition.
            hetero_anion = structure.atoms.any? { |a| a.charge.negative? && %w[O N].include?(a.element) }
            if hetero_anion
              composition["H"] = composition["H"].to_i + 1
              "-1"
            else
              # A carbanion (or charge on S/P): the composition is the
              # identity — no proton accounting, no /p layer.
              nil
            end
          else
            raise Error, "|charge| = #{charge} beyond the ±1 corpus gate"
          end
        [hill_string(composition), proton]
      end

      # The reference's internal-salt annihilation: an anionic
      # O/S/Se/Te cancels with a FIXED cation anywhere in its
      # connected component (nitro, N-oxide, betaine, diazo). The
      # neutralized anion keeps its anionic reading — zero implicit H
      # (h_pinned) — the reference never re-derives H after moving a
      # charge. A proton-carrying cation never annihilates.
      def normalize_internal_salts!(structure)
        neighbors = Hash.new { |h, k| h[k] = [] }
        structure.bonds.each do |bond|
          neighbors[bond.from] << bond.to
          neighbors[bond.to] << bond.from
        end
        sums = Hash.new(0.0)
        structure.bonds.each do |bond|
          sums[bond.from] += bond.order
          sums[bond.to] += bond.order
        end
        consumed = []
        anions = structure.atoms.each_index.select do |index|
          atom = structure.atoms[index]
          atom.charge.negative? && %w[O S Se Te N].include?(atom.element)
        end
        anions.each do |anion|
          next if consumed[anion]

          visited = { anion => true }
          queue = [anion]
          site = nil
          until queue.empty?
            current = queue.pop
            cation_atom = structure.atoms[current]
            no_carbon = neighbors[current].none? do |n|
              structure.atoms[n].element == "C"
            end
            is_fixed_cation = cation_atom.charge.positive? && !consumed[current] &&
                              !no_carbon && !cation_carries_hydrogen_atom?(
                                cation_atom, sums[current]
                              )
            if is_fixed_cation
              site = current
              break
            end
            (neighbors[current] - visited.keys).each do |next_atom|
              visited[next_atom] = true
              queue << next_atom
            end
          end
          next unless site

          structure.atoms[anion].charge = 0
          structure.atoms[anion].h_pinned = true
          structure.atoms[site].charge = 0
          consumed[anion] = consumed[site] = true
        end
      end

      # The proton-related-cation test for one atom: an explicit H or
      # a valence-deficient N/P center (the onium table).
      def cation_carries_hydrogen_atom?(atom, bond_sum)
        return true if atom.h_count.positive?

        %w[N P].include?(atom.element) && bond_sum <= 3.0
      end

      private

      BOND_ORDER = { 1 => 1.0, 2 => 2.0, 3 => 3.0, 4 => 1.5 }.freeze
      VALENCE = { "C" => 4.0, "N" => 3.0, "O" => 2.0, "S" => 6.0, "P" => 5.0,
                  "F" => 1.0, "Cl" => 1.0, "Br" => 1.0, "I" => 1.0,
                  "H" => 1.0 }.freeze

      # Does any cationic atom carry hydrogen? Proton-carrying
      # cations (ammonium, [NH+], protonated amines — explicit code
      # or valence-gap H) standardize by losing one proton; H-less
      # bond-charged cations (quaternary N) keep their composition
      # with no /p layer.
      def cation_carries_hydrogen?(structure)
        sums = Hash.new(0.0)
        structure.bonds.each do |bond|
          sums[bond.from] += bond.order
          sums[bond.to] += bond.order
        end
        structure.atoms.each_with_index.any? do |atom, index|
          next false unless atom.charge.positive?

          next true if atom.h_count.positive?

          (VALENCE.fetch(atom.element, 0.0) - sums[index]).positive?
        end
      end

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
                      elsif atom.h_pinned || atom.charge.negative?
                        # An anionic heteroatom carries no implicit H
                        # (O- of an acetate/carboxylate: the recorded
                        # formula standardizes via the /p layer); a
                        # salt-annihilated atom stays at its anionic
                        # reading (h_pinned).
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
