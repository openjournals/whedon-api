require 'mina/bundler'
require 'mina/git'
require 'mina/unicorn'
require 'mina/rbenv'

# Basic settings:
#   domain       - The hostname to SSH to.
#   deploy_to    - Path to deploy into.
#   repository   - Git repo to clone from. (needed by mina/git)
#   branch       - Branch name to deploy. (needed by mina/git)

set :term_mode, nil
set :domain, 'whedon.theoj.org'
set :deploy_to, '/home/deployer/whedon'
set :repository, 'git@github.com:openjournals/whedon-api.git'
set :branch, 'mina'
set :user, 'deployer'
set :forward_agent, true
set :port, '22'
set :unicorn_pid, "#{deploy_to}/shared/pids/unicorn.pid"

# For system-wide RVM install.
# set :rvm_path, '/usr/local/rvm/bin/rvm'

# Manually create these paths in shared/ (eg: shared/config/database.yml) in your server.
# They will be linked in the 'deploy:link_shared_paths' step.
set :shared_paths, ['config/secrets.yml', 'log', 'tmp']

# Optional settings:
#   set :user, 'foobar'    # Username in the server to SSH to.
#   set :port, '30000'     # SSH port number.
#   set :forward_agent, true     # SSH forward_agent.

# Put any custom mkdir's in here for when `mina setup` is ran.
# For Rails apps, we'll make some of the shared paths that are shared between
# all releases.
task :setup => :environment do
  queue! %[mkdir -p "#{deploy_to}/#{shared_path}/log"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/#{shared_path}/log"]

  queue! %[mkdir -p "#{deploy_to}/#{shared_path}/config"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/#{shared_path}/config"]

  queue! %[touch "#{deploy_to}/#{shared_path}/config/secrets.yml"]
  queue  %[echo "-----> Be sure to edit '#{deploy_to}/#{shared_path}/config/database.yml' and 'secrets.yml'."]

  if repository
    repo_host = repository.split(%r{@|://}).last.split(%r{:|\/}).first
    repo_port = /:([0-9]+)/.match(repository) && /:([0-9]+)/.match(repository)[1] || '22'

    queue %[
      if ! ssh-keygen -H  -F #{repo_host} &>/dev/null; then
        ssh-keyscan -t rsa -p #{repo_port} -H #{repo_host} >> ~/.ssh/known_hosts
      fi
    ]
  end
end

task :environment do
  invoke :'rbenv:load'
end

desc "Deploys the current version to the server."
task :deploy => :environment do
  to :before_hook do
    # Put things to run locally before ssh
  end
  deploy do
    # Put things that will set up an empty directory into a fully set-up
    # instance of your project.
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'deploy:cleanup'

    to :launch do
      invoke :'sidekiq:stop'
      invoke :'sidekiq:start'
      invoke :'unicorn:restart'
    end
  end
end


namespace :sidekiq do
  desc "start sidekiq"
  task :start => :environment do
    queue "cd #{deploy_to}/#{current_path}/ && bundle exec sidekiq -r ./whedon.rb -d -L #{deploy_to}/#{shared_path}/log/sidekiq.log"
  end

  desc "stop sidekiq"
  task :stop => :environment do
    queue "cd #{deploy_to}/#{current_path}/ && bundle exec sidekiqctl stop #{deploy_to}/tmp/pids/sidekiq.pid"
  end

  desc "restart sidekiq"
  task :restart => :environment do
    invoke :'sidekiq:stop'
    invoke :'sidekiq:start'
  end

end

# For help in making your deploy script, see the Mina documentation:
#
#  - http://nadarei.co/mina
#  - http://nadarei.co/mina/tasks
#  - http://nadarei.co/mina/settings
#  - http://nadarei.co/mina/helpers
