FROM ruby:3
RUN mkdir -p /opt/replacer
ENV LANG=C.UTF-8 \
    BUNDLE_JOBS=4 \
    BUNDLE_APP_CONFIG=/opt/replacer/.bundle

COPY Gemfile Gemfile.lock /opt/replacer

WORKDIR /opt/replacer
RUN bundle config --local path .cache/bundle
RUN --mount=type=cache,target=/opt/replacer/.cache/bundle \
    bundle install && \
    mkdir -p vendor && \
    cp -ar .cache/bundle vendor/bundle
RUN bundle config --local path vendor/bundle

COPY run.rb /opt/replacer
COPY lib /opt/replacer/lib

CMD ["bundle", "exec", "ruby", "run.rb"]
