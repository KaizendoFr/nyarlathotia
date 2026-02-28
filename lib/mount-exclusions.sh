#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 Nyia Keeper Contributors
# Nyia Keeper Mount Exclusions Library - KISS Design
# Simple Docker overlay mounts to exclude sensitive files

# Fallback print functions
if ! declare -f print_verbose >/dev/null 2>&1; then
    print_verbose() { [[ "${VERBOSE:-false}" == "true" ]] && echo "🔍 $*"; return 0; }
fi

# Source shared cache utilities
if ! declare -f is_exclusions_cache_valid >/dev/null 2>&1; then
    source "$(dirname "${BASH_SOURCE[0]}")/exclusions-cache-utils.sh" 2>/dev/null || true
fi

# Inline fallback if portable_sha256sum not yet defined (defensive for isolated sourcing)
if ! declare -f portable_sha256sum >/dev/null 2>&1; then
    portable_sha256sum() {
        if command -v sha256sum >/dev/null 2>&1; then sha256sum
        elif command -v shasum >/dev/null 2>&1; then shasum -a 256
        else openssl dgst -sha256 | sed 's/^.* //'; fi
    }
fi

# Platform-aware case sensitivity for file matching
# Optional argument: project path — used to detect NTFS mounts on WSL2
get_find_case_args() {
    local project_path="${1:-}"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS: case-insensitive filesystem
        echo "-iname"
    elif [[ -n "$project_path" ]] && is_ntfs_path "$project_path"; then
        # WSL2 NTFS mount: case-insensitive filesystem
        echo "-iname"
    else
        # Native Linux: case-sensitive filesystem
        echo "-name"
    fi
}

# Feature control
ENABLE_MOUNT_EXCLUSIONS=${ENABLE_MOUNT_EXCLUSIONS:-true}

# Create explanation files for excluded content
setup_explanation_files() {
    local excluded_file="/tmp/nyia-excluded-file.txt"
    local excluded_dir="/tmp/nyia-excluded-dir"
    
    # Create explanation file
    if [[ ! -f "$excluded_file" ]]; then
        cat > "$excluded_file" << 'EOF'
🔒 FILE EXCLUDED FOR SECURITY

This file was automatically excluded from the container mount because it may contain sensitive information (secrets, credentials, API keys, etc.).

This is a security feature to prevent accidental exposure of sensitive data to AI assistants.

To include this file:
- Use --disable-exclusions flag to disable all exclusions
- Or add an override in .nyiakeeper/exclusions.conf:
    !filename.yaml          (keeps all files named filename.yaml)
    !path/to/specific.yaml  (keeps only that exact path)

Nyia Keeper Mount Exclusions System
EOF
    fi

    # Create explanation directory
    if [[ ! -d "$excluded_dir" ]]; then
        mkdir -p "$excluded_dir"
        cat > "$excluded_dir/README.md" << 'EOF'
# 🔒 Directory Excluded for Security

This directory was automatically excluded from the container mount because it may contain sensitive information.

This is a security feature to prevent accidental exposure of sensitive data to AI assistants.

## To include this directory:
- Use `--disable-exclusions` flag to disable all exclusions
- Or add an override in `.nyiakeeper/exclusions.conf`:
    ```
    !dirname/          # keeps all directories named dirname
    !path/to/dirname/  # keeps only that exact path
    ```

---
*Nyia Keeper Mount Exclusions System*
EOF
    fi
}

# Get user-defined exclusion patterns from .nyiakeeper/exclusions.conf
get_user_exclusion_patterns() {
    local project_path="${1:-$(pwd)}"
    local exclusions_file="$project_path/.nyiakeeper/exclusions.conf"
    
    # If file doesn't exist, return nothing
    [[ -f "$exclusions_file" ]] || return 0
    
    # Read file line by line, skip comments and empty lines
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*! ]] && continue  # Override lines handled by get_user_override_patterns/dirs
        
        # Trim whitespace
        line=$(echo "$line" | xargs)
        [[ -z "$line" ]] && continue
        
        # If line ends with /, it's a directory pattern - skip it here
        [[ "$line" =~ /$ ]] && continue
        
        # Output the pattern
        echo "$line"
    done < "$exclusions_file"
}

# Get user-defined directory exclusion patterns
get_user_exclusion_dirs() {
    local project_path="${1:-$(pwd)}"
    local exclusions_file="$project_path/.nyiakeeper/exclusions.conf"
    
    # If file doesn't exist, return nothing
    [[ -f "$exclusions_file" ]] || return 0
    
    # Read file line by line, skip comments and empty lines
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*! ]] && continue  # Override lines handled by get_user_override_patterns/dirs
        
        # Trim whitespace
        line=$(echo "$line" | xargs)
        [[ -z "$line" ]] && continue
        
        # Only process lines ending with / (directory patterns)
        if [[ "$line" =~ /$ ]]; then
            # Remove trailing slash for consistency
            echo "${line%/}"
        fi
    done < "$exclusions_file"
}

# Get user-defined override patterns (files) from .nyiakeeper/exclusions.conf
# Lines starting with ! negate an exclusion — the file stays visible to the container.
# !filename      = basename match (matches any path ending in that name)
# !path/to/file  = exact relative path match
get_user_override_patterns() {
    local project_path="${1:-$(pwd)}"
    local exclusions_file="$project_path/.nyiakeeper/exclusions.conf"

    [[ -f "$exclusions_file" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ ! "$line" =~ ^[[:space:]]*! ]] && continue  # Only ! lines
        line=$(echo "$line" | xargs)
        line="${line#!}"  # Strip leading !
        [[ -z "$line" ]] && continue
        [[ "$line" =~ /$ ]] && continue  # Skip dir overrides (handled separately)
        echo "$line"
    done < "$exclusions_file"
}

# Get user-defined override patterns (directories) from .nyiakeeper/exclusions.conf
# Lines starting with ! and ending with / negate a directory exclusion.
# !dirname/       = basename match (any directory with that name)
# !path/to/dir/   = exact relative path match
get_user_override_dirs() {
    local project_path="${1:-$(pwd)}"
    local exclusions_file="$project_path/.nyiakeeper/exclusions.conf"

    [[ -f "$exclusions_file" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ ! "$line" =~ ^[[:space:]]*! ]] && continue  # Only ! lines
        line=$(echo "$line" | xargs)
        line="${line#!}"  # Strip leading !
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ /$ ]]; then
            echo "${line%/}"  # Remove trailing slash for consistency
        fi
    done < "$exclusions_file"
}

# Get common sensitive file patterns
get_exclusion_patterns() {
    # Core secrets (but preserve .nyiakeeper/creds/ directory - assistants need those)
    # Exclude .env files at project root (security risk) but allow in subdirs
    echo ".env *.key *.pem *.pfx *.p12 *.ppk *secret* *password* id_rsa id_dsa id_ecdsa id_ed25519"
    # Dangerous .env variants anywhere in project
    echo ".env.* env.local .env.production .env.staging .env.development .env.test .env.backup"
    # Generic credentials (but not .nyiakeeper/creds/ directory)
    echo "credentials.json credentials.yaml credentials.xml credentials.txt auth.json"
    
    # === INFRASTRUCTURE AS CODE ===
    # Terraform
    echo "*.tfstate *.tfstate.* *.tfvars *.tfvars.json terraform.tfvars.* override.tf *_override.tf .terraformrc terraform.rc *.tfplan crash.log"
    # OpenTofu (Terraform fork)
    echo "*.tofu *.tofustate *.tofuvars"
    # Pulumi
    echo "Pulumi.*.yaml Pulumi.*.yml"
    # CloudFormation
    echo "*-parameters.json *-parameters.yaml"
    
    # === KUBERNETES & CONTAINER ORCHESTRATION ===
    # Kubernetes
    echo "kubeconfig *.kubeconfig *-kubeconfig.yaml *.kubeconfig.yml config.yaml"
    # Rancher/RKE
    echo "*.rkestate cluster.rkestate rancher-cluster.yml cluster.yml"
    # K3s
    echo "k3s.yaml"
    # OpenShift
    echo "*.kubeconfig.json"
    
    # === CONFIGURATION MANAGEMENT ===
    # Ansible
    echo "*.vault vault_pass.txt .vault_pass ansible.cfg hosts.ini hosts inventory inventory.ini inventory.yml group_vars/*/vault host_vars/*/vault"
    # Chef
    echo "*.pem knife.rb client.rb validation.pem encrypted_data_bag_secret"
    # Puppet
    echo "*.eyaml hieradata/**/*.eyaml"
    # SaltStack
    echo "master.pem minion.pem *.sls"
    
    # === CONTAINER & BUILD TOOLS ===
    # Docker
    echo ".dockercfg .docker/config.json docker-compose.override.yml docker-compose.prod.yml docker-compose.secrets.yml"
    # Podman
    echo "containers.conf auth.json"
    # Buildah
    echo ".buildah"
    
    # === PACKAGE MANAGERS & LANGUAGES ===
    # Node.js/NPM
    echo ".npmrc .yarnrc .yarnrc.yml"
    # Python
    echo ".pypirc pip.conf setup.cfg tox.ini .python-version"
    # Ruby
    echo ".gem/credentials config/database.yml config/secrets.yml config/credentials.yml.enc config/master.key"
    # Java/Maven/Gradle
    echo "*.p8 *.jks *.keystore *.truststore settings.xml gradle.properties"
    # Go
    echo ".netrc go.sum"
    # Rust
    echo ".cargo/credentials .cargo/config.toml"
    # PHP
    echo "auth.json .env.*.php .env.php"
    # .NET
    echo "appsettings.*.json appsettings.Production.json appsettings.Staging.json nuget.config"
    
    # === CI/CD ===
    # Jenkins
    echo "credentials.xml jenkins.yaml jenkins.yml"
    # GitHub Actions
    echo ".github/workflows/secrets.yml"
    # GitLab CI
    echo ".gitlab-ci-local-variables.yml"
    # CircleCI
    echo ".circleci/config.local.yml"
    # Travis CI
    echo ".travis.yml"
    # ArgoCD
    echo "argocd-*.yaml"
    # Tekton
    echo "tekton-*.yaml"
    
    # === CLOUD PROVIDERS ===
    # AWS
    echo "credentials aws_access_key_id aws_secret_access_key *.pem"
    # Google Cloud
    echo "service-account*.json *-service-account.json gcloud.json application_default_credentials.json"
    # Azure
    echo "*.publishsettings *.azureProfile"
    # DigitalOcean
    echo "doctl.config"
    # Heroku
    echo ".netrc"
    
    # === MONITORING & LOGGING ===
    # Datadog
    echo "datadog.yaml datadog.yml"
    # New Relic
    echo "newrelic.yml newrelic.ini"
    # Prometheus
    echo "prometheus.yml"
    # Grafana
    echo "grafana.ini"
    
    # === MESSAGE QUEUES & DATABASES ===
    # Databases
    echo ".pgpass .my.cnf database.yml db.conf ormconfig.json ormconfig.js"
    # Redis
    echo "redis.conf"
    # RabbitMQ
    echo "rabbitmq.conf"
    # Kafka
    echo "kafka.properties"
    
    # === SECURITY TOOLS ===
    # Vault
    echo "*.hcl vault.json .vault-token"
    # Certificates
    echo "*.crt *.csr *.ca-bundle ca.crt server.crt client.crt *.cer *.der"
    # SSH
    echo "known_hosts authorized_keys"
    # VPN
    echo "*.ovpn wireguard.conf *.wg vpn.conf openvpn.conf"
    # Git-crypt
    echo ".git-crypt/**"
    
    # === WEB SERVERS ===
    # Nginx
    echo "nginx.conf sites-enabled/* sites-available/*"
    # Apache
    echo ".htaccess .htpasswd httpd.conf"
    
    # === GENERAL STATE FILES ===
    echo "*.state *.rkestate *.tfstate *.backup *.bak"
    
    # === LICENSES & MISC ===
    echo "*.license license.key license.txt"
    
    # === USER-DEFINED PATTERNS ===
    # Add patterns from .nyiakeeper/exclusions.conf
    get_user_exclusion_patterns "${1:-$(pwd)}"
}

# Get sensitive directory patterns  
get_exclusion_dirs() {
    # === CLOUD PROVIDERS === (but NOT .nyiakeeper/creds/ - assistants need that)
    echo ".aws .gcloud .azure .digitalocean .linode .vultr"
    
    # === KUBERNETES & ORCHESTRATION ===
    echo ".kube .minikube .k3s .k0s .kind .rancher .openshift .okd"
    
    # === CONTAINER TOOLS ===
    echo ".docker .podman .buildah .containerd"
    
    # === CONFIGURATION MANAGEMENT ===
    echo ".ansible .chef .puppet .salt .vagrant"
    
    # === INFRASTRUCTURE AS CODE ===
    echo ".terraform .terragrunt .pulumi .cdktf"
    
    # === CI/CD ===
    echo ".jenkins .circleci .buildkite .drone"

    # === PACKAGE MANAGERS ===
    echo ".npm .yarn .pnpm .cargo .gem .pypi .nuget .m2 .ivy2 .sbt .gradle"

    # === SECURITY & CERTIFICATES ===
    echo ".ssh .gnupg .gpg .git-crypt"

    # === MONITORING ===
    echo ".datadog .newrelic .dynatrace"

    # === CLOUD FUNCTIONS ===
    echo ".serverless .netlify .vercel .amplify"

    # === ORCHESTRATION TOOLS ===
    echo ".helm .kustomize .skaffold .tilt .garden"

    # === SERVICE MESH ===
    echo ".istio .linkerd .consul"

    # === DATABASES ===
    echo ".mysql .postgresql .mongodb .redis .elasticsearch"

    # === MESSAGE QUEUES ===
    echo ".kafka .rabbitmq .nats"

    # === DEVELOPMENT TOOLS ===
    echo ".vscode-server"

    # === BACKUP & STATE ===
    echo ".backup .bak"

    # === INFRASTRUCTURE ===
    echo ".packer .kitchen .inspec"
    
    # === USER-DEFINED DIRECTORIES ===
    # Add directory patterns from .nyiakeeper/exclusions.conf
    get_user_exclusion_dirs "${1:-$(pwd)}"
}

# Bare-word directory patterns that are only safe near the project root.
# These match common security dir names but also match legitimate package
# names inside dependency trees (e.g., npm "private", "consul", "state").
# Scanned at depth 2 only (project root + 1 level) to avoid false positives.
# Note: "private" and bare "consul" removed — too many false positives.
get_shallow_exclusion_dirs() {
    # Security & certificates (bare-word variants)
    echo "vault certs certificates ssl tls pki"
    # Backup & state (bare-word variants)
    echo "backups backup state states"
    # Generic secrets (bare-word variants)
    echo "secrets credentials keys"
}

# Slash-containing directory patterns that need find -path instead of -name.
# find -name only matches the final component, so ".github/secrets" never matches.
# These use -path "*/$pattern" to match correctly.
get_exclusion_path_patterns() {
    echo ".github/secrets .gitlab/secrets .devcontainer/secrets .codespaces/secrets"
}

# Global array for volume arguments
declare -a VOLUME_ARGS

# Global cache for nyiakeeper home (avoid calling get_nyiakeeper_home for every file)
_NYIA_HOME_CACHE=""

# Check if path is a Nyia Keeper system path that should not be excluded
is_nyiakeeper_system_path() {
    local file_path="$1"
    local project_path="$2"

    # Get Nyia Keeper home (cached to avoid repeated calls)
    if [[ -z "$_NYIA_HOME_CACHE" ]]; then
        # Use platform-aware function if available, otherwise fall back to default
        if declare -f get_nyiakeeper_home >/dev/null 2>&1; then
            _NYIA_HOME_CACHE="${NYIAKEEPER_HOME:-$(get_nyiakeeper_home)}"
        else
            _NYIA_HOME_CACHE="${NYIAKEEPER_HOME:-$HOME/.config/nyiakeeper}"
        fi
    fi
    local nyia_home="$_NYIA_HOME_CACHE"
    
    # If the project IS the Nyia Keeper home, check for system subdirs
    if [[ "$project_path" == "$nyia_home" ]] || [[ "$(realpath "$project_path")" == "$(realpath "$nyia_home")" ]]; then
        # Check if file is in protected Nyia Keeper directories
        case "$file_path" in
            claude/*|codex/*|gemini/*|opencode/*|data/*|config/*|bin/*|lib/*|docker/*)
                return 0  # True - this is a system path
                ;;
        esac
    fi
    
    return 1  # False - not a system path
}

# Check if path is under any excluded directory
# Usage: is_path_under_excluded_dir "rel/path/to/file" "${excluded_dirs[@]}"
is_path_under_excluded_dir() {
    local file_path="$1"
    shift
    local -a dirs=("$@")

    for dir in "${dirs[@]}"; do
        [[ -z "$dir" ]] && continue
        # Check if file_path starts with dir/
        if [[ "$file_path" == "$dir/"* ]]; then
            return 0  # True - file is under this directory
        fi
    done
    return 1  # False - not under any excluded directory
}

# Check if a directory exclusion pattern is a package-manager cache dir
# These get writable tmpfs mounts instead of read-only placeholders,
# so the container can use them (npm cache, cargo fetch, etc.) without
# leaking data to the host
is_package_manager_cache_pattern() {
    case "$1" in
        .npm|.yarn|.pnpm|.cargo|.gem|.pypi|.nuget|.m2|.ivy2|.sbt|.gradle)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# Check if a relative path is overridden by a user !pattern in exclusions.conf
# Two match modes:
# - Basename match: override has no slash → matches basename of rel_path
# - Exact path match: override contains slash → must match rel_path exactly
# Returns 0 (true) if overridden, 1 (false) otherwise
is_path_overridden() {
    local rel_path="$1"
    shift
    local -a overrides=("$@")
    local base
    base=$(basename "$rel_path")

    for override in "${overrides[@]}"; do
        [[ -z "$override" ]] && continue
        # Exact relative path match (override contains a slash)
        if [[ "$override" == */* ]] && [[ "$override" == "$rel_path" ]]; then
            return 0
        fi
        # Basename match (no slash in override = match any path with that name)
        if [[ "$override" != */* ]] && [[ "$override" == "$base" ]]; then
            return 0
        fi
    done
    return 1
}

# Main function: populate volume arguments array with exclusions
create_volume_args() {
    local project_path="$1"
    local container_path="${2:-/workspace}"
    
    print_verbose "create_volume_args called with: $project_path -> $container_path"
    print_verbose "ENABLE_MOUNT_EXCLUSIONS=$ENABLE_MOUNT_EXCLUSIONS"
    
    # Clear the global array
    VOLUME_ARGS=()
    
    # Check if disabled
    if [[ "$ENABLE_MOUNT_EXCLUSIONS" != "true" ]]; then
        VOLUME_ARGS=("-v" "$project_path:$container_path:rw")
        print_verbose "Mount exclusions disabled, returning simple mount"
        return 0
    fi
    
    # Setup explanation files
    setup_explanation_files
    
    # Start with base mount
    VOLUME_ARGS=("-v" "$project_path:$container_path:rw")
    print_verbose "Base mount added, checking for exclusions..."
    
    # Try to use cached exclusion lists if available
    local cache_file="$project_path/.nyiakeeper/.excluded-files.cache"
    local config_file="$project_path/.nyiakeeper/exclusions.conf"
    
    # Check if cache is valid using the correct validation function
    if declare -f is_exclusions_cache_valid >/dev/null 2>&1 && is_exclusions_cache_valid "$project_path"; then
        print_verbose "Cache is valid, using cached exclusions"

        # Load user override patterns for cache path too
        local -a cache_file_overrides=()
        local -a cache_dir_overrides=()
        while IFS= read -r ov; do [[ -n "$ov" ]] && cache_file_overrides+=("$ov"); done < <(get_user_override_patterns "$project_path")
        while IFS= read -r ov; do [[ -n "$ov" ]] && cache_dir_overrides+=("$ov"); done < <(get_user_override_dirs "$project_path")

        # Read cached lists
        local excluded_files_str=""
        local excluded_dirs_str=""
        while IFS='=' read -r key value; do
            case "$key" in
                excluded_files) excluded_files_str="$value" ;;
                excluded_dirs) excluded_dirs_str="$value" ;;
            esac
        done < "$cache_file"

        # First: parse and mount excluded directories (MUST be before files!)
        local -a excluded_dir_array=()
        if [[ -n "$excluded_dirs_str" ]]; then
            IFS=',' read -ra excluded_dir_array <<< "$excluded_dirs_str"
            for rel_path in "${excluded_dir_array[@]}"; do
                if [[ -n "$rel_path" ]]; then
                    # Skip if user has overridden this directory
                    if [[ ${#cache_dir_overrides[@]} -gt 0 ]] && is_path_overridden "$rel_path" "${cache_dir_overrides[@]}"; then
                        print_verbose "Override: keeping directory visible (cached): $rel_path"
                        continue
                    fi
                    local dir_basename
                    dir_basename=$(basename "$rel_path")
                    if is_package_manager_cache_pattern "$dir_basename"; then
                        VOLUME_ARGS+=("--mount" "type=tmpfs,destination=$container_path/$rel_path,tmpfs-mode=1777")
                        print_verbose "Excluding directory (cached, writable tmpfs): $rel_path"
                    else
                        VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-dir:$container_path/$rel_path:ro")
                        print_verbose "Excluding directory (cached): $rel_path"
                    fi
                fi
            done
        fi

        # Second: process files, but skip if under excluded directory
        if [[ -n "$excluded_files_str" ]]; then
            IFS=',' read -ra cached_files <<< "$excluded_files_str"
            for rel_path in "${cached_files[@]}"; do
                [[ -z "$rel_path" ]] && continue
                # Skip if file is under an excluded directory
                if is_path_under_excluded_dir "$rel_path" "${excluded_dir_array[@]}"; then
                    print_verbose "Skipping file (parent dir excluded): $rel_path"
                    continue
                fi
                # Skip if user has overridden this file
                if [[ ${#cache_file_overrides[@]} -gt 0 ]] && is_path_overridden "$rel_path" "${cache_file_overrides[@]}"; then
                    print_verbose "Override: keeping file visible (cached): $rel_path"
                    continue
                fi
                VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-file.txt:$container_path/$rel_path:ro")
                print_verbose "Excluding file (cached): $rel_path"
            done
        fi
    else
        print_verbose "Cache invalid or missing, scanning filesystem"
        # Cache invalid or doesn't exist - scan filesystem
        local max_depth="${EXCLUSION_MAX_DEPTH:-5}"

        # Load user override patterns (!pattern in exclusions.conf)
        local -a file_overrides=()
        local -a dir_overrides=()
        while IFS= read -r ov; do [[ -n "$ov" ]] && file_overrides+=("$ov"); done < <(get_user_override_patterns "$project_path")
        while IFS= read -r ov; do [[ -n "$ov" ]] && dir_overrides+=("$ov"); done < <(get_user_override_dirs "$project_path")

        # First: scan and collect excluded directories (MUST be before files!)
        local -a scanned_excluded_dirs=()
        local dir_patterns=$(get_exclusion_dirs "$project_path")
        print_verbose "Directory exclusion patterns: $dir_patterns"
        while IFS=' ' read -r pattern; do
            # Use find to search recursively
            while IFS= read -r -d '' match; do
                local rel_path="${match#$project_path/}"

                # Skip if this is a Nyia Keeper system directory
                if is_nyiakeeper_system_path "$rel_path" "$project_path"; then
                    print_verbose "Skipping Nyia Keeper system directory: $rel_path"
                    continue
                fi

                # Skip if user has overridden this directory
                if [[ ${#dir_overrides[@]} -gt 0 ]] && is_path_overridden "$rel_path" "${dir_overrides[@]}"; then
                    print_verbose "Override: keeping directory visible: $rel_path"
                    continue
                fi

                scanned_excluded_dirs+=("$rel_path")
                # Package-manager cache dirs get writable tmpfs (container can use them)
                # Security-sensitive dirs get read-only placeholder
                if is_package_manager_cache_pattern "$pattern"; then
                    VOLUME_ARGS+=("--mount" "type=tmpfs,destination=$container_path/$rel_path,tmpfs-mode=1777")
                    print_verbose "Excluding directory (writable tmpfs): $rel_path"
                else
                    VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-dir:$container_path/$rel_path:ro")
                    print_verbose "Excluding directory: $rel_path"
                fi
            done < <(find "$project_path" -maxdepth "$max_depth" \
                \( -name node_modules -o -name vendor -o -name site-packages \
                   -o -name __pycache__ -o -name .venv -o -name venv \
                   -o -name target \) -prune \
                -o -type d $(get_find_case_args "$project_path") "$pattern" -print0 2>/dev/null)
        done < <(echo "$dir_patterns" | tr ' ' '\n')

        # Shallow scan: bare-word patterns at depth 2 only (project root + 1 level)
        # These match common security dir names but also match legitimate packages,
        # so we limit depth to avoid false positives inside src/, lib/, etc.
        local shallow_patterns=$(get_shallow_exclusion_dirs)
        if [[ -n "$shallow_patterns" ]]; then
            print_verbose "Shallow exclusion patterns (depth 2): $shallow_patterns"
            while IFS=' ' read -r pattern; do
                while IFS= read -r -d '' match; do
                    local rel_path="${match#$project_path/}"
                    if is_nyiakeeper_system_path "$rel_path" "$project_path"; then
                        print_verbose "Skipping Nyia Keeper system directory: $rel_path"
                        continue
                    fi
                    if [[ ${#dir_overrides[@]} -gt 0 ]] && is_path_overridden "$rel_path" "${dir_overrides[@]}"; then
                        print_verbose "Override: keeping directory visible: $rel_path"
                        continue
                    fi
                    scanned_excluded_dirs+=("$rel_path")
                    VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-dir:$container_path/$rel_path:ro")
                    print_verbose "Excluding directory (shallow): $rel_path"
                done < <(find "$project_path" -maxdepth 2 -type d $(get_find_case_args "$project_path") "$pattern" -print0 2>/dev/null)
            done < <(echo "$shallow_patterns" | tr ' ' '\n')
        fi

        # Path-based scan: slash-containing patterns that need find -path
        # find -name only matches the final component, so ".github/secrets" needs -path
        local path_patterns=$(get_exclusion_path_patterns)
        if [[ -n "$path_patterns" ]]; then
            print_verbose "Path-based exclusion patterns: $path_patterns"
            while IFS=' ' read -r pattern; do
                while IFS= read -r -d '' match; do
                    local rel_path="${match#$project_path/}"
                    if is_nyiakeeper_system_path "$rel_path" "$project_path"; then
                        continue
                    fi
                    if [[ ${#dir_overrides[@]} -gt 0 ]] && is_path_overridden "$rel_path" "${dir_overrides[@]}"; then
                        print_verbose "Override: keeping directory visible: $rel_path"
                        continue
                    fi
                    scanned_excluded_dirs+=("$rel_path")
                    VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-dir:$container_path/$rel_path:ro")
                    print_verbose "Excluding directory (path): $rel_path"
                done < <(find "$project_path" -maxdepth "$max_depth" -type d -path "*/$pattern" -print0 2>/dev/null)
            done < <(echo "$path_patterns" | tr ' ' '\n')
        fi

        # Second: scan files, skip if under excluded directory
        local patterns=$(get_exclusion_patterns "$project_path")
        print_verbose "Exclusion patterns: $patterns"
        while IFS=' ' read -r pattern; do
            # Use find to search recursively
            while IFS= read -r -d '' match; do
                local rel_path="${match#$project_path/}"

                # Skip if this is a Nyia Keeper system file
                if is_nyiakeeper_system_path "$rel_path" "$project_path"; then
                    print_verbose "Skipping Nyia Keeper system file: $rel_path"
                    continue
                fi

                # Skip if file is under an excluded directory
                if is_path_under_excluded_dir "$rel_path" "${scanned_excluded_dirs[@]}"; then
                    print_verbose "Skipping file (parent dir excluded): $rel_path"
                    continue
                fi

                # Skip if user has overridden this file
                if [[ ${#file_overrides[@]} -gt 0 ]] && is_path_overridden "$rel_path" "${file_overrides[@]}"; then
                    print_verbose "Override: keeping file visible: $rel_path"
                    continue
                fi

                VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-file.txt:$container_path/$rel_path:ro")
                print_verbose "Excluding file: $rel_path"
            done < <(find "$project_path" -maxdepth "$max_depth" \
                \( -name node_modules -o -name vendor -o -name site-packages \
                   -o -name __pycache__ -o -name .venv -o -name venv \
                   -o -name target \) -prune \
                -o -type f $(get_find_case_args "$project_path") "$pattern" -print0 2>/dev/null)
        done < <(echo "$patterns" | tr ' ' '\n')
        
        # KISS: Write cache for next time (simple approach)
        if declare -f write_exclusions_cache >/dev/null 2>&1; then
            # Build simple arrays from VOLUME_ARGS for caching
            declare -gA excluded_files excluded_dirs system_files system_dirs
            excluded_files=() excluded_dirs=() system_files=() system_dirs=()
            
            # Extract excluded files/dirs from volume arguments
            local i=0
            while [[ $i -lt ${#VOLUME_ARGS[@]} ]]; do
                if [[ "${VOLUME_ARGS[$i]}" == "-v" ]]; then
                    local mount_spec="${VOLUME_ARGS[$((i+1))]}"
                    # Parse: /tmp/nyia-excluded-file.txt:/workspace/path:ro
                    if [[ "$mount_spec" == "/tmp/nyia-excluded-file.txt:$container_path/"* ]]; then
                        local file_path="${mount_spec#*/tmp/nyia-excluded-file.txt:$container_path/}"
                        file_path="${file_path%:ro}"
                        [[ -n "$file_path" ]] && excluded_files["$file_path"]=1
                    elif [[ "$mount_spec" == "/tmp/nyia-excluded-dir:$container_path/"* ]]; then
                        local dir_path="${mount_spec#*/tmp/nyia-excluded-dir:$container_path/}"
                        dir_path="${dir_path%:ro}"
                        [[ -n "$dir_path" ]] && excluded_dirs["$dir_path"]=1
                    fi
                    ((i+=2))
                elif [[ "${VOLUME_ARGS[$i]}" == "--mount" ]]; then
                    local mount_spec="${VOLUME_ARGS[$((i+1))]}"
                    # Parse: type=tmpfs,destination=/workspace/.pnpm,tmpfs-mode=1777
                    if [[ "$mount_spec" == *"destination=$container_path/"* ]]; then
                        local dir_path="${mount_spec#*destination=$container_path/}"
                        dir_path="${dir_path%%,*}"  # Strip trailing options
                        [[ -n "$dir_path" ]] && excluded_dirs["$dir_path"]=1
                    fi
                    ((i+=2))
                else
                    ((i++))
                fi
            done
            
            # Write cache with results
            write_exclusions_cache "$project_path"
            print_verbose "Assistant exclusions cache updated"
        fi
    fi
}

# Backward compatibility wrapper
create_filtered_volume_args() {
    create_volume_args "$@"
}

# === WORKSPACE MODE SUPPORT ===

# Appends volume mounts for a repo WITHOUT clearing VOLUME_ARGS
# Unlike create_volume_args(), this ADDS to existing array
# Usage: append_repo_volume_args "$repo_path" "$container_base_path"
append_repo_volume_args() {
    local repo_path="$1"
    local container_base="$2"  # e.g., /project/ws-{hash}/repos

    # Use hash suffix for collision prevention (Issue #10 - same basename repos)
    local repo_hash
    repo_hash=$(echo -n "$repo_path" | portable_sha256sum | cut -c1-8)
    local repo_name
    repo_name=$(basename "$repo_path")
    local container_subpath="${container_base}/${repo_name}-${repo_hash}"

    print_verbose "Appending repo mount: $repo_path -> $container_subpath"

    # Add base mount for this repo (does NOT clear VOLUME_ARGS)
    VOLUME_ARGS+=("-v" "$repo_path:$container_subpath:rw")

    # Apply exclusions from this repo's .nyiakeeper/exclusions.conf if it exists
    if [[ -f "$repo_path/.nyiakeeper/exclusions.conf" ]]; then
        print_verbose "Applying exclusions from: $repo_path/.nyiakeeper/exclusions.conf"

        # Get exclusion patterns for this repo
        local patterns
        patterns=$(get_exclusion_patterns "$repo_path")

        if [[ -n "$patterns" ]]; then
            local max_depth="${EXCLUSION_MAX_DEPTH:-5}"

            while IFS= read -r pattern; do
                [[ -z "$pattern" ]] && continue

                # Find matching files/directories
                while IFS= read -r -d '' match; do
                    local rel_path="${match#$repo_path/}"

                    # Skip Nyia Keeper system paths
                    if is_nyiakeeper_system_path "$rel_path" "$repo_path" 2>/dev/null; then
                        continue
                    fi

                    if [[ -d "$match" ]]; then
                        VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-dir:$container_subpath/$rel_path:ro")
                        print_verbose "Excluding directory in repo: $rel_path"
                    else
                        VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-file.txt:$container_subpath/$rel_path:ro")
                        print_verbose "Excluding file in repo: $rel_path"
                    fi
                done < <(find "$repo_path" -maxdepth "$max_depth" \
                    \( -name node_modules -o -name vendor -o -name site-packages \
                       -o -name __pycache__ -o -name .venv -o -name venv \
                       -o -name target \) -prune \
                    -o -name "$pattern" -print0 2>/dev/null)
            done <<< "$patterns"
        fi
    fi

    # Always apply built-in security exclusions to repos
    local builtin_patterns=".env .env.* *.pem *.key credentials.json"
    for pattern in $builtin_patterns; do
        while IFS= read -r -d '' match; do
            local rel_path="${match#$repo_path/}"
            if [[ -f "$match" ]]; then
                VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-file.txt:$container_subpath/$rel_path:ro")
                print_verbose "Excluding sensitive file in repo: $rel_path"
            fi
        done < <(find "$repo_path" -maxdepth 3 \
            \( -name node_modules -o -name vendor -o -name site-packages \
               -o -name __pycache__ -o -name .venv -o -name venv \
               -o -name target \) -prune \
            -o -name "$pattern" -print0 2>/dev/null)
    done
}