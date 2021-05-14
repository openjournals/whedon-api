require 'uri'
require 'json'
require 'rest-client'
require 'time'
require_relative 'github'

include GitHub

module NeuroLibre

    def get_latest_book_build_sha(repository_address,custom_branch=nil)
        
        uri = URI(repository_address)
        target_repo = uri.path[1...] # user/repo

        if custom_branch.nil? 
            sha = github_client.commits(target_repo).map {|c,a| [c.commit.message,c.sha]}.select{ |e, i| e[/\--build-book/] }.first
        else
            sha = github_client.commits(target_repo,custom_branch).map {|c,a| [c.commit.message,c.sha]}.select{ |e, i| e[/\--build-book/] }.first
        end
        
        if !sha.nil? 
            # Return sha only 
            sha = sha[1]
        end

        return sha 

    end

    def get_built_books(commit_sha: nil,user_name: nil,repo_name: nil)
        # Returns a JSON array containing fields:  
        # - time_added 
        # - book_url 
        # - download_link
        # Depending on the request, array length would be > 1. In that case, 
        # elements will be returned in reverse chronological order so that 
        # result[0] corresponds to the latest. 
    
        api_url = "http://neurolibre-data.conp.cloud:8081/api/v1/resources/books"
    
        if !commit_sha.nil?
            api_url += "?commit_hash=#{commit_sha}"
        elsif !user_name.nil?
            api_url += "?user_name=#{user_name}"
        elsif !repo_name.nil?
            api_url += "?repo_name=#{repo_name}"
        end
        
        puts api_url
        response = RestClient::Request.new(
            method: :get,
            :url => api_url,
            verify_ssl: false,
            :user => 'neurolibre',
            :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
            :headers => { :content_type => :json }
        ).execute do |response|
        case response.code
        
        when 200
            
            result = JSON.parse(response)
    
            if result.is_a?(Array) && result.length()==1
                result = result.map {|c| {:time_added => Time.parse(c['time_added']),:book_url => c['book_url'], :download_url => c['download_url'] }}.to_json
            elsif result.is_a?(Array) && result.length() >1
                # Array in reverse chronological order
                result = result.map {|c| {:time_added => Time.parse(c['time_added']),:book_url => c['book_url'], :download_url => c['download_url'] }}.sort_by { |hash| hash[:time_added].to_i }.reverse.to_json
            end
            
            return result
        
        when 404
    
            result = nil
            warn "Requested resource does not exist."
            return result

        else 

            result = nil
            warn "Returned code #{response.code}"

        end
        end
    end

    def request_book_build(payload_in)
        # Payload contains repo_url and commit_hash
        begin
            puts "Attempting server-sent event stream connection..."
            block = proc { |response|
                response.error! unless response.code == "200"
                
                    response.read_body do |chunk|
                    # Not sure if sidekiq can dynamically feed this to 
                    # the browser if I were to upload payload in this loop. 
                    # Anyway, we'll need to resolve another bug on test server to find that out. 
                    puts chunk
                    end
            }
            RestClient::Request.execute(
                method: :post,
                :url => 'http://neurolibre-data.conp.cloud:8081/api/v1/resources/books',
                verify_ssl: false,
                :user => 'neurolibre',
                :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
                :payload => payload_in,
                :headers => { :content_type => :json },
                block_response: block
            )
        rescue
            response = RestClient::Request.new(
                method: :post,
                :url => 'http://neurolibre-data.conp.cloud:8081/api/v1/resources/books',
                verify_ssl: false,
                :user => 'neurolibre',
                :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
                :payload => payload_in,
                :headers => { :content_type => :json }
            ).execute do |response|
                case response.code
                when 409
        
                # Conflict: Means that a build with requested hash already exists. 
                # In that case, first we'll attempt to return build book.
        
                payload_in = JSON.parse(payload_in)
                puts "hit 409"
                puts payload_in['commit_hash']
                begin
                    result = get_built_books(commit_sha:payload_in['commit_hash'])
                    result = JSON.parse(result)
                    return result[0]['book_url']
                rescue
                    # We need a better indexing of successfull/failed attempts. More importantly 
                    # we also need to know if a build is ongoing. 
                    puts "Returning the latest successful book build"
                    reponame = URI(payload_in['repo_url']).path.split('/').last
                    result = get_built_books(repo_name:reponame)
                    result = JSON.parse(result)
                    return result[0]['book_url']
                end
        
                when 200
                
                    puts "pass"
                
                else
                
                    fail "Invalid response #{response.code} received."
                
                end
              end
            
        end

    end

    def validate_repository_content(repository_address)
        # Returns a JSON array containing fields:  
        # - response 
        # - reason
        # If response is true, then the reposiotry meets minimum file/folder 
        # level requirements. Otherwise, reason indicates why the repo 
        # is not valid.

        uri = URI(repository_address)
        # Drop first slash
        target_repo = uri.path[1...]
        
        base_folders = github_client.contents(target_repo).map {|c,t| [c.path,c.type]}.select { |e, i| i=='dir' }.flatten(1).select.with_index {|e,i| !i.odd?}
        folder_level_check = base_folders.include?('binder') && base_folders.include?('content')
    
        binder_configs = [
            "environment.yml",
            "data_requirement.json",
            "requirements.txt",
            "Pipfile",
            "Pipfile.lock",
            "setup.py",
            "Project.toml",
            "REQUIRE",
            "install.R",
            "apt.txt",
            "DESCRIPTION",
            "manifest.yml",
            "postBuild",
            "start",
            "runtime.txt",
            "default.nix",
            "Dockerfile",
            "start"
            ];
    
        # List required content. Updates require changing content_required.intersection(content_files).length() < 2 condition
        content_required = ['_toc.yml','_config.yml']
    
        # Initialize default reponse
        out = {:response => true, :reason => "Repository meets mimimum file/folder level requirements."}
    
        if folder_level_check
            
            # Check for BinderHub config files
            binder_files = github_client.contents(target_repo,:path => 'binder/').map {|c,t| [c.path,c.type]}.select { |e, i| i=='file' }.flatten(1).select.with_index {|e,i| !i.odd?}.map {|i| i.partition('/').last}
            if  binder_configs.intersection(binder_files).length() == 0
                out = {:response => false, :reason => "Binder folder does not contain a valid environment configuration file."}
            end
    
            # Check for _toc.yml and _config.yml
            content_files = github_client.contents(target_repo,:path => 'content/').map {|c,t| [c.path,c.type]}.select { |e, i| i=='file' }.flatten(1).select.with_index {|e,i| !i.odd?}.map {|i| i.partition('/').last}
            if content_required.intersection(content_files).length() < 2
                out =  {:response => false, :reason => "Missing _toc.yml or _config.yml under the content folder."}
            end
    
        else
            out = {:response => false, :reason => "Missing /binder or /content folder."}
        end
    
        return JSON.parse(out.to_json)
    end

end

require 'sinatra'
require 'action_mailer'

class Mailer < ActionMailer::Base
  def contact
    mail(
      :to      => "agahkarakuzu@gmail.com",
      :from    => "roboneuro@gmail.com",
      :subject => "Test") do |format|
        format.text
        format.html
    end
  end
end

configure do
  set :root,    File.dirname(__FILE__)
  set :views,   File.join(Sinatra::Application.root, 'views')
  set :haml,    { :format => :html5 }
    
  if production?
    ActionMailer::Base.smtp_settings = {
        user_name: ENV["SENDGRID_USERNAME"],
        password: ENV["SENDGRID_PASSWORD"],
        address: 'smtp.sendgrid.net',
        domain: 'heroku.com',
        port: 587,
        authentication: :plain,
        enable_starttls_auto: true
    }
    ActionMailer::Base.view_paths = File.join(Sinatra::Application.root, 'views')
  else
    ActionMailer::Base.delivery_method = :file
    ActionMailer::Base.file_settings = { :location => File.join(Sinatra::Application.root, 'tmp/emails') }
    ActionMailer::Base.view_paths = File.join(Sinatra::Application.root, 'views')
  end
end

post '/mail' do
  email = Mailer.contact
  email.deliver
end