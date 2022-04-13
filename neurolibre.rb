require 'uri'
require 'json'
require 'rest-client'
require 'time'
require_relative 'github'
require 'mail'
require 'whedon'

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

    def get_latest_book_build_sha(repository_address, custom_branch=nil)
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

        if sha.kind_of?(Array)
            return sha[0]
        else
            return sha
        end

    end

    def get_latest_upstream_sha(forked_repo)
        # This does not take custom_branch as it is intended to find the
        # latest commit pushed by the user from its roboneurolibre fork. 
        target_repo = get_repo_name(forked_repo)
        sha = github_client.commits(target_repo).map {|c,a| [c.commit.author.name,c.sha]}.select{ |e, i| e != 'roboneuro' }.first[1]
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
            warn "There is not a book built at #{commit_sha} for #{user_name}/#{repo_name} on NeuroLibre test server."
            return result

        # We need a way to distinguish these cases.
        # I'm not sure that this is the place to raise an error, anyway.
        else
            abort("Returned code #{response.code}")
        end
        end
    end

    def parse_neurolibre_response(response)
        tmp =  response.to_str

        # Get string between message": and , which is the message
        binder_messages  =  tmp.each_line(chomp: true).map {|s| s[/(?<=message":)(.*)(?=,)/]}.compact
        binder_messages = binder_messages.map{|string| string.strip[1...-1].gsub(/\r?\n/,'')}

        binder_messages = binder_messages.join(',')
        binder_messages = binder_messages.split(',')
        
        # Fetch book build response into a hash
        tmp_chomped  =  tmp.each_line(chomp: true).map {|s| s[/\{([^}]+)\}/]}.compact
        book_json  = JSON.parse(tmp_chomped[-1])

        # We'll need to send a GET request at this point to fetch book build logs.

        return binder_messages, book_json
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
        :timeout => 3600, # Give 60 minutes
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

    def get_book_build_log(op_binder,repository_address,hash)
        
        jblogs = []

        binder_log = ":wilted_flower: We ran into a problem building your book. Please see the log files below.<details><summary> <b>BinderHub build log</b> </summary><pre><code>#{op_binder}</code></pre></details><p>If the BinderHub build looks OK, please see the Jupyter Book build log(s) below.</p>"
        jblogs.push(binder_log)

        target_repo = get_repo_name(repository_address)
        uname = target_repo.split("/")[0]
        repo = target_repo.split("/")[1]
        response = RestClient::Request.new(
            method: :get,
            :url => "http://neurolibre-data.conp.cloud/book-artifacts/#{uname}/github.com/#{repo}/#{hash}/book-build.log",
            verify_ssl: false,
            :user => 'neurolibre',
            :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
            :headers => { :content_type => :json }
        ).execute
        
        # Add the main book build log
        book_log = "<details><summary> <b>Jupyter Book build log</b> </summary><pre><code>#{response.to_str}</code></pre></details>"
        jblogs.push(book_log)
        #jblogs.push("<br>")

        # Now look into reports (if exists)
        response = RestClient::Request.new(
            method: :get,
            :url => "http://neurolibre-data.conp.cloud/book-artifacts/#{uname}/github.com/#{repo}/#{hash}/_build/html/reports",
            verify_ssl: false,
            :user => 'neurolibre',
            :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
            :headers => { :content_type => :json }
        ).execute
        
        # If returns something, then check for the pattern for execution log files
        # Create one dropdown per execution log
        if response.code == 200
            txt = response.to_str
            rgx = /href=['"]\K[^'"]+.log/
            logs = txt.scan(rgx)
            logs.each do |log_file|
                log = RestClient::Request.new(
                    method: :get,
                    :url => "http://neurolibre-data.conp.cloud/book-artifacts/#{uname}/github.com/#{repo}/#{hash}/_build/html/reports/#{log_file}",
                    verify_ssl: false,
                    :user => 'neurolibre',
                    :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
                    :headers => { :content_type => :json }
                ).execute

                cur_log= "<details><summary> <b>Execution error log</b> for <code>#{log_file.gsub('.log','')}</code> notebook (or MyST).</summary><pre><code>#{log.to_str}</code></pre></details>"

                jblogs.push(cur_log)
                #jblogs.push("<br>")
            end
        end
        
        msg = "<p>:lady_beetle: After inspecting the logs above, you can interactively debug your notebooks on our <a href=\"https://binder.conp.cloud\">BinderHub server</a>. For guidelines, please see <a href=\"https://docs.neurolibre.org/en/latest/TEST_SUBMISSION.html#debugging-for-long-neurolibre-submission\">the relevant documentation.</a></p>"
        jblogs.push(msg)
        # Return logs 
        return jblogs.join('')
    end

    def validate_repository_content(repository_address, custom_branch=nil)
        # Returns a JSON array containing fields:
        # - response
        # - reason
        # If response is true, then the repository meets minimum file/folder
        # level requirements. Otherwise, reason indicates why the repo
        # is not valid.

        uri = URI(repository_address)
        # Drop first slash
        target_repo = uri.path.delete_prefix('/')

        if custom_branch
            ref ="heads/#{custom_branch}"
        else
            ref = nil
        end

        # Confirm binder, content folders exist
        begin
            binder_folder = github_client.contents(target_repo,
                                                  :path => 'binder',
                                                  :ref => ref)
            content_folder = github_client.contents(target_repo,
                                                   :path => 'content',
                                                   :ref => ref)
        rescue Octokit::NotFound
            out = {:response => false,
                   :reason => "Missing 'binder' or 'content' folder for #{repository_address}"}
            return JSON.parse(out.to_json)
        end

        # Initialize default reponse
        out = {:response => true,
               :reason => "Repository meets mimimum file/folder level requirements."}

        binder_files = [];
        # Check for BinderHub config files
        binder_folder.each do |file|
            binder_files.append(file.name)
        end

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

        if  (binder_configs & binder_files).length() == 0
            out = {:response => false,
                   :reason => "Binder folder does not contain a valid environment configuration file."}
        end

        content_files = [];
        # Check for _toc.yml and _config.yml
        content_folder.each do |file|
            content_files.append(file.name)
        end

        content_required = ['_toc.yml','_config.yml'];

        if (content_required & content_files).length() < 2
            out =  {:response => false,
                    :reason => "Missing _toc.yml or _config.yml under the content folder."}
        end

        return JSON.parse(out.to_json)
    end

    def email_received_request(user_mail,repository_address,sha,commit_sha,jid)
        options_mail = {
        :address => "smtp.sendgrid.net",
        :port                 => 587,
        :user_name            => 'apikey',
        :domain               => 'neurolibre.org',
        :password             => ENV['SENDGRID_API_TOKEN'],
        :authentication       => 'plain',
        :enable_starttls_auto => true  }

      Mail.defaults do
        delivery_method :smtp, options_mail
      end

      mail = Mail.deliver do
        to       user_mail
        from    'RoboNeuro <noreply@neurolibre.org>'
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
                <p>We have successfully received your request to build a NeuroLibre preprint.</p>
                <h3><b>Your submission key is <code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{sha}</code></b></h3>
                <div style=\"background-color:#f0eded;border-radius:15px;padding:10px\">
                <p>We would like to remind you that the build process may take a while. We will send you the results when it is completed.</p>
                <p>You can access the process page by clicking this button</p>
                <a href=\"https://roboneuro.herokuapp.com/preview?id=#{jid}\">
                <button type=\"button\" style=\"background-color:red;color:white;border-radius:6px;box-shadow:5px 5px 5px grey;padding:10px 24px;font-size: 14px;border: 2px solid #FFFFFF;\">RoboNeuro Build</button>
                </a>
                </div>
                <h3><b>Building book at Git sha <a href=\"https://github.com/#{repository_address}/commit/#{commit_sha}\"><code style=\"background-color:#d3d3d3;border-radius:6px;padding:2px;\">#{commit_sha[0...6]}</code></a></b></h3>
                <p>For further information, please visit our <a href=\"https://docs.neurolibre.org/en/latest/\">documentation</a>.</p>
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

        puts "Sending results email"
        book_url = results_book['book_url']
        puts "Debug book url"
        puts book_url
        response = RestClient::Request.new(
            method: :get,
            :url => book_url,
            verify_ssl: false,
            :headers => { :content_type => :json }
        ).execute do |response|
        case response.code
        when 404
            puts "Looks like the book build has failed. Setting book_url to nil."
            book_url = nil
        when 200
            puts "Book url successful."
        end
        end

        if book_url
            book_html = """
                        <div style=\"background-color:gainsboro;border-radius:15px;padding:10px\">
                        <p>🌱</p>
                        <h2><strong>Your <a href=\"#{book_url}\">NeuroLibre Book</a> is ready!</strong></h2>
                        <center><img style=\"height:250px;\" src=\"https://github.com/neurolibre/brand/blob/main/png/built.png?raw=true\"></center>
                        </div>
                        <p>You can see attached log files to inspect the build.</p>
                        """
        else
            book_html = """
                        <div style=\"background-color:#f0eded;border-radius:15px;padding:10px\">
                        <p><strong>Looks like your book build was not successful.</strong></p>
                        <center><img style=\"height:250px;\" src=\"https://github.com/neurolibre/brand/blob/main/png/sad_robo.png?raw=true\"></center>
                        <p>Please see attached log files to resolve the problem.</p>
                        </div>
                        """
        end

        File.open("binder_build_#{commit_sha}.log", "w+") do |f|
            results_binder.each { |element| f.puts(element) }
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
        :address => "smtp.sendgrid.net",
        :port                 => 587,
        :user_name            => 'apikey',
        :domain               => 'neurolibre.org',
        :password             => ENV['SENDGRID_API_TOKEN'],
        :authentication       => 'plain',
        :enable_starttls_auto => true  }

      Mail.defaults do
        delivery_method :smtp, options_mail
      end

      @mail = Mail.new do
        to       user_mail
        from    'RoboNeuro <noreply@neurolibre.org>'
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

    def fork_for_production(papers_repo)
        target_repo = get_repo_name(papers_repo)
        r = github_client.fork(target_repo, {:organization => 'roboneurolibre'})
        puts(r['html_url'])
        return r['html_url']
    end

    def get_config_for_prod(repository_address)
        # Here, repository_address is https://github.com/author/repository, ensured to have content/_config.yml.
        puts(repository_address)
        target_repo = get_repo_name(repository_address)
        puts("https://raw.githubusercontent.com/#{target_repo}/main/content/_config.yml")
        new_config = RestClient.get("https://raw.githubusercontent.com/#{target_repo}/main/content/_config.yml")

        if new_config.nil?
            warn "Target repository does not have content/_config.yml"
            return nil
        end

        pattern = Regexp.new(/binderhub_url:.*/).freeze
        if pattern.match?(new_config)
            # A line that mathces binderhub_url: (unique occurence in the _config template), then update the target.
            new_config = new_config.gsub(/binderhub_url:.*/, "binderhub_url: \"https://binder-mcgill.conp.cloud\"")
        else
            
            pattern_lb = Regexp.new(/launch_buttons:.*/).freeze
            if pattern_lb.match?(new_config)
                # Launch_buttons parent field exists, binderhub_url missing insert it under the parent field.
                new_config = new_config.gsub(/launch_buttons:.*/, "launch_buttons: \n  binderhub_url: \"https://binder-mcgill.conp.cloud\"")
            else
                # Both parent and child fields are missing, append them to the end.
                new_config = new_config + "\nlaunch_buttons: \n  binderhub_url: \"https://binder-mcgill.conp.cloud\""
            end
        end

        pattern_url = Regexp.new(/^\s*url\s*:.*/).freeze
        if pattern_url.match?(new_config)
            # A line that begins with url: (empty spaces allowed), then update url address.
            new_config = new_config.gsub(/^\s*url\s*:.*/, "  url: #{repository_address}")
        else
            pattern_rep = Regexp.new(/repository:.*/).freeze
            if pattern_rep.match?(new_config)
                # Repository parent field exists, url missing, add url.
                new_config = new_config.gsub(/repository.*/, "repository: \n  url: #{repository_address}")
            else
                # Both url and repository parent field are missing, append them to the end.
                new_config = new_config + "\nrepository: \n  url: #{repository_address}\n  branch: main"
            end
        end

        # return modified _config.yml content
        return new_config
    end

    def get_toc_for_prod(repository_address, author_repository, review_id)
        
        # Here, repository_address is https://github.com/author/repository, ensured to have content/_config.yml.
        target_repo = get_repo_name(repository_address)
        new_toc = RestClient.get("https://raw.githubusercontent.com/#{target_repo}/main/content/_toc.yml")
    
        if new_toc.nil?
            warn "Target repository does not have content/_config.yml"
            return nil
        end
    
        # Please do not modify empty spaces
        add = "\n- caption: NeuroLibre\n  chapters:\n  - url: #{author_repository}\n    title: Author\'s repository \n  - url: https://github.com/neurolibre/neurolibre-reviews/issues/#{review_id}\n    title: Technical screening record"
        
        return new_toc + add
    
    end

    def update_github_content(repository_address,content_path,new_content,commit_message,branch="main")

        # A repo for which roboneuro has write access (neurolibre or roboneurolibre orgs.)
        target_repo = get_repo_name(repository_address)
        
        # Get blob sha of the target file 
        blob = JSON.parse(RestClient.get("https://api.github.com/repos/#{target_repo}/contents/#{content_path}"))
        
        # Update the content
        r = github_client.update_contents(target_repo,
                                  content_path,
                                  commit_message,
                                  blob['sha'],
                                  new_content,
                                  :branch => branch)
        # Let caller infer in case this fails 
        if r.nil?
            return nil
        else
            return true
        end
    end

    def request_book_sync(payload_in)
        
        response = RestClient::Request.new(
            method: :post,
            :url => 'http://neurolibre-data-prod.conp.cloud:29876/api/v1/resources/books/sync',
            verify_ssl: false,
            :user => 'neurolibre',
            :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
            :payload => payload_in,
            :timeout => 1200, # Give 20 minutes
            :headers => { :content_type => :json }
            ).execute

        return response
    end

    def request_production_binderhub(payload_in)
        
        response = RestClient::Request.new(
            method: :post,
            :url => 'http://neurolibre-data-prod.conp.cloud:29876/api/v1/resources/binder/build',
            verify_ssl: false,
            :user => 'neurolibre',
            :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
            :payload => payload_in,
            :timeout => 1800, # Give 30 minutes
            :headers => { :content_type => :json }
            ).execute

        return response
    end

    def zenodo_create_buckets(payload_in)

        response = RestClient::Request.new(
        method: :post,
        :url => 'http://neurolibre-data-prod.conp.cloud:29876/api/v1/resources/zenodo/buckets',
        verify_ssl: false,
        :user => 'neurolibre',
        :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
        :payload => payload_in,
        :headers => { :content_type => :json }
        ).execute

        return response
    end

    def get_resource_lookup(repository_address)
        
        response = RestClient::Request.new(
            method: :get,
            :url => 'http://neurolibre-data.conp.cloud/book-artifacts/lookup_table.tsv',
            verify_ssl: false,
            :user => 'neurolibre',
            :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
            :headers => { :content_type => :json }
        ).execute
        
        # The second entry in the tsv file is the repository address, if found, then proceed.
        found= response.split("\n").map {|c| [c]}.select{ |e| e[0].split(",")[1] == repository_address }.join(', ')

        if (found.nil? || found.empty?)
            puts('Cannot find a lookup table.')
            lut = nil
        else
            cur_date,cur_url,cur_docker, cur_tag, cur_data_url, cur_data_doi = found.split(",")
            lut = {'repo' => cur_tag,
                   'docker' => cur_docker,
                   'data_url' => cur_data_url,
                   'data_doi' => cur_data_doi}
        end

        return lut

    end

    def zenodo_get_status(issue_id)

        post_params = {:issue_id => issue_id}.to_json
        
        response = RestClient::Request.new(
            method: :post,
            :url => 'http://neurolibre-data-prod.conp.cloud:29876/api/v1/resources/zenodo/list',
            verify_ssl: false,
            :user => 'neurolibre',
            :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
            :payload => post_params,
            :headers => { :content_type => :json }
            ).execute
        
        res = response.to_str

        regex_repository_upload = /(<li>zenodo_uploaded_repository)(.*?)(?=.json)/
        regex_data_upload = /(<li>zenodo_uploaded_data)(.*?)(?=.json)/
        regex_book_upload = /(<li>zenodo_uploaded_book)(.*?)(?=.json)/
        regex_docker_upload = /(<li>zenodo_uploaded_docker)(.*?)(?=.json)/
        regex_deposit = /(<li>zenodo_deposit)(.*?)(?=.json)/
        regex_publish = /(<li>zenodo_published)(.*?)(?=.json)/
        hash_regex = /_(?!.*_)(.*)/
        
        zenodo_regexs = [regex_repository_upload,regex_data_upload,regex_book_upload,regex_docker_upload]
        types = ['Repository', 'Data', 'Book','Docker']
                
        rsp = []
        
        if res[regex_deposit].nil? || res[regex_deposit].empty?
            rsp.push("<h3>Deposit</h3>:red_square: <b>Zenodo deposit records have not been created yet.</b>")
        else
            rsp.push("<h3>Deposit</h3>:green_square: Zenodo deposit records are found.")
        end
        
        rsp.push("<h3>Upload</h3><ul>")
        zenodo_regexs.each_with_index do |cur_regex,idx|
        if res[cur_regex].nil? || res[cur_regex].empty?
            rsp.push("<li>:red_circle: <b>#{types[idx]} archive is missing</b></li>")
        else
            tmp = res[cur_regex][hash_regex][1..-1]
            rsp.push("<li>:green_circle: #{types[idx]} archive (<code>#{tmp}</code>)</li>")
        end
        end
        rsp.push("</ul><h3>Publish</h3>")
        
        if res[regex_publish].nil? || res[regex_publish].empty?
            rsp.push(":small_red_triangle_down: <b>Zenodo DOIs have not been published yet.</b>")
        else
            rsp.push(":white_check_mark: Zenodo DOIs are published.")
        end
            
        return rsp.join('')

    end

    def zenodo_archive_items(payload_in,items,item_args)
        # Requests will be sent to NeuroLibre server one by one
        # Otherwise, it may time-out, also not elegant.

        response = []
        items.each_with_index do |it, idx|
            
            payload_in["item"] = it
            payload_in["item_arg"] = item_args[idx]
            payload_call = payload_in.to_json
            r = RestClient::Request.new(
                method: :post,
                :url => 'http://neurolibre-data-prod.conp.cloud:29876/api/v1/resources/zenodo/upload',
                verify_ssl: false,
                :user => 'neurolibre',
                :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
                :payload => payload_call,
                :timeout => 1800, # Give 30 minutes
                :headers => { :content_type => :json }
                ).execute

            response.push(r.to_str)
        end

        return response

    end

    def create_git_json(file_path, issue_id, papers_repo, journal_alias)
        id = "%05d" % issue_id
        crossref_xml_path = "#{journal_alias}.#{id}/10.55458.#{journal_alias}.#{id}.json"
    
        gh_response = github_client.create_contents(papers_repo,
                                                    crossref_xml_path,
                                                    "Creating 10.55458.#{journal_alias}.#{id}.json",
                                                    File.open("#{file_path.strip}").read,
                                                    :branch => "#{journal_alias}.#{id}")
    
        return gh_response.content.html_url
    end

end