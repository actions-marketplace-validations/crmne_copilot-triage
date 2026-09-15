# Copilot Triage

**You shouldn't need 2,000 lines of generated YAML to label an issue.**

Copilot Triage is a small alternative to **GitHub Agentic Workflows** for issues
and discussions, built for [RubyLLM](https://github.com/crmne/ruby_llm) and
[Spotifast](https://github.com/crmne/spotifast). A Ruby script, a cheap model,
and cached answers. Read the report, help the person, get out of the way.

## Why this exists

We used [GitHub Agentic Workflows](https://github.com/github/gh-aw) to triage
[RubyLLM](https://github.com/crmne/ruby_llm) and
[Spotifast](https://github.com/crmne/spotifast) issues and discussions. In
RubyLLM alone, the [compiled workflow](https://github.com/crmne/ruby_llm/blob/d04b4eeb341d76440bee9a029f150b7598e5cfcc/.github/workflows/issue-assessment.lock.yml)
was **2,035 lines of YAML**. Tool gateways. Agent jobs. A separate threat detector.
Safe-output jobs. Failure-reporting machinery.

Our [recorded runs](https://github.com/crmne/ruby_llm/actions/runs/33890389416)
used Sonnet 5 to assess reports and Haiku 4.5 to inspect the output. Both consumed
Copilot credits. Then the workflow started
[opening issues about its own failures](https://github.com/crmne/ruby_llm/issues/922)
and [posting comments about its detector failing](https://github.com/crmne/ruby_llm/issues/913).
The bot became another thing to maintain. And another source of email.

That is a ridiculous amount of machinery for this job.

GitHub Agentic Workflows is a general agent platform. We needed a bot for
issues and discussions.
So we removed the platform and kept the job.

## Small on purpose

One prompt chooses labels and a short assessment or clarification. A technical
question can use one more prompt with relevant documentation. Ruby validates the result
and calls GitHub's API. That's the whole approach.

```ruby
item, labels = read_report
decision = assess(item, labels)
publish(item, labels, decision)
```

- **Use the Copilot subscription you already pay for.** The default is
  `gpt-5.6-luna`. Change the model if you want. Keep one billing account.
- **Spend tokens on the report.** One prompt for triage, one optional prompt for
  a technical answer. The model gets the relevant text and has no tools.
- **Reuse the answer.** An identical validated prompt comes from cache with
  zero model calls. New comments and changed source material are considered.
- **Give people useful replies.** A missing detail gets one short question.
  A new issue gets a brief assessment grounded in the report. Technical answers
  get source links. Follow-ups must add something useful.
- **Keep the bot's problems out of your issues.** Model failures go in the job
  summary. They don't become a new ticket or a string of failure comments.
- **Read the code yourself.** [One Ruby script](lib/assessment.rb), using the
  standard library. Your repository keeps a small policy file and calls a
  shared action. Fix it once, reuse it everywhere.

Here is what we replaced in RubyLLM:

| | Our GitHub Agentic Workflows setup | Copilot Triage |
| --- | --- | --- |
| Workflow | 2,035 generated YAML lines plus a Markdown definition | A small caller and one shared Ruby script |
| Model work | Sonnet 5 assessment plus Haiku 4.5 detection | Luna triage plus an optional answer prompt |
| GitHub access | Agent tools behind a gateway, followed by safe-output jobs | Ruby validates the decision and makes the API calls |
| Reassessment | Agent-driven investigation | Cached responses when the prompt is unchanged |
| Model failures | Bot-created issues and detector comments | Job summary |

Those are differences in scope and machinery, not a claim of identical answer
quality. This reads five recent comments and up to two source files. It leaves
duplicate investigations and uncertain answers to a maintainer. We have not yet
benchmarked live answer quality or end-to-end cost against the old workflow.

**Issue triage can be this simple.**

## Use it

1. Add a `COPILOT_GITHUB_TOKEN` repository secret. Use a fine-grained token with
   **Copilot Requests** permission and an available Copilot allowance. See
   [Copilot authentication](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#copilot-login-options).
2. Save [examples/triage.yml](examples/triage.yml) as `.github/triage.yml` and
   adapt the labels, replies, source paths, and policy to your project.
3. Add `.github/workflows/triage.yml`:

```yaml
name: Triage
on:
  issues:
    types: [opened, reopened]
  issue_comment:
    types: [created]
  discussion:
    types: [created]
  discussion_comment:
    types: [created]

permissions:
  contents: read
  issues: write
  discussions: write

concurrency:
  group: >-
    triage-${{ github.event.discussion && 'discussion' || 'issue' }}-${{ github.event.issue.number || github.event.discussion.number }}-${{ github.event.discussion && (github.event.comment.parent_id || github.event.comment.id) || 'report' }}
  cancel-in-progress: false

jobs:
  triage:
    if: (github.event.sender.type != 'Bot' || github.event_name == 'issues') && !github.event.issue.pull_request
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: crmne/copilot-triage@v0.3.0
        with:
          copilot-token: ${{ secrets.COPILOT_GITHUB_TOKEN }}
```

The action checks out your repository's **default branch**, restores cached
responses, installs Copilot CLI, and runs the assessment. Commit the configuration
to that branch before enabling the workflow. It requires the Ruby, Node.js,
GitHub CLI, Git, and `timeout` commands provided by GitHub's Ubuntu runners.
There is no runtime gem dependency or provider API key.

Pin the action to a full commit SHA for an immutable version. Update that
reference to adopt a release; the implementation stays in this repository.
Keep project-specific policy in your repository.

### Preview a report

Add manual inputs to the workflow's `on` section:

```yaml
  workflow_dispatch:
    inputs:
      kind:
        type: choice
        options: [issue, discussion]
        default: issue
      number:
        description: Issue or discussion number
        required: true
```

Then add these inputs alongside `copilot-token` on the action step:

```yaml
          kind: ${{ inputs.kind || (github.event.discussion && 'discussion' || 'issue') }}
          number: ${{ inputs.number || github.event.issue.number || github.event.discussion.number }}
          dry-run: ${{ github.event_name == 'workflow_dispatch' }}
```

Also add `|| inputs.number` to the concurrency group's number expression and
`inputs.kind ||` before its kind expression. A manual run shows its decision
in the job summary without changing GitHub. It can preview closed reports.
Uncached prompts still consume Copilot credits.

## Replies

New issues can get a brief initial assessment: what the report establishes and
one useful next check. Missing information gets one short question. Technical
answers use the supplied docs or source,
with a short example when useful and verified links placed inside the reply.
The answer stays under 60 words and at most three sentences, with no headings,
tables, em dashes, or generic status summaries.

For example, a reply might be:

> Does restarting the app pick up the system theme?
>
> _Generated by [Copilot Triage](https://github.com/marketplace/actions/copilot-triage) using `gpt-5.6-luna`; 6200 input / 80 output tokens this run; [view run](https://github.com/crmne/copilot-triage/actions)._

The figures above are illustrative. Every posted comment includes this compact
footer, added by Ruby, with the model, measured input/output tokens, and a link
to the exact run attempt. Counts cover fresh calls in that run, including
provider-cached input. Cache-only runs say **0 new model tokens**; missing CLI
usage is reported as unavailable. The footer links the Marketplace listing so
readers can reuse the action. It does not spend model tokens to write itself.

Or, when the configured documentation establishes it:

> Define `execute` on your tool class. See [the guide](https://rubyllm.com/tools/).

Map documentation files to your public site in the policy:

```yaml
documentation:
  docs/*.md: https://example.com/guides/%{name}/
```

`%{name}` is the filename without its extension. The maintainer supplies this
mapping; the action does not crawl the site. Other citations link to the exact
Git revision read. Models choose source paths from a catalog and cannot invent
links. Source files outside the checkout are excluded.

Each run reads the current report and its latest five comments. A discussion
comment event reads that thread's parent and latest five replies, including
threads older than the latest top-level comments. Answers stay in that thread.
Technical answers can read at most two complete source files, up to 48 KB combined.
Duplicate investigations, uncertain answers, and product decisions stay with
the maintainer. This bounds the work; it does not reproduce a full repository
investigation or guarantee the same answer as a larger agent.

The action suppresses replies when a maintainer or bot commented most recently.
It checks the report again before publishing and skips if it changed. Successful
assessments get a bot 🎉 reaction. PRs are outside its scope; GitHub's built-in
Copilot code review is a separate product.

### Reports from Honeybadger

Private repositories work too. Allow the reporting bot in your policy:

```yaml
report_bots:
  - honeybadger[bot]
```

The workflow above admits bot-created issue events; the script checks the
author against this list before calling the model. Other bots remain excluded,
and bot comments never trigger a conversation loop. Error reports are assessed
for the maintainer using the supplied exception and backtrace. Configure the
source files it may read; keep credentials and customer data out of that input.

### Follow-up comments

Human comments on open issues and discussions trigger reassessment. If the bot
asks for a version, it can use the reporter's answer. Bot comments and comments
from owners, members, and collaborators are skipped before any model call.
Maintainers can still request a manual assessment.

Comment runs wait 30 seconds before reading GitHub. If a newer comment exists,
the older event is skipped without calling Copilot. Concurrency keeps one run
active per issue or discussion thread and replaces older pending runs in that
conversation. Separate discussion threads are assessed independently. A comment
arriving during inference invalidates that answer; the next run assesses the
updated conversation.
Active runs are allowed to finish so publishing cannot be interrupted halfway.

A new human comment usually changes the prompt and costs a model call. Cache
hits help repeated assessments of unchanged input. Reassessment does not mean
another public reply: the same response rules apply, and an exact reply already
present in the recent conversation is not posted again.

Existing issues and discussions are not automatically backfilled when you
install or upgrade the action. Use a manual preview for older reports. If a
run posts nothing, its job summary distinguishes skipped input or invalid model
output from a valid decision to stay silent.

## Cost and caching

The default model is `gpt-5.6-luna`; set `model` to change it. The first prompt
is limited to 24 KB and the answer prompt to 64 KB. Long runs of repeated NUL
bytes in pasted logs become a compact count; surrounding messages remain intact.
Other oversized input is left for a maintainer rather than silently truncated. Copilot adds its own system
context, so billed input exceeds the text supplied by the script.

Validated responses are cached through GitHub Actions. The key includes the
complete prompt, model, and script version. An unchanged prompt costs **zero
model calls**. New report text, recent comments, policy, or models change the key.
Answer keys include source contents, so documentation changes refresh the answer
while source selection can still be reused. Cached output is validated again.

The cache stores model responses, not remote conversations. Every run fetches
the report again. GitHub may evict cache entries, causing a fresh call. A new
bot reply also changes the next assessment's input. Stable policy and sources
precede report text to help provider prompt caching; Copilot determines any
provider-side discount.

There are at most two prompt invocations, each with a 90-second timeout and no
workflow retry loop. The CLI may retry service requests internally. Its minimum
session limit is 30 AI credits; this is a soft fallback limit, not an expected
price, and an in-flight response can exceed it. Actual usage JSON appears in
the job summary when available.

## Failures and permissions

Copilot failures and invalid output appear in the job summary and leave the
report unchanged. They do not create failure issues or comments. GitHub write
failures fail the job without marking the assessment complete. The action does
not change your billing settings; exhausted credits require a reset or budget.

The model has no tools, MCP servers, GitHub write token, or repository custom
instructions. It runs with isolated settings. The script controls labels and
comments and never closes reports or modifies code. Keep secrets out of report
text and the configured source files, which are sent to Copilot.

The CLI is pinned to `1.0.83`. An empty custom-agent tool list still retains
skill and SQL tools in that version, so they are excluded explicitly. The
offline integration test verifies that the actual model request has zero tools.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). Tests use fake GitHub/model responses;
the CLI integration test uses a local fake provider and spends no credits.

The first release is a preview. This independent project uses GitHub Copilot CLI
and is not an official GitHub product.

MIT licensed. Built for [RubyLLM](https://github.com/crmne/ruby_llm) and
[Spotifast](https://github.com/crmne/spotifast), reusable in your repositories.
