# Digest

RSS/Atom feed aggregator that generates digests in multiple formats (md, html, txt).

## Reading

Each configured digest produces output files in the repository root (`{name}.md`, `{name}.html`, `{name}.txt` depending on configuration). These files are overwritten when new items are found.

To get the latest digest, pull the repo or browse to `{name}.md` on GitHub. Daily tags (`v{YYYY-MM-DD}`) mark each update.

### Terminal Browsing 

Use `git show` with the desired tag and digest file:

```shell
$ git show v2026-01-15:ruby.md
```

Using `git` and `fzf`, you can browse digests by tag via a preview window:

```shell
$ git tag --sort=-creatordate | fzf --preview 'git show {}:<DIGEST_FILE>.md' --preview-window=top:80%:wrap
```

For markdown rendering, I recommend [`glow`](https://github.com/charmbracelet/glow):

```shell
$ git tag --sort=-creatordate | fzf --preview 'git show {}:<DIGEST_FILE>.md | glow -w0' --preview-window=top:80%:wrap
```

The included `./digest` executable uses [`bat`](https://github.com/sharkdp/bat) for syntax highlighting, rather than rendering.

## Generating

```
ruby digest.rb
```

Fetches all configured feeds concurrently and writes digests for any with new items since `.last_run`.

To re-fetch the last 24 hours:

```
rm .last_run && ruby digest.rb
```

## Configuration

Feed URLs are grouped under named digests in `config.yml`:

```yaml
mail:
  host: MAIL_HOST
  username: MAIL_USERNAME
  password: MAIL_PASSWORD

digests:
  ruby:
    feeds:
      - https://rubyweekly.com/rss
      - https://railsatscale.com/feed.xml
    format:
      - md
    mail:
      format: html
      to:
        - RUBY_DIGEST_RECIPIENT
```

Each digest key creates output files based on `format` (defaults to `[md]`). Supported formats: `md`, `html`, `txt`.

The top-level `mail` key maps SMTP settings to environment variable names. Per-digest `mail.to` lists environment variable names containing recipient addresses. `mail.format` controls the email format (defaults to `html`). The mail format is automatically generated alongside the digest formats, so there's no need to list it in both places.

## Files

```
config.yml      Named digest configurations
digest.rb       Main script
mail.rb         Email delivery script
.last_run       ISO 8601 timestamp of last run
{name}.{fmt}    Generated digests (md, html, txt)
```

## GitHub Action

Runs daily at 8 AM UTC via `.github/workflows/digest.yml`. Can be triggered manually from Actions > Generate Daily Digest > Run workflow.

Commits generated files (`*.md`, `*.html`, `*.txt`) and `.last_run`, then creates a `v{YYYY-MM-DD}` tag. Emails digests that have `mail.to` configured (continues on error so mail failures don't block the commit).
