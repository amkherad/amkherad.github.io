# syntax = docker/dockerfile:1.2
FROM ruby:3.2.2 AS builder
ENV BUNDLE_PATH=/bundler

WORKDIR /src

# Install Basics
RUN apt-get update \
  && apt-get install -y \
    ca-certificates \
    nodejs \
    build-essential \
    npm \
    ncftp \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN gem install bundle jekyll

RUN npm install -g gh

COPY "/Gemfile" "."
COPY "/Gemfile.lock" "."

# Install Gems
RUN bundle install

COPY . .

ENV PATH="${PATH}:$HOME/gems/bin"

RUN bundle exec jekyll build

# Fetching the latest nginx image
FROM nginx:latest
# Copying built assets from builder
COPY --from=builder /src/_site/ /usr/share/nginx/html/
# Copying our nginx.conf
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf
