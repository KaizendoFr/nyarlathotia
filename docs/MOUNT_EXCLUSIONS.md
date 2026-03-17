# Mount Exclusions

Nyia Keeper automatically hides sensitive files (API keys, certificates, cloud credentials) from containers using Docker overlay mounts. This prevents accidental exposure of secrets to AI assistants while keeping the rest of your project fully visible.

## Default Patterns

The built-in exclusion list covers several categories of sensitive content:

**Cloud providers** -- `.aws/`, `.gcloud/`, `.azure/`, `.digitalocean/`, service account JSON files, AWS credential files, Azure publish settings, and more.

**SSH and certificates** -- `.ssh/`, `.gnupg/`, private keys (`*.pem`, `*.key`, `*.ppk`), certificates (`*.crt`, `*.csr`), and known-hosts files.

**Kubernetes and orchestration** -- `.kube/`, `.minikube/`, `.helm/`, kubeconfig files, and configs for K3s, Rancher, OpenShift, and Istio/Linkerd/Consul service meshes.

**Infrastructure as code** -- `.terraform/`, `.pulumi/`, Terraform state and variable files (`*.tfstate`, `*.tfvars`), and CloudFormation parameter files.

**CI/CD** -- `.jenkins/`, `.circleci/`, `.buildkite/`, GitHub Actions secrets, GitLab CI local variables, and ArgoCD/Tekton config files.

**Configuration management** -- `.ansible/`, `.chef/`, `.puppet/`, `.vagrant/`, Ansible vault files, Chef validation keys, and SaltStack configs.

**Package managers** -- `.npm/`, `.yarn/`, `.cargo/`, `.gem/`, `.m2/`, `.gradle/`, registry auth files (`.npmrc`, `.pypirc`), and language-specific credential stores. Package manager cache directories get writable tmpfs mounts so the container can use them without leaking data to the host.

**Environment and secrets files** -- `.env`, `.env.*`, `*secret*`, `*password*`, `credentials.json`, and similar patterns.

**Databases, message queues, and monitoring** -- connection configs for PostgreSQL, MySQL, Redis, Kafka, RabbitMQ, plus Datadog, New Relic, Prometheus, and Grafana configs.

**Shallow patterns** -- directories like `vault/`, `secrets/`, `credentials/`, `certs/`, and `backups/` are checked only at the project root and one level deep to avoid false positives inside dependency trees.

The full list is defined in `lib/mount-exclusions.sh` (functions `get_exclusion_patterns()`, `get_exclusion_dirs()`, `get_shallow_exclusion_dirs()`, and `get_exclusion_path_patterns()`).

## Custom Exclusions

Add your own exclusion patterns in `.nyiakeeper/exclusions.conf` at the root of your project:

```
# Basename patterns — match anywhere in the tree
*.secret
my-local-config.json
my-secrets/

# Root-anchored patterns — match only at project root
config/database.yml
docs/internal/

# Explicit root-anchor with leading /
/src/sensitive.key

# Explicit anywhere-match with **/ prefix
**/node_modules/
```

You can create this file manually or run:

```bash
nyia exclusions init
```

## Pattern Matching Rules

Patterns in `exclusions.conf` follow **gitignore conventions**:

| Pattern | Matching | Scope |
|---|---|---|
| `.env` | Basename | Matches `.env` at any depth |
| `secrets/` | Basename (dir) | Matches any directory named `secrets` anywhere |
| `*.backup` | Basename (glob) | Matches by extension anywhere |
| `config/database.yml` | Root-anchored | Matches only `<root>/config/database.yml` |
| `/src/` | Root-anchored | Matches only `<root>/src/` |
| `**/node_modules/` | Basename (explicit) | Matches `node_modules/` at any depth |

**Key rules:**

- **No `/` in pattern** (or only trailing `/`): matches anywhere by basename.
- **Contains `/`** (not just trailing): anchored to the project root.
- **Leading `/`**: explicitly root-anchored (even without other `/`).
- **`**/` prefix**: explicitly match anywhere (overrides root-anchoring).
- **Trailing `/`**: directory-only matching.
- **`#` at line start**: comment.

**Wildcards:** `*`, `?`, and `[...]` work inside patterns. Note that `*` can cross path
segments (unlike pure gitignore where `*` stops at `/`). For most exclusion configs this
makes no practical difference.

**Migration note:** If you previously used path patterns like `config/database.yml` expecting
them to match at any depth, they are now root-anchored (match only at project root). To
restore the previous match-anywhere behavior, prefix with `**/`: `**/config/database.yml`.

## Override Patterns

To force-include a file or directory that is hidden by default, prefix the pattern with `!`:

```
# Force-include .aws/ (overrides the default exclusion)
!.aws/

# Force-include a specific key file
!deploy-key.pem

# Force-include at project root only (root-anchored)
!config/credentials.json

# Force-include anywhere (explicit)
!**/vendor/
```

Override patterns follow the **same anchoring rules** as exclusion patterns:

- **Basename override** (`!.env.example`): force-includes matching files anywhere.
- **Root-anchored override** (`!config/credentials.json`): force-includes only at project root.
- **Explicit anywhere override** (`!**/vendor/`): force-includes at any depth.

## Workspace Mode

In [workspace mode](WORKSPACE.md), each repository can have its own `exclusions.conf`:

```
repo1/.nyiakeeper/exclusions.conf    # Applied to repo1 mount
repo2/.nyiakeeper/exclusions.conf    # Applied to repo2 mount
workspace/.nyiakeeper/exclusions.conf  # Applied to main workspace
```

The same built-in patterns apply to every repository independently. Both read-only (`ro`) and read-write (`rw`) mounts receive exclusions.

## CLI Options

### Disable for one session

Pass the `--disable-exclusions` flag to bypass all exclusions for a single session:

```bash
nyia-claude --disable-exclusions
```

The container will see every file in your project, including secrets. Use this only when you explicitly need the assistant to access excluded content.

### Disable via environment variable

Set the `ENABLE_MOUNT_EXCLUSIONS` environment variable to `false`:

```bash
ENABLE_MOUNT_EXCLUSIONS=false nyia-claude
```

This has the same effect as `--disable-exclusions`.

## Troubleshooting

### Why is my file hidden?

Run with `--verbose` to see every file and directory that gets excluded:

```bash
nyia-claude --verbose
```

The output will show lines like:

```
Excluding file: path/to/my-file.pem
Excluding directory: .aws
Override: keeping file visible: deploy-key.pem
```

Look for your file in the exclusion output to understand which pattern matched it.

### How do I check what is excluded?

Use the built-in exclusions command to inspect the current state:

```bash
nyia exclusions list      # Show excluded files and patterns
nyia exclusions status    # Check if exclusions are enabled and show config
```

### A file I need is being excluded

1. Check which pattern matched it (use `--verbose`).
2. Add an override to `.nyiakeeper/exclusions.conf`:
   ```
   !the-file-i-need.json
   ```
3. Run again -- the file will now be visible to the container.

### Exclusions seem stale or incorrect

Nyia Keeper caches exclusion scan results in `.nyiakeeper/.excluded-files.cache`. The cache is automatically invalidated when `exclusions.conf` changes or when the project file tree changes. If you suspect a stale cache, delete it:

```bash
rm .nyiakeeper/.excluded-files.cache
```

The next session will perform a fresh scan.
