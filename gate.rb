#!/usr/bin/env ruby
# frozen_string_literal: true

# The M1 gate: the reference engine's formula layer must equal the
# recorded oracle segment for EVERY fixture — 100%, no skips.
require_relative "lib/inchi"

corpus = File.expand_path(ARGV[0] || "../inchi-tests/corpus/fixtures/identity.json")
require "json"
cases = JSON.parse(File.read(corpus))

failures = []
cases.each do |case_data|
  id = case_data.fetch("id")
  structure = Inchi::Engine.parse_molfile(case_data.fetch("molfile"))
  formula, proton = Inchi::Engine.formula_layer(structure)
  recorded = case_data.fetch("inchi").split("/")
  expected_formula = recorded[1]
  failures << "#{id}: formula #{formula.inspect} != oracle #{expected_formula.inspect}" if formula != expected_formula

  expected_proton = recorded.find { |segment| segment.start_with?("p") }
  if expected_proton
    failures << "#{id}: proton #{proton.inspect} != oracle #{expected_proton}" unless proton && "p#{proton}" == expected_proton
  elsif proton
    failures << "#{id}: unexpected proton #{proton.inspect}"
  end
rescue Inchi::Error => e
  failures << "#{id}: #{e.message}"
end

if failures.empty?
  puts "GATE PASS: #{cases.length}/#{cases.length} formula layers agree with the oracle"
else
  warn "GATE FAIL: #{failures.length}/#{cases.length}\n#{failures.join("\n")}"
  exit 1
end
