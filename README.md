# Test-GithubApp

## Create a GitHub repository

Use the script below to create a new GitHub repository through the GitHub API:

```bash
./create_github_repo.sh <repo-name> [--description "text"] [--private|--public] [--org <org-name>]
```

Prerequisites:

- `curl`
- `jq`
- `openssl`
- GitHub App with repository creation permissions
- `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY_PATH` environment variables

Example:

```bash
export GITHUB_APP_ID=123456
export GITHUB_APP_INSTALLATION_ID=78901234
export GITHUB_APP_PRIVATE_KEY_PATH="$HOME/.keys/my-github-app.private-key.pem"

./create_github_repo.sh demo-repo --description "Demo repo" --private
```

## Run manually with GitHub Actions

A manual workflow is available at `.github/workflows/create-repo.yml`.

Set these repository secrets before running it:

- `GITHUB_APP_ID`
- `GITHUB_APP_INSTALLATION_ID`
- `GITHUB_APP_PRIVATE_KEY` (full PEM content)

Then run it from the Actions tab:

1. Open **Create Repo (Manual)** workflow.
2. Click **Run workflow**.
3. Provide `repo_name`, optional `description`, `visibility`, and optional `org_name`.
