#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR Proprietary
# Copyright (c) 2024 NyarlathotIA Contributors
# NyarlathotIA Mount Exclusions Library - KISS Design
# Simple Docker overlay mounts to exclude sensitive files

# Fallback print functions
if ! declare -f print_verbose >/dev/null 2>&1; then
    print_verbose() { [[ "${VERBOSE:-false}" == "true" ]] && echo "🔍 $*"; }
fi

# Source shared cache utilities
if ! declare -f is_exclusions_cache_valid >/dev/null 2>&1; then
    source "$(dirname "${BASH_SOURCE[0]}")/exclusions-cache-utils.sh" 2>/dev/null || true
fi

# Platform-aware case sensitivity for file matching
get_find_case_args() {
    # On macOS with case-insensitive filesystem, provide both case-sensitive and insensitive options
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # For macOS, we'll use both -name and -iname to catch case variations
        echo "-iname"
    else
        # Linux filesystems are typically case-sensitive
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
- Use --disable-exclusions flag
- Or add an override in .nyarlathotia/exclusions.conf

NyarlathotIA Mount Exclusions System
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
- Use `--disable-exclusions` flag
- Or add an override in `.nyarlathotia/exclusions.conf`

---
*NyarlathotIA Mount Exclusions System*
EOF
    fi
}

# Get user-defined exclusion patterns from .nyarlathotia/exclusions.conf
get_user_exclusion_patterns() {
    local project_path="${1:-$(pwd)}"
    local exclusions_file="$project_path/.nyarlathotia/exclusions.conf"
    
    # If file doesn't exist, return nothing
    [[ -f "$exclusions_file" ]] || return 0
    
    # Read file line by line, skip comments and empty lines
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*! ]] && continue  # Skip override attempts for now
        
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
    local exclusions_file="$project_path/.nyarlathotia/exclusions.conf"
    
    # If file doesn't exist, return nothing
    [[ -f "$exclusions_file" ]] || return 0
    
    # Read file line by line, skip comments and empty lines
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*! ]] && continue  # Skip override attempts for now
        
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

# Get common sensitive file patterns
get_exclusion_patterns() {
    # Core secrets (but preserve .nyarlathotia/creds/ directory - assistants need those)
    # Exclude .env files at project root (security risk) but allow in subdirs
    echo ".env *.key *.pem *.pfx *.p12 *.ppk *secret* *password* id_rsa id_dsa id_ecdsa id_ed25519"
    # Dangerous .env variants anywhere in project
    echo ".env.* env.local .env.production .env.staging .env.development .env.test .env.backup"
    # Generic credentials (but not .nyarlathotia/creds/ directory)
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
    # Add patterns from .nyarlathotia/exclusions.conf
    get_user_exclusion_patterns "${1:-$(pwd)}"
}

# Get sensitive directory patterns  
get_exclusion_dirs() {
    # === CLOUD PROVIDERS === (but NOT .nyarlathotia/creds/ - assistants need that)
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
    echo ".jenkins .circleci .github/secrets .gitlab/secrets .buildkite .drone"
    
    # === PACKAGE MANAGERS ===
    echo ".npm .yarn .pnpm .cargo .gem .pypi .nuget .m2 .ivy2 .sbt .gradle"
    
    # === SECURITY & CERTIFICATES ===
    echo ".ssh .gnupg .gpg .git-crypt vault consul certs certificates ssl tls pki"
    
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
    echo ".vscode-server .devcontainer/secrets .codespaces/secrets"
    
    # === BACKUP & STATE ===
    echo "backups backup state states .backup .bak"
    
    # === GENERIC SECRETS ===
    echo "secrets credentials private keys"
    
    # === INFRASTRUCTURE ===
    echo ".packer .kitchen .inspec"
    
    # === USER-DEFINED DIRECTORIES ===
    # Add directory patterns from .nyarlathotia/exclusions.conf
    get_user_exclusion_dirs "${1:-$(pwd)}"
}

# Global array for volume arguments
declare -a VOLUME_ARGS

# Check if path is a NyarlathotIA system path that should not be excluded
is_nyarlathotia_system_path() {
    local file_path="$1"
    local project_path="$2"
    
    # Get NyarlathotIA home (could be the project path itself)
    # Use platform-aware function if available, otherwise fall back to default
    if declare -f get_nyarlathotia_home >/dev/null 2>&1; then
        local nyia_home="${NYARLATHOTIA_HOME:-$(get_nyarlathotia_home)}"
    else
        local nyia_home="${NYARLATHOTIA_HOME:-$HOME/.config/nyarlathotia}"
    fi
    
    # If the project IS the NyarlathotIA home, check for system subdirs
    if [[ "$project_path" == "$nyia_home" ]] || [[ "$(realpath "$project_path")" == "$(realpath "$nyia_home")" ]]; then
        # Check if file is in protected NyarlathotIA directories
        case "$file_path" in
            claude/*|codex/*|gemini/*|opencode/*|data/*|config/*|bin/*|lib/*|docker/*)
                return 0  # True - this is a system path
                ;;
        esac
    fi
    
    return 1  # False - not a system path
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
    local cache_file="$project_path/.nyarlathotia/.excluded-files.cache"
    local config_file="$project_path/.nyarlathotia/exclusions.conf"
    
    # Check if cache is valid using the correct validation function
    if declare -f is_exclusions_cache_valid >/dev/null 2>&1 && is_exclusions_cache_valid "$project_path"; then
        print_verbose "Cache is valid, using cached exclusions"
        # Read cached lists
        local excluded_files_str=""
        local excluded_dirs_str=""
        while IFS='=' read -r key value; do
            case "$key" in
                excluded_files) excluded_files_str="$value" ;;
                excluded_dirs) excluded_dirs_str="$value" ;;
            esac
        done < "$cache_file"
        
        # Process cached excluded files
        if [[ -n "$excluded_files_str" ]]; then
            IFS=',' read -ra cached_files <<< "$excluded_files_str"
            for rel_path in "${cached_files[@]}"; do
                [[ -n "$rel_path" ]] && VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-file.txt:$container_path/$rel_path:ro")
                print_verbose "Excluding file (cached): $rel_path"
            done
        fi
        
        # Process cached excluded directories
        if [[ -n "$excluded_dirs_str" ]]; then
            IFS=',' read -ra cached_dirs <<< "$excluded_dirs_str"
            for rel_path in "${cached_dirs[@]}"; do
                [[ -n "$rel_path" ]] && VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-dir:$container_path/$rel_path:ro")
                print_verbose "Excluding directory (cached): $rel_path"
            done
        fi
    else
        print_verbose "Cache invalid or missing, scanning filesystem"
        # Cache invalid or doesn't exist - scan filesystem
        local max_depth="${EXCLUSION_MAX_DEPTH:-5}"
        # Read patterns without shell globbing expansion
        local patterns=$(get_exclusion_patterns "$project_path")
        print_verbose "Exclusion patterns: $patterns"
        while IFS=' ' read -r pattern; do
            # Use find to search recursively
            while IFS= read -r -d '' match; do
                local rel_path="${match#$project_path/}"
                
                # Skip if this is a NyarlathotIA system file
                if is_nyarlathotia_system_path "$rel_path" "$project_path"; then
                    print_verbose "Skipping NyarlathotIA system file: $rel_path"
                    continue
                fi
                
                VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-file.txt:$container_path/$rel_path:ro")
                print_verbose "Excluding file: $rel_path"
            done < <(find "$project_path" -maxdepth "$max_depth" -type f $(get_find_case_args) "$pattern" -print0 2>/dev/null)
        done < <(echo "$patterns" | tr ' ' '\n')
        
        # Process directory patterns using find for recursive search
        local dir_patterns=$(get_exclusion_dirs "$project_path")
        print_verbose "Directory exclusion patterns: $dir_patterns"
        while IFS=' ' read -r pattern; do
            # Use find to search recursively
            while IFS= read -r -d '' match; do
                local rel_path="${match#$project_path/}"
                
                # Skip if this is a NyarlathotIA system directory
                if is_nyarlathotia_system_path "$rel_path" "$project_path"; then
                    print_verbose "Skipping NyarlathotIA system directory: $rel_path"
                    continue
                fi
                
                VOLUME_ARGS+=("-v" "/tmp/nyia-excluded-dir:$container_path/$rel_path:ro")
                print_verbose "Excluding directory: $rel_path"
            done < <(find "$project_path" -maxdepth "$max_depth" -type d $(get_find_case_args) "$pattern" -print0 2>/dev/null)
        done < <(echo "$dir_patterns" | tr ' ' '\n')
        
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