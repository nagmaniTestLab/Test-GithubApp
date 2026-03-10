#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./create_github_repo.sh <repo-name> [--description "text"] [--private|--public] [--org <org-name>]

Required:
  <repo-name>                  Name of the GitHub repository to create.

Optional:
  --description "text"         Repository description.
  --private                    Create as private repository.
  --public                     Create as public repository (default).
  --org <org-name>             Create repository under an organization.
  --help                       Show this help text.

Environment:
  GITHUB_APP_ID                GitHub App ID.
  GITHUB_APP_INSTALLATION_ID   GitHub App installation ID.
  GITHUB_APP_PRIVATE_KEY_PATH  Path to GitHub App private key PEM file.

Examples:
  ./create_github_repo.sh demo-repo --description "Demo repo" --private
  ./create_github_repo.sh team-repo --org my-org --public
EOF
}

base64url_encode() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

create_app_jwt() {
  local now exp header payload unsigned signature

  now=$(date +%s)
  exp=$((now + 540))
  header='{"alg":"RS256","typ":"JWT"}'
  payload=$(jq -nc --argjson iat "$now" --argjson exp "$exp" --arg iss "$GITHUB_APP_ID" '{iat: $iat, exp: $exp, iss: $iss}')

  unsigned="$(printf '%s' "$header" | base64url_encode).$(printf '%s' "$payload" | base64url_encode)"
  signature=$(printf '%s' "$unsigned" | openssl dgst -binary -sha256 -sign "$GITHUB_APP_PRIVATE_KEY_PATH" | base64url_encode)

  printf '%s.%s' "$unsigned" "$signature"
}

request_installation_token() {
  local app_jwt token_response token_status token_body token_value

  app_jwt=$(create_app_jwt)
  token_response=$(curl -sS -w '\n%{http_code}' -X POST "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${app_jwt}" \
    -H "X-GitHub-Api-Version: 2022-11-28")

  token_status=$(echo "$token_response" | tail -n1)
  token_body=$(echo "$token_response" | sed '$d')

  if [[ "$token_status" != "201" ]]; then
    echo "Failed to create installation token (HTTP ${token_status}): $(echo "$token_body" | jq -r '.message // "Unknown error"')" >&2
    exit 1
  fi

  token_value=$(echo "$token_body" | jq -r '.token // empty')
  if [[ -z "$token_value" ]]; then
    echo "Failed to read installation token from GitHub response." >&2
    exit 1
  fi

  printf '%s' "$token_value"
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" || $# -eq 0 ]]; then
  usage
  exit 0
fi

REPO_NAME="$1"
shift

DESCRIPTION=""
VISIBILITY="public"
ORG_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --description)
      if [[ $# -lt 2 ]]; then
        echo "Error: --description requires a value." >&2
        exit 1
      fi
      DESCRIPTION="$2"
      shift 2
      ;;
    --private)
      VISIBILITY="private"
      shift
      ;;
    --public)
      VISIBILITY="public"
      shift
      ;;
    --org)
      if [[ $# -lt 2 ]]; then
        echo "Error: --org requires a value." >&2
        exit 1
      fi
      ORG_NAME="$2"
      shift 2
      ;;
    *)
      echo "Error: Unknown argument '$1'" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${GITHUB_APP_ID:-}" ]]; then
  echo "Error: GITHUB_APP_ID is not set." >&2
  exit 1
fi

if [[ -z "${GITHUB_APP_INSTALLATION_ID:-}" ]]; then
  echo "Error: GITHUB_APP_INSTALLATION_ID is not set." >&2
  exit 1
fi

if [[ -z "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]]; then
  echo "Error: GITHUB_APP_PRIVATE_KEY_PATH is not set." >&2
  exit 1
fi

if [[ ! -f "$GITHUB_APP_PRIVATE_KEY_PATH" ]]; then
  echo "Error: Private key file not found at '$GITHUB_APP_PRIVATE_KEY_PATH'." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required but not installed." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is required but not installed." >&2
  exit 1
fi

private_flag="false"
if [[ "$VISIBILITY" == "private" ]]; then
  private_flag="true"
fi

payload=$(jq -n \
  --arg name "$REPO_NAME" \
  --arg description "$DESCRIPTION" \
  --argjson private "$private_flag" \
  '{name: $name, description: $description, private: $private}')

api_url="https://api.github.com/user/repos"
if [[ -n "$ORG_NAME" ]]; then
  api_url="https://api.github.com/orgs/${ORG_NAME}/repos"
fi

installation_token=$(request_installation_token)

response=$(curl -sS -w '\n%{http_code}' -X POST "$api_url" \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${installation_token}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -d "$payload")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" == "201" ]]; then
  repo_url=$(echo "$body" | jq -r '.html_url')
  echo "Repository created successfully: ${repo_url}"
  exit 0
fi

message=$(echo "$body" | jq -r '.message // "Unknown error"')
echo "Failed to create repository (HTTP ${http_code}): ${message}" >&2

errors=$(echo "$body" | jq -r '.errors[]?.message' || true)
if [[ -n "$errors" ]]; then
  echo "Details:" >&2
  echo "$errors" >&2
fi

exit 1
