# Copilot Triage

Label issues and answer questions with small, cached Copilot prompts.

One prompt chooses labels and an optional clarification. A technical question
can use one more prompt with relevant documentation. A Ruby script validates
the result and publishes through GitHub's API.

```ruby
item, labels = read_report
decision = assess(item, labels)
publish(item, labels, decision)
```

This is an independent project using GitHub Copilot CLI. It is not an official
GitHub product. The first release is a preview: tests verify the workflow's
behavior and CLI requests with a fake model; live answer quality and end-to-end
cost have not yet been benchmarked.

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
  discussion:
    types: [created]

permissions:
  contents: read
  issues: write
  discussions: write

concurrency:
  group: triage-${{ github.event.issue.number || github.event.discussion.number }}
  cancel-in-progress: false

jobs:
  triage:
    if: github.event.sender.type != 'Bot'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: crmne/copilot-triage@v0.1.0
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

Also add `|| inputs.number` to the concurrency group expression. A manual run
shows its decision in the job summary without changing GitHub. It can preview
closed reports. Uncached prompts still consume Copilot credits.

## Replies

Complete bug reports normally get labels and no comment. Missing information
gets one prewritten question. Technical answers use the supplied docs or source,
with a short example when useful and verified links placed inside the reply.
Replies stay under 60 words and at most three sentences, with no headings,
tables, em dashes, or generic status summaries.

For example, a reply might be:

> Which version are you using?

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

Each run reads the current report and its latest five comments. Technical
answers can read at most two complete source files, up to 48 KB combined.
Duplicate investigations, uncertain answers, and product decisions stay with
the maintainer. This bounds the work; it does not reproduce a full repository
investigation or guarantee the same answer as a larger agent.

The action suppresses replies when a maintainer or bot commented most recently.
It checks the report again before publishing and skips if it changed. Successful
assessments get a bot 🎉 reaction. Ordinary comments do not trigger the example
workflow. PRs are outside its scope; GitHub's built-in Copilot code review is a
separate product.

## Cost and caching

The default model is `gpt-5.6-luna`; set `model` to change it. The first prompt
is limited to 24 KB and the answer prompt to 64 KB. Oversized input is left for
a maintainer rather than silently truncated. Copilot adds its own system
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

MIT licensed. Extracted from [RubyLLM](https://github.com/crmne/ruby_llm).
