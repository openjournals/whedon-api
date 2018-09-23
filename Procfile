web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb -E $RACK_ENV
worker: bundle exec sidekiq -c 3 -t 25 -r ./workers.rb
