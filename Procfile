web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb -e RACK_ENV=$RACK_ENV
worker: bundle exec sidekiq -c 3 -t 25 -r ./whedon.rb -e RACK_ENV=$RACK_ENV
