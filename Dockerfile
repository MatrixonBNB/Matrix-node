# syntax = docker/dockerfile:1

ARG RUBY_VERSION=3.3.4
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

ENV SECRET_KEY_BASE_DUMMY=1

# Set environment variables
ENV RAILS_ENV="production" \
    BUNDLE_PATH="/usr/local/bundle" \
    LANG="C.UTF-8" \
    RAILS_LOG_TO_STDOUT="enabled"

# Throw-away build stage
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libvips \
    pkg-config \
    libsecp256k1-dev \
    automake \
    autoconf \
    libtool \
    curl

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle config build.rbsecp256k1 --use-system-libraries && \
    bundle install

# Copy application code and precompile bootsnap
COPY . .
RUN bundle exec bootsnap precompile app/ lib/

# Final stage
FROM base

# Install only runtime dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    libvips \
    libsecp256k1-dev \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Set up non-root user
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER rails:rails

CMD ["bundle", "exec", "clockwork", "config/derive_facet_blocks.rb"]
