---
description: Create a Jira task in the SW project, sized and assigned, in the current sprint
argument-hint: <title> :: <description>
---

Create a Jira task for a piece of work using the **Jira Cloud REST API** with an API token. Arguments: `<title> :: <description>` — title and description separated by ` :: ` (e.g., `Jump-to-snippet input :: Adds a numeric input in the annotate view that jumps to snippet N. ~half a day of work.`).

Intended to be called both standalone and from `/feature` before implementation begins.

> **Setup required.** This command relies on `$JIRA_EMAIL`, `$JIRA_API_TOKEN`, and a `.claude/jira-config.json` file. If any are missing, see `cmo-core/README.md` → Setup and abort with a short error pointing the user there.

## Auth

All API calls use HTTP Basic Auth with the email + token:

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
     -H "Content-Type: application/json" \
     "https://<siteDomain>/rest/api/3/..."
```

If `JIRA_EMAIL` or `JIRA_API_TOKEN` is empty, abort with: `JIRA_EMAIL and JIRA_API_TOKEN must be set — see cmo-core/README.md → Setup.`

## Steps

1. **Read config**: Load `.claude/jira-config.json`. Extract `siteDomain`, `projectKey`, `boardId`, `assigneeAccountId`, `issueTypeName`, `sprintFieldId`, `storyPointsFieldId`, `checkpointKey`, `storyPointScale`. If the file is missing, abort with: `.claude/jira-config.json not found — see cmo-core/README.md → Setup.`

2. **Parse arguments**: Split on ` :: ` into `<title>` and `<description>`. If no `::` is given, treat the full input as the title and use a one-line summary of the surrounding context as the description.

3. **Estimate story points**: Pick a value from `storyPointScale` based on the description (and any context from the calling command). Use the scale literally: 1 ≈ 1 hour, 2 ≈ half a day, 3 ≈ 1 day, 5 ≈ 5 days, 8 ≈ 2 weeks. If the estimate is uncertain, round up. Append a short `Story-point reasoning: …` line to the description.

4. **Resolve target sprint** — query the board's sprints directly:

   ```bash
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
   curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        "https://<siteDomain>/rest/api/3/issueLinkType"

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
