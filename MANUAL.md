# Manual

Ruby Digest fetches RSS/Atom feeds daily and generates a markdown digest of new items.

## How it works

1. `digest.rb` reads feed URLs from `config.yml`
2. Fetches each feed and filters to items published since `.last_run`
3. If there are new items, (over)writes `digests/YYYY-MM-DD.md` and updates the `README.md` symlink
4. Updates `.last_run` timestamp

## Files

- `config.yml` - List of feed URLs and other settings
- `digest.rb` - Main script 
- `.last_run` - ISO 8601 timestamp of last run
- `digests/` - Generated markdown digests
- `README.md` - Symlink to latest digest

## Usage

```
ruby digest.rb
```

To reset and fetch the last 24 hours again:

```
rm .last_run && ruby digest.rb
```

This will overwrite any existing digest for today.

## GitHub Action

The workflow at `.github/workflows/digest.yml` runs automatically on a schedule and can be triggered manually.

- **Schedule**: Daily at 8 AM UTC
- **Manual trigger**: Go to Actions > Generate Daily Digest > Run workflow

The action commits `digests/`, `.last_run`, and `README.md` if there are changes.
