# Repository Creation & Project Setup Script

A battle-tested script for automating repo creation and project setup across Azure DevOps and GitHub. Handles all the tedious bullshit of setting up new Python projects with proper git initialization.

## Prerequisites

These tools better be in your PATH or nothing's gonna work:
- `curl`: HTTP calls that don't suck
- `jq`: JSON parsing that isn't regex hell
- `uv`: Python project bootstrapping that doesn't make you want to die
- `git`: Version control (duh)

## Authentication

### Azure DevOps
Set `AZURE_REPOCREATE_EXT_PAT` in your env with a PAT that has these permissions:
- Code (read, write, manage)
- Project and Team (read)

### GitHub
Set `GITHUB_REPOCREATE_TOKEN` with a token that isn't completely neutered. Needs:
- `repo` scope for private repos
- `public_repo` scope if you're doing open source shit

Don't even try using expired or malformed tokens. Script will tell you to GTFO.

## Usage

### Basic Syntax
```bash
./pyprojectsetup.sh [--devops|--github-personal|--github-org] [options]
```

### Required Args
- `--project-name`: Lowercase repo name. Don't be creative - stick to `^[a-z0-9][a-z0-9_-]{0,62}[a-z0-9]$`

### Platform-Specific Args

#### Azure DevOps
```bash
./pyprojectsetup.sh --devops \
    --project-name your-repo \
    --org-url https://dev.azure.com/your-org \
    --project-id your-project-guid
```

Skip `--org-url` by setting `AZURE_REPOCREATE_ORG_URL`
Skip `--project-id` by setting `AZURE_REPOCREATE_PROJECT_ID`

#### GitHub Personal
```bash
./pyprojectsetup.sh --github-personal \
    --project-name your-repo
```

#### GitHub Org
```bash
./pyprojectsetup.sh --github-org \
    --project-name your-repo \
    --org your-org-name
```

Skip `--org` by setting `GITHUB_REPOCREATE_ORG`

### Optional Flags
- `--autocommit`: YOLO push straight to main after setup
- `-v, --version`: Show version (currently 1.0.0)
- `-h, --help`: Show help when you're lost

## What This Script Actually Does

1. Validates your inputs aren't complete garbage
2. Checks all required tools exist
3. Verifies your auth tokens aren't expired/malformed
4. Makes sure repo name doesn't exist (no force overwrites)
5. Creates repo via API
6. Bootstraps Python project with `uv init`
7. Sets up git remote
8. Optionally commits and pushes if you used `--autocommit`

## Error Handling

Script fails fast and loud when:
- Required tools missing
- Auth tokens invalid/missing
- Repo already exists
- Project name violates pattern
- Directory already exists
- Any git operation fails
- API calls return non-200s

## Known Issues

1. `uv init` creates `master` branch because it's stuck in 2010. Script force-renames to `main`.
2. Azure DevOps API is slow as molasses. Be patient.
3. GitHub rate limits will kick your ass if you spam requests.
4. This cannot be ran from inside a Git Repository. You will get workspace errors from uv.

## Contributing

1. Fork it
2. Branch it
3. Send a PR
4. Don't break the tests

## License

Do whatever you want with it. Just don't blame me when it breaks.