# Development/test image. Source is bind-mounted by compose; gems live in the image.
FROM ruby:3.4.12

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000
CMD ["bash", "-c", "rm -f tmp/pids/server.pid && bin/rails db:prepare && bin/rails server -b 0.0.0.0"]
