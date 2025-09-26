ARG RUBY_VERSION=3.3.0
FROM ruby:${RUBY_VERSION}-slim AS base

ARG BUNDLER_VERSION=2.5.10

ENV RAILS_ENV=production NODE_ENV=production
WORKDIR /app

# OS deps
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential libpq-dev curl git nodejs npm \
  && rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=10 \
  CMD curl -fsS http://127.0.0.1:${PORT:-3000}/up || exit 1

# Gem setup
RUN gem install bundler -v ${BUNDLER_VERSION}
COPY Gemfile Gemfile.lock ./
RUN bundle config set deployment 'true' \
 && bundle config set without 'development test' \
 && bundle install --jobs 4

# App code
COPY . .

# JS build (if you use esbuild or importmaps/tailwind adjust accordingly)
# Example (comment out if not needed):
# RUN npm ci && npm run build

COPY ext/oqs_shim/liboqs_shim.so /app/ext/oqs_shim/
COPY ext/oqs_shim/liboqs.so.8 /usr/local/lib/

RUN ldconfig

# Precompile assets & bootsnap
RUN bundle exec rake assets:precompile

# Runtime port
EXPOSE 3000

# DB migrations on boot (optional; Kamal can run tasks instead)
CMD ["bash", "-lc", "bundle exec rake db:migrate && bundle exec puma -C config/puma.rb"]