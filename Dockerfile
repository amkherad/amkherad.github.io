FROM jekyll/jekyll AS builder

USER 0

WORKDIR /src

COPY "/Gemfile" "."
COPY "/Gemfile.lock" "."

RUN mkdir _site

RUN chmod -R o+rw /src

# Install Gems
RUN bundle install

COPY . .

RUN chmod -R o+rw /src

RUN bundle exec jekyll build --trace

# Fetching the latest nginx image
FROM nginx:latest
# Copying built assets from builder
COPY --from=builder /src/_site/ /usr/share/nginx/html/
# Copying our nginx.conf
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf
