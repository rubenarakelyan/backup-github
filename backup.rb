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
    load_and_validate_config!
    version_data = load_version_data(type: "repositories")

    client = Octokit::Client.new(access_token: @config["github_access_token"])
    client.auto_paginate = true

    repos = client.repos(client.user, { affiliation: "owner", visibility: options[:private_repos] ? "all" : "public" })

    if repos.length == 0
      puts "No repositories found to back up.".red
      exit
    end

    puts "Backing up #{repos.length} repositories..."
    puts

    repos.each do |repo|
      if repo.pushed_at == version_data[repo.name]
        puts "Skipping #{repo.name} because it hasn't changed".green
        puts
        next
      end

      archive_url = client.archive_link(repo.full_name, { format: "zipball" })
      puts "Downloading from #{archive_url}..."
      response = Faraday.get(archive_url)

      if response.status == 200
        filename = response.headers["content-disposition"].sub("attachment; filename=", "")
        File.write("#{@config['backup_directory']}/#{filename}", response.body)
        version_data[repo.name] = repo.pushed_at
        puts "Downloaded as #{filename}".green
      else
        puts "Received unexpected HTTP status #{response.status}".red
        puts response.body
      end

      puts
      sleep 1 # try not to hit the rate limit
    end

    save_version_data(type: "repositories", data: version_data)

    puts "Done".green
  rescue Octokit::Unauthorized
    puts "GitHub access token incorrect.".red
  rescue Faraday::Error => e
    puts "Error making request: #{e.message}".red
  end

  desc "backup-gists", "Back up GitHub Gists"
  def backup_gists
    load_and_validate_config!
    version_data = load_version_data(type: "gists")

    client = Octokit::Client.new(access_token: @config["github_access_token"])
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
      if gist.updated_at == version_data[gist.id]
        puts "Skipping #{gist.id} because it hasn't changed".green
        puts
        next
      end

      full_gist = client.gist(gist.id)
      archive_url = "https://gist.github.com/#{username}/#{full_gist.id}/archive/#{full_gist.history[0].version}.zip"
      puts "Downloading from #{archive_url}..."
      response = Faraday.get(archive_url)

      if response.status == 302
        redirected_response = Faraday.get(response.headers["location"])
        filename = redirected_response.headers["content-disposition"].sub("attachment; filename=", "")
        File.write("#{@config['backup_directory']}/#{filename}", redirected_response.body)
        version_data[gist.id] = gist.updated_at
        puts "Downloaded as #{filename}".green
      else
        puts "Received unexpected HTTP status #{response.status}".red
        puts response.body
      end

      puts
      sleep 1 # try not to hit the rate limit
    end

    save_version_data(type: "gists", data: version_data)

    puts "Done".green
  rescue Octokit::Unauthorized
    puts "GitHub access token incorrect.".red
  rescue Faraday::Error => e
    puts "Error making request: #{e.message}".red
  end

  no_commands do
    def load_and_validate_config!
      @config = YAML.safe_load_file("config.yaml")

      if @config["github_access_token"].nil? || @config["github_access_token"].empty?
        puts "GitHub access token not found - run `ruby backup.rb config` to set.".red
        exit
      end

      if @config["backup_directory"].nil? || @config["backup_directory"].empty?
        puts "Backup directory not found - run `ruby backup.rb config` to set.".red
        exit
      end

      if !File.directory?(@config["backup_directory"])
        puts "Backup directory does not exist.".red
        exit
      end
    rescue Errno::ENOENT
      puts "Config file not found - run `ruby backup.rb config` to create.".red
      exit
    end

    def load_version_data(type:)
      filename = version_data_filename(type: type)

      if File.exist?(filename)
        YAML.safe_load_file(filename, permitted_classes: [Time])
      else
        {}
      end
    end

    def save_version_data(type:, data:)
      if File.write(version_data_filename(type: type), data.to_yaml) == 0
        puts "Error saving version data - everything will be downloaded again next time".red
      end
    end

    def version_data_filename(type:)
      "#{@config['backup_directory']}/#{type}.yaml"
    end
  end

  def self.exit_on_failure?
    true
  end
end

BackupGitHub.start(ARGV)
