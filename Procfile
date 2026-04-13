web: bundle exec rails server -b 0.0.0.0 -p $PORT
worker: bundle exec rake solid_queue:start
release: bundle exec rails db:migrate db:seed
