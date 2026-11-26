# fluentd-splunk

Fluentd container image with the community [fluent-plugin-splunk-hec-radiant](https://github.com/gnanirahulnutakki/fluent-plugin-splunk-hec-radiant) plugin, for OpenShift log forwarding to Splunk HEC via [redhat-cop/openshift-logforwarding-splunk](https://github.com/redhat-cop/helm-charts/tree/main/charts/openshift-logforwarding-splunk).

Built for **OpenShift 4.22** (RHCOS / RHEL 9) on digest-pinned `ubi9/ruby-33`. Gems are vendored under `vendor/cache` for offline / disconnected builds (`bundle install --local`, no dnf).

## Plugin types (`@type`)

Splunk’s original `fluent-plugin-splunk-hec` is **EOL** and is **not** installed in this image (it collides on the same Fluentd type name and is a poor fit for Ruby 3.3). Radiant is the maintained replacement and **registers as `splunk_hec`**, so existing chart / config using the old type keeps working.

| `@type` | Supported here | Notes |
|---------|----------------|--------|
| `splunk_hec` | Yes (recommended for charts) | Same type string as the EOL Splunk plugin — drop-in for redhat-cop ConfigMaps |
| `splunk_hec_radiant` | Yes | Alias to the same radiant class (explicit “new plugin” name) |

Migration: leave `@type splunk_hec` unchanged when switching images, or rename to `@type splunk_hec_radiant` when you want the new name in config. Parameter names are compatible for typical HEC settings (`hec_host`, `hec_token`, `index`, …).

Drop-in for the chart:

| Contract | Value |
|----------|--------|
| `args` | `fluentd` (`forwarding.fluentd.scl` must stay `false`) |
| Config | `/etc/fluent/fluent.conf` |
| Buffer | `/var/log/fluentd` |
| Plugin | `@type splunk_hec` or `@type splunk_hec_radiant` |
| Ports | `24224` TCP/UDP |
| User | non-root, arbitrary UID (`1001:0`, `g=u`) |

Versions: Fluentd `1.20.1`, radiant `0.1.2` — see `Gemfile`.

## Docs

| Doc | Contents |
|-----|----------|
| [docs/openshift-build-and-deploy.md](docs/openshift-build-and-deploy.md) | BuildConfig / ImageStream, build flow, Helm deploy, updating base image and plugin |
| [docs/fluentd-configmap-examples.md](docs/fluentd-configmap-examples.md) | ConfigMap examples for both `@type` names and migration notes |

## Layout

```text
Containerfile
Gemfile / Gemfile.lock
vendor/cache/
deploy/openshift/          # ImageStream, BuildConfig, Helm values overlay
docs/                      # build/deploy guide + ConfigMap examples
LICENSE
```

## License

Apache License 2.0 — see `LICENSE`.
