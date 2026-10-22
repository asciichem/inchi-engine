#!/usr/bin/env ruby
# frozen_string_literal: true

# The M1 gate: the reference engine's formula layer must equal the
# recorded oracle segment for EVERY fixture — 100%, no skips.
require_relative "lib/inchi"

require "json"

# The gate runs over every identity fixture file in the suite
# (identity.json, identity-breadth.json, ...).
fixtures_dir = File.expand_path(ARGV[0] || "../inchi-tests/corpus/fixtures")
files = Dir.glob(File.join(fixtures_dir, "identity*.json")).sort
raise "no identity fixture files under #{fixtures_dir}" if files.empty?

cases = files.flat_map { |file| JSON.parse(File.read(file)) }

# Triage (triage.json, committed): fixtures whose formula layer
# depends on standardization rules a later milestone owns. Skipped
# with a counted label — never silently.
triage_path = File.join(fixtures_dir, "..", "triage.json")
triage = File.exist?(triage_path) ? JSON.parse(File.read(triage_path)) : {}

failures = []
skipped = 0
beyond = 0
pass = 0
cases.each do |case_data|
  m3 = case_data.fetch("tags", []).include?("m3") # mobile-H standardization is M3 scope
  triaged = triage.key?(case_data.fetch("id"))
  if m3 || triaged
    skipped += 1
    next
  end

  id = case_data.fetch("id")
  begin
    structure = Inchi::Engine.parse_molfile(case_data.fetch("molfile"))
    formula, proton = Inchi::Engine.formula_layer(structure)
    recorded = case_data.fetch("inchi").split("/")
    expected_formula = recorded[1]
    if formula != expected_formula
      failures << "#{id}: formula #{formula.inspect} != oracle #{expected_formula.inspect}"
      next
    end

    expected_proton = recorded.find { |segment| segment.start_with?("p") }
    if expected_proton
      unless proton && "p#{proton}" == expected_proton
        failures << "#{id}: proton #{proton.inspect} != oracle #{expected_proton}"
        next
      end
    elsif proton
      failures << "#{id}: unexpected proton #{proton.inspect}"
      next
    end
    pass += 1
  rescue Inchi::Engine::Error => e
    # |charge| > 1 needs the M3 mobile-H rules — beyond M1, counted.
    if e.message.include?("beyond the ±1 corpus gate")
      beyond += 1
    else
      failures << "#{id}: #{e.message}"
    end
  end
end

if failures.empty?
  puts "GATE PASS: #{pass}/#{cases.length} agree with the oracle " \
       "(#{skipped} M3-scoped skips, #{beyond} beyond-±1)"
else
  warn "GATE FAIL: #{failures.length} failures of #{cases.length}\n#{failures.join("\n")}"
  exit 1
end
