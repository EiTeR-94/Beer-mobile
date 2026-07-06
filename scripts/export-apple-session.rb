#!/usr/bin/env ruby
# Génère FASTLANE_SESSION (Windows OK) — portail développeur Apple.
#
# PowerShell :
#   New-Item -ItemType Directory -Force -Path C:\tmp
#   chcp 65001; $env:LC_ALL="en_US.UTF-8"; $env:LANG="en_US.UTF-8"
#   $env:APPLE_ID="eiter_94@hotmail.com"
#   $env:FASTLANE_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   ruby scripts/export-apple-session.rb
#
# Ruby recommandé : 3.3.x (pas 4.0 — fastlane instable)

require "fileutils"

if Gem.win_platform?
  FileUtils.mkdir_p("C:/tmp")
  FileUtils.mkdir_p(File.join(ENV["TEMP"] || "C:/tmp", "spaceship"))
end

require "spaceship"

user = ENV["APPLE_ID"].to_s.strip
pass = ENV["FASTLANE_PASSWORD"].to_s.strip

if user.empty? || pass.empty?
  warn "Variables requises : APPLE_ID et FASTLANE_PASSWORD (mot de passe pour app)"
  exit 1
end

puts "Connexion portail développeur Apple (#{user})…"

last_err = nil
3.times do |attempt|
  begin
    Spaceship::Portal.login(user, pass)
    last_err = nil
    break
  rescue StandardError => e
    last_err = e
    warn "Tentative #{attempt + 1}/3 échouée : #{e.message}"
    sleep 8 if attempt < 2
  end
end

if last_err
  warn "\nÉchec connexion Apple."
  warn "Vérifie : mot de passe POUR APP (appleid.apple.com), pas Hotmail."
  warn "Ouvre https://developer.apple.com/account et accepte les conditions."
  warn "Ruby 3.3.x recommandé (Ruby 4.0 + fastlane = souvent cassé)."
  raise last_err
end

session = Spaceship::Portal.client.store_cookie

unless session && !session.empty?
  warn "Session vide après login."
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