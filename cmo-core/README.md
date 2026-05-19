# cmo-core

Language-agnostic plugin for the cmo-claude-plugins marketplace. Provides code review and project analysis agents, git/PR commands, a Jira task creator, universal coding/security/git skills, and a hook that reminds the model to load the right skills on every prompt.

## What's inside

| Type | Name | Purpose |
|---|---|---|
| Agent | `code-reviewer` | Reviews diffs for security, quality, architecture; confidence-filtered findings |
| Agent | `project-analyzer` | Multi-phase analysis (architecture, patterns, smells, errors, coupling, security) |
| Command | `/feature` | End-to-end finishing: detect conventions skills from the diff, run analyzer + reviewer **in parallel**, then open the PR via `/pr` |
| Command | `/clear-repo` | Switch to default branch and delete every merged local branch |
| Command | `/pr` | Push branch and open a PR — never merges; reviewer handles that |
| Command | `/create-jira-task` | Create a sized, assigned, sprinted Jira task via REST API |
| Command | `/upgrade-documentation` | Upgrade README + architectural diagrams to the C-Mo standard (IEC 62304 notation) |
| Skill | `coding-standards` | SOLID + Fowler smells + clean code (universal) |
| Skill | `testing-standards` | Tier structure, two-level Jira traceability (Task / Requirement), test independence and parallelism, scenario coverage (universal) |
| Skill | `git-operations` | Conventional commits, no AI attribution, branch hygiene |
| Skill | `security-review` | Secrets, input validation, SQL injection, authz, XSS, CSRF, rate limiting |
| Hook | `skill-reminder` | UserPromptSubmit hook — inspects the branch diff and emits a targeted list of skills to load (e.g., `coding-standards` + `python-conventions` + `git-operations` for a Python diff). Falls back to a generic reminder outside git repos or when the branch is clean. |

## How `/feature` keeps reviews aligned with conventions

The skill-reminder hook, the `/feature` command, and the two review agents all share one source of truth for "what counts as a project convention": the conventions skills (`python-conventions`, `dotnet-conventions`, `vue-conventions`, etc.). The hook derives a skill list from the diff, `/feature` passes that same list into both review agents in parallel, and the agents are instructed to treat those skills as authoritative — so the analyzer can't flag a pattern as a smell that the conventions skill explicitly prescribes. If the conventions and the analyzer ever disagree, the conventions win and the analyzer's rule is the one that needs updating.

## Setup

Most agents/commands work out of the box. **`/create-jira-task` requires per-developer credentials and a per-project config**, set up once.

### 1. Create a Jira API token (per developer)

Visit https://id.atlassian.com/manage-profile/security/api-tokens and generate a token.

### 2. Export credentials (per developer)

Add to `~/.zshrc`, `~/.envrc`, or your secrets manager:

```bash
export JIRA_EMAIL="your.email@c-mo.solutions"
export JIRA_API_TOKEN="<token from step 1>"
```

### 3. Add `.claude/jira-config.json` to each project that uses `/create-jira-task`

Template:

```json
{
  "siteDomain": "c-mo.atlassian.net",
  "projectKey": "SW",
  "boardId": 42,
  "assigneeAccountId": "5b10ac8d82e05b22cc7d4ef5",
  "issueTypeName": "Task",
  "sprintFieldId": "customfield_10020",
  "storyPointsFieldId": "customfield_10016",
  "checkpointKey": null,
  "storyPointScale": [1, 2, 3, 5, 8]
}
```

Field reference:

| Field | What it is / how to find it |
|---|---|
| `siteDomain` | Your Atlassian Cloud host, e.g. `c-mo.atlassian.net` |
| `projectKey` | The Jira project key (e.g. `SW`) |
| `boardId` | Scrum board id for the active sprint — URL `/jira/software/c/projects/<KEY>/boards/<id>` |
| `assigneeAccountId` | Default assignee. Find via `GET https://<siteDomain>/rest/api/3/myself` or `/rest/api/3/user/search?query=<email>` |
| `issueTypeName` | Issue type to create (usually `Task`) |
| `sprintFieldId` | Custom field id for Sprint — usually `customfield_10020`. Confirm via `GET /rest/api/3/field` |
| `storyPointsFieldId` | Custom field id for Story Points — usually `customfield_10016` |
| `checkpointKey` | Optional parent Epic key to link new tasks under; `null` to skip |
| `storyPointScale` | Allowed point values; the command will never produce a value outside this list |

### 4. Verify

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
     "https://c-mo.atlassian.net/rest/api/3/myself"
```

If you get JSON back with your account info, the credentials work. If you get `401`, the token is wrong or the email doesn't match.

## Security notes

- `JIRA_API_TOKEN` is a personal credential — never commit it. Keep it in env vars, `.envrc`, or a secrets manager.
- `.claude/jira-config.json` contains no secrets and **should** be committed so every dev on the project gets the same defaults.
- The Claude Code `.claude/` directory must stay out of git — `git-operations` skill enforces this; check `.git/info/exclude` if you're unsure.
