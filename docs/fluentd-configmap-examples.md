# Fluentd ConfigMap examples (radiant Splunk HEC)

The chart mounts ConfigMap key `td-agent.conf` as `/etc/fluent/fluent.conf`.

## Is `@type splunk_hec` still valid?

**Yes.** That is the type the stock [redhat-cop/openshift-logforwarding-splunk](https://github.com/redhat-cop/helm-charts/tree/main/charts/openshift-logforwarding-splunk) ConfigMap uses, and it is what radiant registers in code (`Fluent::Plugin.register_output("splunk_hec", …)`).

This image does **not** ship Splunk’s EOL `fluent-plugin-splunk-hec` gem. Both gems claim the `splunk_hec` type, so they cannot be loaded together. Radiant replaces the old plugin for that type. The image also registers **`splunk_hec_radiant`** as an alias to the same class, so you can migrate configs either by keeping the old type or by renaming explicitly.

| Config | Behavior in this image |
|--------|-------------------------|
| `@type splunk_hec` | Radiant HEC output (chart / old-config compatible) |
| `@type splunk_hec_radiant` | Same radiant class under the new type name |

Secrets and connection details are normally injected as env vars by the Helm chart (`SPLUNK_*`, `SHARED_KEY`, …).

## Chart-compatible (default) — `@type splunk_hec`

No ConfigMap change required when moving from an image that used the EOL Splunk plugin to this one.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openshift-logforwarding-splunk
  namespace: openshift-logging
  labels:
    app.kubernetes.io/component: fluentd
data:
  fluentd-loglevel: "warn"
  splunk-insecure: "true"
  splunk-hostname: "splunk.example.com"
  splunk-port: "8088"
  splunk-protocol: "https"
  splunk-index: "openshift"
  splunk-sourcetype: "openshift"
  splunk-source: "openshift"
  td-agent.conf: |
    <system>
      log_level "#{ENV['LOG_LEVEL']}"
    </system>

    <source>
      @type forward
      @id input1
      port 24224
      <transport tls>
        cert_path /secret/fluentd/tls.crt
        private_key_path /secret/fluentd/tls.key
        private_key_passphrase "#{ENV['FLUENTD_SSL_PASSPHRASE']}"
      </transport>
      <security>
        shared_key "#{ENV['SHARED_KEY']}"
        self_hostname "#{ENV['HOSTNAME']}"
      </security>
    </source>

    <match **>
      @type splunk_hec
      protocol "#{ENV['SPLUNK_PROTOCOL']}"
      insecure_ssl "#{ENV['SPLUNK_INSECURE']}"
      hec_host "#{ENV['SPLUNK_HOST']}"
      hec_port "#{ENV['SPLUNK_PORT']}"
      hec_token "#{ENV['SPLUNK_TOKEN']}"
      index "#{ENV['SPLUNK_INDEX']}"
      sourcetype "#{ENV['SPLUNK_SOURCETYPE']}"
      source "#{ENV['SPLUNK_SOURCE']}"
      host "#{ENV['NODE_NAME']}"
      <buffer>
        @type memory
        chunk_limit_records 100000
        chunk_limit_size 200m
        flush_interval 5s
        flush_thread_count 1
        overflow_action block
        retry_max_times 3
        total_limit_size 600m
      </buffer>
    </match>
```

## Explicit radiant type — `@type splunk_hec_radiant`

Same settings; only the type string changes. Useful when you want configs to show they are on the community plugin.

```yaml
  td-agent.conf: |
    <match **>
      @type splunk_hec_radiant
      protocol "#{ENV['SPLUNK_PROTOCOL']}"
      insecure_ssl "#{ENV['SPLUNK_INSECURE']}"
      hec_host "#{ENV['SPLUNK_HOST']}"
      hec_port "#{ENV['SPLUNK_PORT']}"
      hec_token "#{ENV['SPLUNK_TOKEN']}"
      index "#{ENV['SPLUNK_INDEX']}"
      sourcetype "#{ENV['SPLUNK_SOURCETYPE']}"
      source "#{ENV['SPLUNK_SOURCE']}"
      host "#{ENV['NODE_NAME']}"
      gzip_compression true
      <fields>
        cluster "#{ENV['CLUSTER_NAME']}"
      </fields>
      <buffer>
        @type memory
        flush_interval 5s
        overflow_action block
        total_limit_size 600m
      </buffer>
    </match>
```

## With Splunk CA verification

Set chart `forwarding.splunk.insecure: false` and provide `forwarding.splunk.ca_bundle`. The chart mounts the CA at `/secret/splunk/splunk-ca.crt`.

```yaml
  td-agent.conf: |
    <match **>
      @type splunk_hec
      protocol https
      insecure_ssl false
      hec_host "#{ENV['SPLUNK_HOST']}"
      hec_port "#{ENV['SPLUNK_PORT']}"
      hec_token "#{ENV['SPLUNK_TOKEN']}"
      index "#{ENV['SPLUNK_INDEX']}"
      sourcetype "#{ENV['SPLUNK_SOURCETYPE']}"
      source "#{ENV['SPLUNK_SOURCE']}"
      host "#{ENV['NODE_NAME']}"
      ca_file /secret/splunk/splunk-ca.crt
      require_ssl_min_version true
      <buffer>
        @type memory
        flush_interval 5s
        overflow_action block
        total_limit_size 600m
      </buffer>
    </match>
```

## Dynamic index from tag (radiant)

```yaml
  td-agent.conf: |
    <match app.**>
      @type splunk_hec
      hec_host "#{ENV['SPLUNK_HOST']}"
      hec_port "#{ENV['SPLUNK_PORT']}"
      hec_token "#{ENV['SPLUNK_TOKEN']}"
      protocol https
      insecure_ssl "#{ENV['SPLUNK_INSECURE']}"
      index ${tag[1]}
      sourcetype openshift:container
      source "#{ENV['SPLUNK_SOURCE']}"
      host "#{ENV['NODE_NAME']}"
      <buffer tag>
        @type memory
        flush_interval 5s
        overflow_action block
      </buffer>
    </match>
```

## File buffer (persistent volume)

When the chart enables `forwarding.fluentd.persistence`, point the buffer at `/var/log/fluentd` (the volume mount used by this image and the chart).

```yaml
  td-agent.conf: |
    <match **>
      @type splunk_hec
      hec_host "#{ENV['SPLUNK_HOST']}"
      hec_port "#{ENV['SPLUNK_PORT']}"
      hec_token "#{ENV['SPLUNK_TOKEN']}"
      protocol "#{ENV['SPLUNK_PROTOCOL']}"
      insecure_ssl "#{ENV['SPLUNK_INSECURE']}"
      index "#{ENV['SPLUNK_INDEX']}"
      sourcetype "#{ENV['SPLUNK_SOURCETYPE']}"
      source "#{ENV['SPLUNK_SOURCE']}"
      host "#{ENV['NODE_NAME']}"
      <buffer>
        @type file
        path /var/log/fluentd/fluentd-buffers/buffer
        flush_mode interval
        flush_interval 5s
        flush_thread_count 2
        retry_type exponential_backoff
        retry_forever true
        retry_max_interval 30
        chunk_limit_size 200m
        total_limit_size 600m
        overflow_action block
      </buffer>
    </match>
```

## Minimal standalone (no TLS on forward)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-splunk-lab
  namespace: openshift-logging
data:
  fluent.conf: |
    <system>
      log_level info
    </system>
    <source>
      @type forward
      port 24224
    </source>
    <match **>
      @type splunk_hec
      protocol https
      insecure_ssl true
      hec_host splunk.example.com
      hec_port 8088
      hec_token "#{ENV['SPLUNK_TOKEN']}"
      index main
      sourcetype fluentd:lab
      <buffer>
        @type memory
        flush_interval 1s
      </buffer>
    </match>
```

> This image’s entrypoint always loads `/etc/fluent/fluent.conf`. The chart mounts that path from key `td-agent.conf`; a custom ConfigMap must use the same mount path (or key → `fluent.conf` under `/etc/fluent/`).
