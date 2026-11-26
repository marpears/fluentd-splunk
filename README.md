# fluentd-splunk

Fluentd image with [fluent-plugin-splunk-hec-radiant](https://github.com/gnanirahulnutakki/fluent-plugin-splunk-hec-radiant) for [redhat-cop/openshift-logforwarding-splunk](https://github.com/redhat-cop/helm-charts/tree/main/charts/openshift-logforwarding-splunk).

Built for **OpenShift 4.22** (RHCOS / RHEL 9) on digest-pinned `ubi9/ruby-33`. Gems are vendored under `vendor/cache` so the image builds offline (`bundle install --local`, no dnf).

Drop-in for the chart:

| Contract | Value |
|----------|--------|
| `args` | `fluentd` (`forwarding.fluentd.scl` must stay `false`) |
| Config | `/etc/fluent/fluent.conf` |
| Buffer | `/var/log/fluentd` |
| Plugin | `@type splunk_hec` (autoload symlink for radiant) |
| Ports | `24224` TCP/UDP |
| User | non-root, arbitrary UID (`1001:0`, `g=u`) |

Versions: Fluentd `1.20.1`, radiant `0.1.2` — see `Gemfile`.

## OpenShift build artifacts

Apply `deploy/openshift/build.yaml` into the chart namespace (typically `openshift-logging`). That creates two cluster objects:

| Object | Name | Role |
|--------|------|------|
| **ImageStream** | `fluentd-splunk` | Tag pointer for built images (`:latest`) |
| **BuildConfig** | `fluentd-splunk` | Recipe: git source, Docker strategy, output ImageStreamTag |

Nothing else is stored as a long-lived “Dockerfile object.” The `Containerfile`, `Gemfile*`, and `vendor/cache` live in git; the BuildConfig only records the clone URI/ref and that the Dockerfile path is `Containerfile`.

Each `oc start-build` creates a **Build** (`fluentd-splunk-N`) and a short-lived **build pod**. The BuildConfig keeps the last 3 successful and 3 failed Builds (`successfulBuildsHistoryLimit` / `failedBuildsHistoryLimit`). The durable artifact is the image pushed to:

`image-registry.openshift-image-registry.svc:5000/openshift-logging/fluentd-splunk:latest`

(also visible as ImageStreamTag `fluentd-splunk:latest` in that namespace).

## How the build process works

1. **Trigger** — `oc start-build -n openshift-logging fluentd-splunk` (or the console / a webhook). No local tree required.
2. **Clone** — OpenShift clones `https://github.com/marpears/fluentd-splunk.git` at ref `main` into the build pod (patch `source.git.uri` for an internal mirror; add a source secret if the repo is private).
3. **Buildah / Docker strategy** — Runs the repo `Containerfile` with build-arg `UBI_IMAGE` (digest-pinned `ubi9/ruby-33` by default):
   - **Builder stage:** `bundle install --local` from `vendor/cache`, Fluentd binstubs, radiant `@type splunk_hec` symlink.
   - **Runtime stage:** copies installed gems, sets OpenShift-friendly ownership, installs `/bin/entrypoint` that runs `fluentd -c /etc/fluent/fluent.conf`.
4. **Push** — The finished image is tagged and pushed to ImageStreamTag `fluentd-splunk:latest` in the internal registry.
5. **Consume** — The Helm chart’s StatefulSet pulls that ImageStream (see `deploy/openshift/values-image.yaml`). New builds update `:latest`; restart or roll the StatefulSet if pods do not pick it up automatically.

Disconnected clusters need both a reachable git mirror (with `vendor/cache` committed) and a mirrored `UBI_IMAGE` pullspec; the gem install itself does not call rubygems.org or dnf.

## Deploy

```bash
oc apply -n openshift-logging -f deploy/openshift/build.yaml
# Disconnected: patch source.git.uri + UBI_IMAGE to your mirrors
oc start-build -n openshift-logging fluentd-splunk --follow

helm upgrade --install openshift-logforwarding-splunk \
  ./openshift-logforwarding-splunk \
  --namespace openshift-logging \
  -f deploy/openshift/values-image.yaml \
  --set forwarding.splunk.token=<HEC_TOKEN> \
  --set forwarding.splunk.hostname=<splunk-hec-host>
```

Useful checks:

```bash
oc get is,bc,builds -n openshift-logging -l app.kubernetes.io/name=fluentd-splunk
oc logs -n openshift-logging -f build/fluentd-splunk-1
oc describe is fluentd-splunk -n openshift-logging
```

Local smoke-test: `podman build -t fluentd-splunk:local -f Containerfile .` (add `--network=none` once the base image is present).

## Update the base image

1. `skopeo inspect docker://registry.access.redhat.com/ubi9/ruby-33:latest --format '{{.Digest}}'`
2. Set `ARG UBI_IMAGE=...@sha256:...` in `Containerfile` and the matching build-arg in `deploy/openshift/build.yaml`
3. Commit / push, mirror the digest if disconnected, then `oc start-build … --follow`

## Update the Splunk HEC plugin

On a connected host (same Ruby major as the image):

```bash
# bump gem "fluent-plugin-splunk-hec-radiant" in Gemfile, then:
podman run --rm -v "$PWD:/opt/app-root/src:Z" -w /opt/app-root/src \
  -e HOME=/tmp \
  registry.access.redhat.com/ubi9/ruby-33 \
  bash -c 'bundle update fluent-plugin-splunk-hec-radiant && bundle package'
rm -rf vendor/bundle .bundle
```

Commit `Gemfile`, `Gemfile.lock`, and `vendor/cache/`, push, then `oc start-build … --follow`. Keep the radiant `@type splunk_hec` symlink in the `Containerfile` until [radiant#1](https://github.com/gnanirahulnutakki/fluent-plugin-splunk-hec-radiant/issues/1) is fixed upstream.

## Layout

```text
Containerfile
Gemfile / Gemfile.lock
vendor/cache/                 # offline gems (cloned into the build)
deploy/openshift/build.yaml   # ImageStream + BuildConfig
deploy/openshift/values-image.yaml
LICENSE
```

## License

Apache License 2.0 — see `LICENSE`.
