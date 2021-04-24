require 'uri'
require 'json'
require 'rest-client'
require 'time'
require_relative 'github'

include GitHub

module NeuroLibre

    def get_latest_book_build_sha(target_repo,custom_branch=nil)
        
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
                result = result.map {|c| {:time_added => Time.parse(c['time_added']),:book_url => c['book_url'], :download_url => c['download_url']} }.to_json
            elsif result.is_a?(Array) && result.length() >1
                # Array in reverse chronological order
                result = result.map {|c| {:time_added => Time.parse(c['time_added']),:book_url => c['book_url'], :download_url => c['download_url']} }.sort_by { |hash| hash[:time_added].to_i }.reverse.to_json
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
            result = get_built_books(commit_sha:payload_in['commit_hash'])
    
            return result
    
            when 200
            
                result = JSON.parse(result)
                return result
            
            else
            
                fail "Invalid response #{response.code} received."
            
            end
          end
    end

end