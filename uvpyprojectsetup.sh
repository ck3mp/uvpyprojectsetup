#!/bin/bash

# Strict mode settings
set -euo pipefail
IFS=$'\n\t'

# ================================================================================
# CONSTANTS AND VERSION INFO
# ================================================================================
readonly VERSION="1.0.0"
readonly REQUIRED_TOOLS=("curl" "jq" "uv" "git")

# ================================================================================
# CONFIGURATION
# ================================================================================
platform="devops"
github_mode="personal"
project_name=""
autocommit=""
org_url=""
project_id=""
org_name=""


# ================================================================================
# HELP AND DOCUMENTATION
# ================================================================================
show_help() {
    cat << EOF
Usage: $(basename "$0") [--devops|--github-personal|--github-org] [options]

Platform (pick one):
    --devops               Use Azure DevOps (default)
    --github-personal      Use GitHub Personal
    --github-org           Use GitHub Organisation

Required:
    --project-name         Project name (lowercase || die)

DevOps options:
    --org-url              DevOps org URL or set AZURE_REPOCREATE_ORG_URL
    --project-id           DevOps project ID or set AZURE_REPOCREATE_PROJECT_ID

GitHub Org options:
    --org                  GitHub org name or set GITHUB_REPOCREATE_ORG

Optional:
    --autocommit           YOLO push to main after setup
    -v, --version          Show version
    -h, --help             Show this help
EOF
}

# ================================================================================
# SECURITY FUNCTIONS
# ================================================================================
validate_token() {
    local platform="$1"
    local token_var
    local token_value
    
    case "$platform" in
        devops)
            token_var="AZURE_REPOCREATE_EXT_PAT"
            token_value="${AZURE_REPOCREATE_EXT_PAT:-}"
            ;;
        github)
            token_var="GITHUB_REPOCREATE_TOKEN"
            token_value="${GITHUB_REPOCREATE_TOKEN:-}"
            ;;
        *)
            die "Invalid platform: $platform"
            ;;
    esac
    
    if [[ -z "$token_value" ]]; then
        die "Missing $token_var. Set this shit or GTFO."
    fi
    
    if [[ "$platform" == "devops" && ! "$token_value" =~ ^[a-zA-Z0-9]+$ ]]; then
        die "Invalid Azure PAT format. Fix your token."
    elif [[ "$platform" == "github" && ! "$token_value" =~ ^gh[ps]_[a-zA-Z0-9]+$ ]]; then
        die "Invalid GitHub token format. Get a proper token."
    fi
}

# ================================================================================
# ERROR HANDLING
# ================================================================================
die() {
    echo "💀 Error: $1" >&2
    exit 1
}

log() {
    local level="$1"
    shift
    printf "[%s] %s\n" "$level" "$*" >&2
}

# ================================================================================
# API INTERACTION
# ================================================================================
make_api_call() {
    local method="$1"
    local url="$2"
    local data="${3:-}"
    local platform="$4"
    local -a headers=()
    local response
    local auth
    
    case "$platform" in
        devops)
            auth=$(echo -n ":${AZURE_REPOCREATE_EXT_PAT}" | base64 | tr -d '\n')
            headers+=(-H "Authorization: Basic ${auth}")
            headers+=(-H "Content-Type: application/json")
            headers+=("--http1.1")
            ;;
        github)
            headers+=(-H "Authorization: token $GITHUB_REPOCREATE_TOKEN")
            headers+=(-H "Accept: application/vnd.github.v3+json")
            ;;
    esac
    
    if [[ -n "$data" ]]; then
        response=$(curl -sS -L -X "$method" "${headers[@]}" -d "$data" "$url" 2>&1)
    else
        response=$(curl -sS -L -X "$method" "${headers[@]}" "$url" 2>&1)
    fi
    
    case "$response" in
        *"401"*) die "Authentication failed. Check your PAT." ;;
        *"403"*) die "Permission denied. Missing required scopes." ;;
        *"404"*) echo "{}" && return 0 ;;
        *"400"*) die "Bad request: $response" ;;
    esac
    
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        die "Invalid JSON response: $response"
    fi
    
    echo "$response"
}

# ================================================================================
# VALIDATION FUNCTIONS
# ================================================================================
check_repo_exists() {
    local project_name="$1"
    local response
    local url
    
    case "$platform" in
        devops)
            url="${org_url}/_apis/git/repositories/${project_name}?api-version=6.0"
            ;;
        github)
            if [[ "$github_mode" == "org" ]]; then
                url="https://api.github.com/repos/${org_name}/${project_name}"
            else
                url="https://api.github.com/repos/${project_name}"
            fi
            ;;
    esac
    
    response=$(make_api_call "GET" "$url" "" "$platform")
    
    if jq -e '.id' <<< "$response" >/dev/null 2>&1; then
        die "Repo '$project_name' already exists. Pick something else."
    fi
}

validate_project_name() {
    local name="$1"
    local pattern='^[a-z0-9][a-z0-9_-]{0,62}[a-z0-9]$'
    
    if [[ ! "$name" =~ $pattern ]]; then
        die "Invalid project name. Must match: $pattern"
    fi
    
    if [[ -d "$name" ]]; then
        die "Directory '$name' exists. Clean up your mess first."
    fi
}

# ================================================================================
# ARGUMENT PARSING
# ================================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --devops)
                platform="devops"
                ;;
            --github-personal|--github-org)
                platform="github"
                github_mode=${1#--github-}
                ;;
            --project-name)
                [[ -z "${2:-}" ]] && die "Missing project name"
                project_name="$2"
                shift
                ;;
            --org-url)
                [[ -z "${2:-}" ]] && die "Missing org URL"
                org_url="$2"
                shift
                ;;
            --project-id)
                [[ -z "${2:-}" ]] && die "Missing project ID"
                project_id="$2"
                shift
                ;;
            --org)
                [[ -z "${2:-}" ]] && die "Missing org name"
                org_name="$2"
                shift
                ;;
            --autocommit)
                autocommit=1
                ;;
            -v|--version)
                echo "$VERSION"
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
        shift
    done
}
# ================================================================================
# MAIN EXECUTION
# ================================================================================
main() {
    parse_args "$@"
    
    for tool in $REQUIRED_TOOLS; do
        command -v "$tool" >/dev/null 2>&1 || die "Missing required tool: $tool"
    done

    validate_token "$platform"
    validate_project_name "$project_name"
    check_repo_exists "$project_name"

    local repo_data response ssh_url web_url

    case "$platform" in
        devops)
            repo_data="{\"name\": \"${project_name}\", \"project\": {\"id\": \"${project_id}\"}}"
            response=$(make_api_call "POST" "${org_url}/_apis/git/repositories?api-version=6.0" "$repo_data" "devops")
            ;;
        github)
            repo_data="{\"name\":\"${project_name}\", \"private\":true}"
            if [[ "$github_mode" == "org" ]]; then
                response=$(make_api_call "POST" "https://api.github.com/orgs/${org_name}/repos" "$repo_data" "github")
            else
                response=$(make_api_call "POST" "https://api.github.com/user/repos" "$repo_data" "github")
            fi
            ;;
    esac

    ssh_url=$(jq -r '.sshUrl // .ssh_url' <<< "$response")
    web_url=$(jq -r '.webUrl // .html_url' <<< "$response")
    
    [[ "$ssh_url" == "null" || "$web_url" == "null" ]] && die "Failed to extract repo URLs"
    
    if ! uv init "$project_name"; then
        die "uv init failed"
    fi
    
    cd "$project_name" || die "Failed to cd into project directory"
    git branch -M main || die "Failed to rename branch to main"
    git remote add origin "$ssh_url" || die "Failed to add git remote"
    
    if [[ -n "$autocommit" ]]; then
        git add . || die "Git add failed"
        git commit -m "Initial commit: Project setup with uv" || die "Git commit failed"
        git push -u origin main || die "Git push failed"
    fi
    
    log "INFO" "🎉 ${project_name} setup complete!"
    log "INFO" "🔗 SSH URL: $ssh_url"
    log "INFO" "🌐 Web URL: $web_url"
}

main "$@"