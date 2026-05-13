---
description: Create a Jira task in the SW project, sized and assigned, in the current sprint
argument-hint: <title> :: <description>
---

Create a Jira task for a piece of work using the **Jira Cloud REST API** with an API token (no MCP dependency). Arguments: `<title> :: <description>` — title and description separated by ` :: ` (e.g., `Jump-to-snippet input :: Adds a numeric input in the annotate view that jumps to snippet N. ~half a day of work.`).

Intended to be called both standalone and from `/feature` before implementation begins.

## One-time setup (per developer)

1. Create a Jira API token at https://id.atlassian.com/manage-profile/security/api-tokens.
2. Export the two required env vars (add to `~/.zshrc`, `~/.envrc`, or your secrets manager):

   ```bash
   export JIRA_EMAIL="your.email@c-mo.solutions"
   export JIRA_API_TOKEN="<token from step 1>"
   ```

3. Make sure `.claude/jira-config.json` exists in the project. Template:

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

   - `boardId`: Scrum board the active sprint belongs to (URL: `/jira/software/c/projects/SW/boards/<id>`)
   - `assigneeAccountId`: GET `https://<siteDomain>/rest/api/3/myself` to find your own, or `/user/search?query=<email>`
   - `sprintFieldId` / `storyPointsFieldId`: usually `customfield_10020` / `customfield_10016` on Jira Cloud — confirm with `/rest/api/3/field`
   - `checkpointKey`: optional parent (Epic key) to link new tasks under; `null` to skip

## Auth

All API calls use HTTP Basic Auth with the email + token. Pattern:

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
     -H "Content-Type: application/json" \
     "https://<siteDomain>/rest/api/3/..."
```

If `JIRA_EMAIL` or `JIRA_API_TOKEN` is empty, abort with: "JIRA_EMAIL and JIRA_API_TOKEN must be set — see the Setup section of /create-jira-task."

## Steps

1. **Read config**: Load `.claude/jira-config.json`. Extract `siteDomain`, `projectKey`, `boardId`, `assigneeAccountId`, `issueTypeName`, `sprintFieldId`, `storyPointsFieldId`, `checkpointKey`, `storyPointScale`.

2. **Parse arguments**: Split on ` :: ` into `<title>` and `<description>`. If no `::` is given, treat the full input as the title and use a one-line summary of the surrounding context as the description.

3. **Estimate story points**: Pick a value from `storyPointScale` based on the description (and any context from the calling command). Use the scale literally: 1 ≈ 1 hour, 2 ≈ half a day, 3 ≈ 1 day, 5 ≈ 5 days, 8 ≈ 2 weeks. If the estimate is uncertain, round up. Append a short `Story-point reasoning: …` line to the description.

4. **Resolve target sprint** — query the board's sprints directly:

   ```bash
   # Active sprint
   curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        "https://<siteDomain>/rest/agile/1.0/board/<boardId>/sprint?state=active"
   ```

   Pick the first sprint in the `values` array. If empty, query `?state=future` and pick the earliest by `startDate`. If both are empty, abort and ask the user which sprint to use — **do not** create an unsprinted ticket.

   Store the resolved sprint as `<sprintId>` (numeric) and `<sprintName>` (for the report).

5. **Resolve checkpoint shape** (only if `checkpointKey` is set):

   ```bash
   curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        "https://<siteDomain>/rest/api/3/issue/<checkpointKey>?fields=issuetype"
   ```

   If `fields.issuetype.hierarchyLevel >= 1` (Epic / Initiative / above-Task), set `parentLink = true`. Otherwise `parentLink = false`.

6. **Create the issue** — POST to `/rest/api/3/issue`. The v3 API requires `description` in Atlassian Document Format (ADF); wrap the plain-text description in a single paragraph node:

   ```bash
   curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        -H "Content-Type: application/json" \
        -X POST "https://<siteDomain>/rest/api/3/issue" \
        -d @- <<'JSON'
   {
     "fields": {
       "project":    { "key": "<projectKey>" },
       "issuetype":  { "name": "<issueTypeName>" },
       "summary":    "<title>",
       "assignee":   { "accountId": "<assigneeAccountId>" },
       "description": {
         "type": "doc", "version": 1,
         "content": [
           { "type": "paragraph", "content": [{ "type": "text", "text": "<description>" }] }
         ]
       },
       "<sprintFieldId>":       <sprintId>,
       "<storyPointsFieldId>":  <estimatedSp>
     }
   }
   JSON
   ```

   If `parentLink` is true, add `"parent": { "key": "<checkpointKey>" }` to the `fields` object. Capture the new issue's `key` from the response.

7. **Link to checkpoint if needed** — only if `checkpointKey` is set and `parentLink` is false:

   ```bash
   # List link types and pick "Relates" (or the closest equivalent)
   curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        "https://<siteDomain>/rest/api/3/issueLinkType"

   # Create the link
   curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        -H "Content-Type: application/json" \
        -X POST "https://<siteDomain>/rest/api/3/issueLink" \
        -d '{
          "type":         { "name": "Relates" },
          "inwardIssue":  { "key": "<newKey>" },
          "outwardIssue": { "key": "<checkpointKey>" }
        }'
   ```

8. **Report**: Output the new issue key, web URL (`https://<siteDomain>/browse/<KEY>`), sprint name, and assigned story points. If invoked by `/feature`, return the issue key so the caller can use it as `<ticket>`.

## Rules

- Always read the config from `.claude/jira-config.json` at runtime — never hard-code IDs in this file.
- Always read credentials from `$JIRA_EMAIL` / `$JIRA_API_TOKEN` env vars — never inline a token in any command or commit it.
- Never invent story-point values outside the configured scale.
- If sprint resolution returns no active and no future sprint, abort and ask the user which sprint to use rather than creating an unsprinted ticket.
- Do not mention AI / Claude / automation in the issue title or description.
