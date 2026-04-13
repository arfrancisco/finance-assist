web: bundle exec rails server -b 0.0.0.0 -p $PORT
worker: bundle exec rails jobs:start
release: bundle exec rails db:migrate db:seed
