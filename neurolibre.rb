require 'uri'
require 'json'
require 'rest-client'
require 'time'
require_relative 'github'
require 'mail'

include GitHub

module NeuroLibre

    class << self
        attr_accessor :logo
        attr_accessor :header_start
        attr_accessor :header_finish
        attr_accessor :footer
      end
      self.logo = "https://raw.githubusercontent.com/neurolibre/docs.neurolibre.com/master/source/img/logo_neurolibre_old.png"
      self.header_start = """
                          <div style=\"background-color:#333;padding:3px;border-radius:10px;\">
                          <center><img src=\" https://github.com/neurolibre/brand/blob/main/png/neurolibre_test_start.png?raw=true \" height=\"200px\"></img>
                          </div>
                          """
      self.header_finish = """
                          <div style=\"background-color:#333;padding:3px;border-radius:10px;\">
                          <center><img src=\" https://github.com/neurolibre/brand/blob/main/png/neurolibre_test_finish.png?raw=true \" height=\"200px\"></img>
                          </div>
                          """
          self.footer =   """
                          <div style=\"background-color:#333;height:70px;border-radius:10px;\">
                          <p><img src=\" https://github.com/neurolibre/neurolibre.com/blob/master/static/img/favicon.png?raw=true \" height=\"70px\" style=\"float:left;\"></p>
                          <p><a href=\"https://twitter.com/neurolibre?lang=en\"><img style=\"height:45px;margin-right:10px;float:right;margin-top:12px;\" src=\"https://cdn2.iconfinder.com/data/icons/black-white-social-media/32/online_social_media_twitter-512.png\"></a></p>
                          <a href=\"https://github.com/neurolibre\"><img style=\"height:45px;margin-right:10px;float:right;margin-top:12px;\" src=\"https://cdn2.iconfinder.com/data/icons/black-white-social-media/64/github_social_media_logo-512.png\"></a>
                          <a href=\"https://neurolibre.herokuapp.com\"><img style=\"height:45px;margin-right:10px;float:right;margin-top:12px;\" src=\"https://cdn3.iconfinder.com/data/icons/black-white-social-media/32/www_logo_social_media-512.png\"></a>
                          </p></div>
                          """
    def is_email_valid? email
        email =~URI::MailTo::EMAIL_REGEXP
    end

    def get_repo_name(in_address, for_pdf=false)
        
        if for_pdf
            uri = URI(in_address)
            if uri.kind_of?(URI::HTTP) or uri.kind_of?(URI::HTTPS)
                # This is full url, fetch user/repo
                target_repo = uri # user/repo
            else
                # assumes username/repo
                target_repo = "https://github.com/#{in_address}"
            end
        else
            uri = URI(in_address)
            if uri.kind_of?(URI::HTTP) or uri.kind_of?(URI::HTTPS)
                # This is full url, fetch user/repo
                target_repo = uri.path[1...] # user/repo
            else
                # assumes username/repo
                target_repo = in_address
            end
        end

        return target_repo
    end

    def get_latest_book_build_sha(repository_address,custom_branch=nil)
        
        target_repo = get_repo_name(repository_address)

        if custom_branch.nil? 
            #sha = github_client.commits(target_repo).map {|c,a| [c.commit.message,c.sha]}.select{ |e, i| e[/\--build-book/] }.first
            begin
                sha = github_client.commits(target_repo).map {|c,a| [c.sha]}.first
            rescue
                sha = nil
            end
        else
            #sha = github_client.commits(target_repo,custom_branch).map {|c,a| [c.commit.message,c.sha]}.select{ |e, i| e[/\--build-book/] }.first
            begin 
                sha = github_client.commit(target_repo,custom_branch)['sha']
            rescue
                sha = nil
            end
        end

        return sha[0]

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

    def parse_neurolibre_response(response)
        tmp =  response.to_str
        tmp_chomped  =  tmp.each_line(chomp: true).map {|s| s[/\{([^}]+)\}/]}
        # Get rid of nils
        tmp = tmp_chomped.compact
        jsn =  JSON.parse(tmp.to_json)
        jsn1  = jsn[0...-1].map {|c| JSON.parse(c) }
        # This is information about book build
        jsn2 = JSON.parse(jsn[-1])

        # We'll need to send a GET request at this point to fetch book build logs.

        return jsn1.map {|c| c['message']}, jsn2
    end

    def request_book_build(payload_in)
        # Payload contains repo_url and commit_hash

        response = RestClient::Request.new(
        method: :post,
        :url => 'http://neurolibre-data.conp.cloud:8081/api/v1/resources/books',
        verify_ssl: false,
        :user => 'neurolibre',
        :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
        :payload => payload_in,
        :timeout => 1800, # Give 30 minutes
        :headers => { :content_type => :json }
        ).execute do |response|
            case response.code
            when 200
                return parse_neurolibre_response(response)
            when 409
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
            if  (binder_configs & binder_files).length() == 0
                out = {:response => false, :reason => "Binder folder does not contain a valid environment configuration file."}
            end
    
            # Check for _toc.yml and _config.yml
            content_files = github_client.contents(target_repo,:path => 'content/').map {|c,t| [c.path,c.type]}.select { |e, i| i=='file' }.flatten(1).select.with_index {|e,i| !i.odd?}.map {|i| i.partition('/').last}
            if (content_required & content_files).length() < 2
                out =  {:response => false, :reason => "Missing _toc.yml or _config.yml under the content folder."}
            end
    
        else
            out = {:response => false, :reason => "Missing /binder or /content folder."}
        end
    
        return JSON.parse(out.to_json)
    end

    def email_received_request(user_mail,repository_address,sha,commit_sha,jid)
        options_mail = { 
        :address => "smtp.gmail.com",
        :port                 => 587,
        :user_name            => ENV['RN_GMAIL_NAME'],
        :password             => ENV['RN_GMAIL_PASS'],
        :authentication       => 'plain',
        :enable_starttls_auto => true  }

      Mail.defaults do
        delivery_method :smtp, options_mail
      end

      mail = Mail.deliver do
        to       user_mail
        from    'RoboNeuro'
        subject "NeuroLibre - Your test request for #{repository_address}"
      
        text_part do
          body "We have received your request for #{repository_address} commit #{commit_sha}."
        end
      
        html_part do
          content_type 'text/html; charset=UTF-8'
          body  """
                <body>
                #{NeuroLibre.header_start}
                <center>
                <h3><code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{repository_address}</code></h3>
                <p>This mail is to confirm that we have successfully received your request to build a NeuroLibre book.</p>
                <h3><b>Your submission key is <code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{sha}</code></b></h3>
                <div style=\"background-color:#f0eded;border-radius:15px;padding:10px\">
                <p>We would like to remind you that the build process may take a while. We will send you the results when it is completed.</p>
                <p>You can access the process page by clicking this button</p>
                <a href=\"https://roboneuro.herokuapp.com/preview?id=#{jid}\">
                <button type=\"button\" style=\"background-color:red;color:white;border-radius:6px;box-shadow:5px 5px 5px grey;padding:10px 24px;font-size: 14px;border: 2px solid #FFFFFF;\">RoboNeuro Build</button>
                </a>
                </div>
                <h3><b>Building book at Git sha <a href=\"https://github.com/#{repository_address}/commit/#{commit_sha}\"><code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{commit_sha[0...6]}</code></a></b></h3>
                <p>For further information, please visit our <a href=\"https://docs.neurolibre.com/en/latest/\">documentation</a>.</p>
                <p>Robotically yours,</p>
                <p>RoboNeuro</p>
                </center>
                </body>
                #{NeuroLibre.footer}
                """
        end
      end
    end

    def email_processed_request(user_mail,repository_address,sha,commit_sha,results_binder,results_book)
        
        
        book_url = results_book['book_url']

        if book_url
            book_html = """
                        <div style=\"background-color:gainsboro;border-radius:15px;padding:10px\">
                        <p>🌱</p>
                        <h2><strong>Your <a href=\"#{book_url}\">NeuroLibre Book</a> is ready!</strong></h2>
                        <center><img style=\"height:50px;\" src=\"https://github.com/neurolibre/brand/blob/main/png/built.png?raw=true\"></center>
                        </div>
                        <p>You can see attached log files to inspect the build.</p>
                        """
        else
            book_html = """
                        <div style=\"background-color:#dc3545;border-radius:15px;padding:10px\">
                        <p><strong>Looks like your book build was not successful.</strong></p>
                        <p>Please see attached log files to resolve the problem.</p>
                        </div>
                        """
        end

        File.open("binder_build_#{commit_sha}.log", "w+") do |f|
            results_binder.each { |element| f.puts(element.strip) }
        end

        book_log = RestClient::Request.new(
        method: :get,
        :url => results_book['book_build_logs'],
        verify_ssl: false,
        :user => 'neurolibre',
        :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
        :headers => { :content_type => :json }
        ).execute

        File.open("book_build_#{commit_sha}.log", "w+") do |f|
        # Remove ANSI colors
            book_log.each_line { |element| f.puts(element.strip.gsub(/\e\[([;\d]+)?m/, '')) }
        end

        options_mail = { 
        :address => "smtp.gmail.com",
        :port                 => 587,
        :user_name            => ENV['RN_GMAIL_NAME'],
        :password             => ENV['RN_GMAIL_PASS'],
        :authentication       => 'plain',
        :enable_starttls_auto => true  }

      Mail.defaults do
        delivery_method :smtp, options_mail
      end

      @mail = Mail.new do
        to       user_mail
        from    'RoboNeuro'
        subject "NeuroLibre - Finished book build for #{repository_address}"
      
        text_part do
          body "We have finished processing your request for #{repository_address} commit #{commit_sha}. Results #{results_binder}"
        end
        
        html_part do
          content_type 'text/html; charset=UTF-8'
          body  """
                <body>
                #{NeuroLibre.header_finish}
                <center>
                <h3><code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{repository_address}</code></h3>
                <p>Your test request <code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{sha}</code> has been completed.</p>
                #{book_html}
                <h3><b>Git reference for this build was <a href=\"https://github.com/#{repository_address}/commit/#{commit_sha}\"><code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{commit_sha[0...6]}</code></a></b></h3>
                <p>For further information, please visit our <a href=\"https://docs.neurolibre.com/en/latest/\">documentation</a>.</p>
                <p>Thank you for using our preview service,</p>
                <p>RoboNeuro</p>
                </center>
                </body>
                #{NeuroLibre.footer}
                """
         end

        add_file "./binder_build_#{commit_sha}.log"
        add_file "./book_build_#{commit_sha}.log"

      end
      
      @round_tripped_mail = Mail.new(@mail.encoded)
      @round_tripped_mail.deliver

      return book_url
    end


end