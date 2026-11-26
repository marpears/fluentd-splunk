# Fluentd + fluent-plugin-splunk-hec-radiant for redhat-cop/openshift-logforwarding-splunk.
# Chart contract: args ["fluentd"], config /etc/fluent/fluent.conf,
# @type splunk_hec (and alias splunk_hec_radiant) via radiant.
# Offline: vendor/cache + bundle install --local. Mirror UBI and set UBI_IMAGE if disconnected.
# OCP 4.22 / RHCOS RHEL 9 → ubi9/ruby-33 (includes build tools; no dnf).

ARG UBI_IMAGE=registry.access.redhat.com/ubi9/ruby-33@sha256:0d6e8a324725cae9c6df34fd2200f3311c9c872fa478ea657c7aa03a928082db

FROM ${UBI_IMAGE} AS builder
USER 0
WORKDIR /opt/app-root/src
COPY Gemfile Gemfile.lock ./
COPY vendor/cache ./vendor/cache
ENV BUNDLE_DEPLOYMENT=true \
    BUNDLE_PATH=vendor/bundle \
    BUNDLE_CACHE_PATH=vendor/cache \
    MAKEFLAGS="-j$(nproc)"
RUN bundle config set --local deployment true && \
    bundle config set --local path vendor/bundle && \
    bundle config set --local bin bin && \
    bundle config set --local cache_all true && \
    bundle install --local && \
    bundle binstubs fluentd --force && \
    PLUGIN_DIR="$(bundle show fluent-plugin-splunk-hec-radiant)/lib/fluent/plugin" && \
    # radiant#1: registers as splunk_hec but file is out_splunk_hec_radiant.rb
    ln -sf out_splunk_hec_radiant.rb "$PLUGIN_DIR/out_splunk_hec.rb" && \
    # Also accept @type splunk_hec_radiant (same class; eases migration / radiant docs)
    grep -q 'register_output("splunk_hec_radiant"' \
      "$PLUGIN_DIR/out_splunk_hec_radiant.rb" || \
      sed -i '/register_output("splunk_hec", self)/a\      Fluent::Plugin.register_output("splunk_hec_radiant", self)' \
        "$PLUGIN_DIR/out_splunk_hec_radiant.rb" && \
    rm -rf vendor/bundle/ruby/*/cache vendor/cache .bundle/cache && \
    find vendor/bundle -name "*.so" -exec strip {} + 2>/dev/null || true

FROM ${UBI_IMAGE}
LABEL name="fluentd-splunk" \
      summary="Fluentd with Splunk HEC for OpenShift log forwarding" \
      io.openshift.tags="logging,fluentd,splunk,hec" \
      io.openshift.expose-services="24224:fluentd"

ENV BUNDLE_DEPLOYMENT=true \
    BUNDLE_PATH=/opt/app-root/src/vendor/bundle \
    BUNDLE_GEMFILE=/opt/app-root/src/Gemfile \
    HOME=/var/log/fluentd \
    LANG=C.UTF-8 \
    PATH=/opt/app-root/src/bin:/opt/app-root/src/vendor/bundle/bin:/opt/app-root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

USER 0
COPY --from=builder --chown=1001:0 /opt/app-root/src /opt/app-root/src
COPY LICENSE /licenses/LICENSE
RUN mkdir -p /etc/fluent /var/log/fluentd && \
    chown -R 1001:0 /etc/fluent /var/log/fluentd /opt/app-root/src && \
    chmod -R g=u /etc/fluent /var/log/fluentd /opt/app-root/src && \
    printf '%s\n' \
      '#!/bin/sh' \
      'set -eu' \
      'cd /opt/app-root/src' \
      '[ "${1:-}" = fluentd ] && shift' \
      'exec bundle exec fluentd -c /etc/fluent/fluent.conf "$@"' \
      > /bin/entrypoint && chmod 755 /bin/entrypoint

USER 1001
WORKDIR /opt/app-root/src
EXPOSE 24224 24224/udp
ENTRYPOINT ["/bin/entrypoint"]
CMD ["fluentd"]
