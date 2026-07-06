#!/usr/bin/env ruby
# Génère FASTLANE_SESSION depuis Windows/Linux (portail développeur, pas App Store Connect).
# Usage PowerShell :
#   $env:APPLE_ID="eiter_94@hotmail.com"
#   $env:FASTLANE_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   ruby scripts/export-apple-session.rb

require "rubygems"
require "bundler/setup" rescue nil
require "spaceship"

user = ENV["APPLE_ID"].to_s.strip
pass = ENV["FASTLANE_PASSWORD"].to_s.strip

if user.empty? || pass.empty?
  warn "Variables requises : APPLE_ID et FASTLANE_PASSWORD (mot de passe pour app)"
  exit 1
end

puts "Connexion portail développeur Apple (#{user})…"
Spaceship::Portal.login(user, pass)
session = Spaceship::Portal.client.store_cookie

unless session && !session.empty?
  warn "Échec : session vide. Vérifie mot de passe pour app + conditions sur developer.apple.com"
  exit 1
end

teams = Spaceship::Portal.client.teams
if teams && !teams.empty?
  t = teams.find { |x| x["type"] == "Individual" } || teams.first
  puts "Team ID : #{t['teamId']} (#{t['name']})"
  puts "(optionnel : secret GitHub APPLE_TEAM_ID = #{t['teamId']})"
end

puts "\n========== COPIE TOUT CE BLOC dans GitHub secret FASTLANE_SESSION ==========\n"
puts session
puts "========== FIN =========="