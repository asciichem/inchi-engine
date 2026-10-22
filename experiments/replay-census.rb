$LOAD_PATH.unshift "/Users/mulgogi/src/asciichem/inchi-engine/lib"
require "inchi"
require "inchi/clayer"
require "json"

def heavy_graph(structure)
  keep = structure.atoms.each_with_index.select { |a, _| a.element != "H" }
  remap = {}
  keep.each_with_index { |(_, original), k| remap[original] = k }
  atoms = keep.map(&:first)
  bonds = structure.bonds.filter_map do |bond|
    next nil if structure.atoms[bond.from].element == "H" || structure.atoms[bond.to].element == "H"
    [remap[bond.from], remap[bond.to]]
  end
  [atoms, bonds]
end

# Replay the recorded /c token walk on OUR graph with backtracking.
# Each number = an atom bonded to the current walk atom (fresh atoms
# advance the walk; seen atoms close and the walk atom stays; on ')'
# the walk returns to the pushed branch point). Counts full solutions.
def replay_solutions(tokens, n, adj)
  assignment = {}          # rank -> our atom
  reverse = Array.new(n)   # our atom -> rank
  stack = []
  count = 0
  rank_of_step = []

  walk = lambda do |position, current_rank|
    if position >= tokens.length
      count += 1
      return count > 1
    end
    token = tokens[position]
    case token
    when Integer
      if (known = assignment[token])
        return count > 1 unless adj[current_rank].include?(known)
        walk.call(position + 1, current_rank)
      else
        adj[current_rank].each do |candidate|
          next if reverse[candidate]
          assignment[token] = candidate
          reverse[candidate] = token
          return true if walk.call(position + 1, candidate)
          assignment.delete(token)
          reverse[candidate] = nil
        end
      end
    when "("
      stack.push(current_rank)
      walk.call(position + 1, current_rank)
      return count > 1 if count > 1
      stack.pop
    when ")"
      saved = stack.pop
      walk.call(position + 1, saved)
      stack.push(saved)
      return count > 1 if count > 1
    when "-"
      walk.call(position + 1, current_rank)
    end
    count > 1
  end

  # The first token's rank = some atom (try all).
  first_rank = tokens.first
  return 0 unless first_rank.is_a?(Integer)
  n.times do |candidate|
    assignment[first_rank] = candidate
    reverse[candidate] = first_rank
    walk.call(1, candidate)
    assignment.delete(first_rank)
    reverse[candidate] = nil
    break if count > 1
  end
  count
end

cases = []
Dir.glob("../inchi-tests/corpus/fixtures/identity*.json").sort.each do |f|
  cases.concat(JSON.parse(File.read(f)))
end

stats = { checked: 0, no_c: 0, solvable: 0, unsolvable: 0, ambiguous: 0 }
unsolvable = []
cases.first(120).each do |case_data|
  id = case_data["id"]
  segment = case_data["inchi"].split("/").find { |s| s.match?(/\Ac[\d()\-]+\z/) }
  if segment.nil?
    stats[:no_c] += 1
    next
  end
  stats[:checked] += 1
  structure = Inchi::Engine.parse_molfile(case_data["molfile"])
  atoms, bonds = heavy_graph(structure)
  n = atoms.length
  adj = Array.new(n) { [] }
  bonds.each { |a, b| adj[a] << b; adj[b] << a }

  tokens = segment.scan(/\d+|[()\-]/).map { |t| t.match?(/\d/) ? Integer(t, 10) : t }
  solutions = replay_solutions(tokens, n, adj)
  if solutions.zero?
    stats[:unsolvable] += 1
    unsolvable << id if unsolvable.length < 5
  elsif solutions > 1
    stats[:ambiguous] += 1
  else
    stats[:solvable] += 1
  end
end

puts stats.inspect
puts "unsolvable: #{unsolvable.inspect}"
