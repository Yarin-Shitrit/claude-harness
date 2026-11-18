---
name: gitlab-review
description: Perform an AI code review on a GitLab merge request by MR number. Posts inline discussion threads with code suggestions on each finding. Triggers on requests to review a GitLab MR, code review for merge request, or posting feedback on a GitLab MR.
user_invocable: true
metadata:
  author: yarin
  version: "2.0.0"
  argument-hint: <project_id> <mr_iid>
---

# GitLab Merge Request Code Review (Inline Threads)

Perform a code review on a GitLab merge request and post each finding as a separate
inline discussion thread on the exact diff line, with code suggestions.

## Arguments

This skill expects two arguments separated by a space:
- `project_id` - The GitLab project ID (numeric) or URL-encoded path (e.g., `my-group%2Fmy-project`)
- `mr_iid` - The merge request IID (the project-scoped number shown in the GitLab UI, e.g., `42`)

If arguments are missing, ask the user for the project ID and MR IID.

## Configuration

This skill reads credentials from environment variables:
- `GITLAB_TOKEN` - GitLab personal access token (requires `api` scope)
- `GITLAB_HOST` - GitLab hostname (e.g., `gitlab.mycompany.com`)
- `GITLAB_REVIEW_SERVICE_DIR` - local checkout of the gitlab-mcp-code-review service
  (the FastAPI `app/` package plus its `.venv`). Defaults to `~/gitlab-mcp-code-review`.

If `GITLAB_TOKEN` or `GITLAB_HOST` is missing, tell the user to set them. If the service directory
does not exist, tell the user the review service has to be installed first and stop.

## Workflow

### Step 1: Validate Configuration

```bash
echo "HOST: $GITLAB_HOST" && echo "TOKEN set: $([ -n "$GITLAB_TOKEN" ] && echo yes || echo no)"
```

### Step 2: Call the Code Review Service

The FastAPI service at `http://localhost:8000` handles the full pipeline. Call it:

```bash
curl -s -X POST http://localhost:8000/review \
  -H "Content-Type: application/json" \
  -d '{"project_id": "<PROJECT_ID>", "mr_iid": <MR_IID>, "post_comments": true}'
```

If the service is not running, start it first:

```bash
cd "${GITLAB_REVIEW_SERVICE_DIR:-$HOME/gitlab-mcp-code-review}" && \
  .venv/bin/uvicorn app.main:app --port 8000 &
```

Then retry the curl call.

### Step 3: Present Results

The service returns JSON with:
- `summary` - Overall assessment of the MR
- `findings` - Array of inline findings, each with `file_path`, `line`, `severity`, `comment`, `suggestion`
- `threads_created` - How many inline discussion threads were posted to GitLab
- `files_reviewed` - Number of files analyzed

Present the results to the user:

```
## MR Review: <mr_title> (!<mr_iid>)

**URL:** <mr_url>
**Files reviewed:** <files_reviewed>
**Threads created:** <threads_created>

### Summary
<summary>

### Findings
For each finding:
- **[severity]** `file_path:line` — comment
  Suggestion: `suggestion` (if present)
```

### Fallback: Direct API Mode

If the service is unavailable, perform the review manually using curl:

1. **Fetch MR details** (need `diff_refs` for positioning):
```bash
curl -s --header "Private-Token: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/<PROJECT_ID>/merge_requests/<MR_IID>"
```

2. **Fetch diffs:**
```bash
curl -s --header "Private-Token: $GITLAB_TOKEN" \
  "https://$GITLAB_HOST/api/v4/projects/<PROJECT_ID>/merge_requests/<MR_IID>/changes"
```

3. **Analyze** the diffs yourself (as Claude) and identify findings with file paths and line numbers.

4. **Post each finding as an inline discussion thread:**
```bash
curl -s -X POST --header "Private-Token: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  --data '{
    "body": "**SEVERITY**\n\nComment here.\n\n```suggestion:-0+0\nreplacement code\n```",
    "position": {
      "position_type": "text",
      "base_sha": "<base_sha from diff_refs>",
      "head_sha": "<head_sha from diff_refs>",
      "start_sha": "<start_sha from diff_refs>",
      "new_path": "path/to/file.py",
      "old_path": "path/to/file.py",
      "new_line": <line_number>
    }
  }' \
  "https://$GITLAB_HOST/api/v4/projects/<PROJECT_ID>/merge_requests/<MR_IID>/discussions"
```

The `diff_refs` object (from step 1) provides `base_sha`, `head_sha`, and `start_sha`.
The `new_line` must be a line number from the NEW side of the diff.
The `suggestion` block uses GitLab's native suggestion syntax so developers can apply fixes with one click.

5. **Post a summary note** after all inline threads are created.

## Important Rules

- NEVER approve or unapprove the MR automatically. Only review and comment.
- Each finding = one discussion thread on the exact line in the diff.
- Include `suggestion` blocks with corrected code so developers can apply with one click.
- If API calls fail with 401, tell the user to verify their GITLAB_TOKEN has `api` scope.
- If API calls fail with 404, suggest the user check the project ID and MR IID.
