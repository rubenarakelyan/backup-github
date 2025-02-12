require "bundler/inline"
require "yaml"

gemfile do
  source "https://rubygems.org"
  gem "thor", "~> 1.3.2"
  gem "rainbow", "~> 3.1.1"
  gem "octokit", "~> 9.2.0"
  gem "faraday-retry", "~> 2.2.1"
end

class BackupGitHub < Thor
  require "rainbow/refinement"
  using Rainbow

  desc "config", "Set configuration options"
  option :github_access_token, required: true
  option :backup_directory, required: true
  def config
    yaml_config = {
      "github_access_token" => options[:github_access_token],
      "backup_directory" => options[:backup_directory]
    }.to_yaml

    if File.write("config.yaml", yaml_config) > 0
      puts "Config saved successfully".green
    else
      puts "Error saving config".red
    end
  end

  desc "backup-repos", "Back up GitHub repositories"
  option :private_repos, type: :boolean
  def backup_repos
    config = YAML.safe_load_file("config.yaml")

    if config["github_access_token"].nil? || config["github_access_token"].empty?
      puts "GitHub access token not found - run `ruby backup.rb config` to set.".red
      exit
    end

    if config["backup_directory"].nil? || config["backup_directory"].empty?
      puts "Backup directory not found - run `ruby backup.rb config` to set.".red
      exit
    end

    if !File.directory?(config["backup_directory"])
      puts "Backup directory does not exist.".red
      exit
    end

    client = Octokit::Client.new(access_token: config["github_access_token"])
    client.auto_paginate = true

    repos = client.repos(client.user, { affiliation: "owner", visibility: options[:private_repos] ? "all" : "public" })

    if repos.length == 0
      puts "No repositories found to back up.".red
      exit
    end

    puts "Backing up #{repos.length} repositories..."
    puts

    repos.each do |repo|
      archive_url = client.archive_link(repo.full_name, { format: "zipball" })
      puts "Downloading from #{archive_url}..."
      response = Faraday.get(archive_url)

      if response.status == 200
        filename = response.headers["content-disposition"].sub("attachment; filename=", "")
        File.write("#{config["backup_directory"]}/#{filename}", response.body)
        puts "Downloaded as #{filename}".green
      else
        puts "Received unexpected HTTP status #{response.status}".red
        puts response.body
      end

      puts
      sleep 1 # try not to hit the rate limit
    end

    puts "Done".green
  rescue Errno::ENOENT
    puts "Config file not found - run `ruby backup.rb config` to create.".red
  rescue Octokit::Unauthorized
    puts "GitHub access token incorrect.".red
  rescue Faraday::Error => e
    puts "Error making request: #{e.message}".red
  end

  desc "backup-gists", "Back up GitHub Gists"
  def backup_gists
    config = YAML.safe_load_file("config.yaml")

    if config["github_access_token"].nil? || config["github_access_token"].empty?
      puts "GitHub access token not found - run `ruby backup.rb config` to set.".red
      exit
    end

    if config["backup_directory"].nil? || config["backup_directory"].empty?
      puts "Backup directory not found - run `ruby backup.rb config` to set.".red
      exit
    end

    if !File.directory?(config["backup_directory"])
      puts "Backup directory does not exist.".red
      exit
    end

    client = Octokit::Client.new(access_token: config["github_access_token"])
    client.auto_paginate = true

    gists = client.gists

    if gists.length == 0
      puts "No Gists found to back up.".red
      exit
    end

    username = client.user.login

    puts "Backing up #{gists.length} Gists..."
    puts

    gists.each do |gist|
      full_gist = client.gist(gist.id)
      archive_url = "https://gist.github.com/#{username}/#{full_gist.id}/archive/#{full_gist.history[0].version}.zip"
      puts "Downloading from #{archive_url}..."
      response = Faraday.get(archive_url)

      if response.status == 302
        redirected_response = Faraday.get(response.headers["location"])
        filename = redirected_response.headers["content-disposition"].sub("attachment; filename=", "")
        File.write("#{config["backup_directory"]}/#{filename}", redirected_response.body)
        puts "Downloaded as #{filename}".green
      else
        puts "Received unexpected HTTP status #{response.status}".red
        puts response.body
      end

      puts
      sleep 1 # try not to hit the rate limit
    end

    puts "Done".green
  rescue Errno::ENOENT
    puts "Config file not found - run `ruby backup.rb config` to create.".red
  rescue Octokit::Unauthorized
    puts "GitHub access token incorrect.".red
  rescue Faraday::Error => e
    puts "Error making request: #{e.message}".red
  end

  def self.exit_on_failure?
    true
  end
end

BackupGitHub.start(ARGV)
