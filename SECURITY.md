# Security Policy

Thanks for helping keep **claude-statusline** and its users safe.

## Supported versions

This is a single-track, rolling release: only the **latest version** is supported.
If you're not current, update before reporting:

```sh
~/.claude/statusline-update.sh          # update to the latest
~/.claude/statusline-update.sh --status # shows what you have
```

| Version | Supported |
|---|---|
| Latest (`main`) | ✅ |
| Anything older | ❌ — please update first |

## Reporting a vulnerability

**Please do _not_ open a public issue for security problems.**

Report privately through GitHub's **Private vulnerability reporting**:

> Repo **Security** tab → **Report a vulnerability** → fill in the advisory form.

(Direct link: `https://github.com/Lucid06-K/claude-statusline/security/advisories/new`)

Please include:

- what you found and where (file + line, or the relevant command / menu path),
- steps to reproduce, or a minimal proof of concept,
- the impact you think it has, and
- your version (`statusline-update.sh --status`) and OS.

**What to expect:**

- **Acknowledgement:** within ~7 days.
- **Assessment & fix:** for a confirmed issue, a patch is shipped on `main` (delivered to users via the updater) as quickly as is practical, and the advisory is published once a fix is available.
- **Credit:** you'll be credited in the advisory unless you'd prefer to stay anonymous.

If you can't use GitHub private reporting, open a normal issue titled **"security — please contact me"** with **no technical details**, and a maintainer will arrange a private channel.

## Scope

Most relevant areas to look at:

- **The updater** (`statusline-update.sh` / opt-in auto-update) — the only part that fetches and runs remote code.
- **The renderer** (`statusline-command.sh`) — it parses untrusted JSON from Claude Code on **stdin**, and **sources** a local config file each render.
- **The config/mode handling** (`statusline-config.sh`, `statusline-mode.sh`) — writes the conf, mode, picker, and per-session files under `~/.claude/`.

Out of scope: issues that require an already-compromised user account or local filesystem write access; social-engineering of the user; and anything in Claude Code itself or third-party tools you run alongside it.

## Security design (what's already in place)

The project is conservative by default:

- **Runs entirely in user space — never `sudo`**, nothing system-wide. The only network access anywhere is the updater's `git fetch`.
- **Reads, never executes, the JSON** Claude Code pipes in. It's parsed with `jq`; values are used as quoted data and interpolated into display strings only — there is **no `eval`** of session input, filenames, branch names, or rate-limit data.
- **The config files are trusted local data.** The renderer `source`s `~/.claude/statusline.conf` (or a per-session conf) the same way your shell sources `~/.zshrc` — these files are only ever written by this tool's own scripts, which emit only `KEY=0|1` and `SL_MODE=<validated-name>` lines. Writing to them requires local access to your account; treat them with the same trust as your dotfiles.
- **Updates are fast-forward only, over HTTPS, pinned to this repository.** `git pull --ff-only origin <branch>` cannot rewrite or clobber local history and aborts if you have local changes. After pulling, every script is **syntax-checked** (`bash -n`) before it can be loaded; a fast-forward only ever lands whole commits whose content is **hash-verified by git** in transit. **Auto-update is off by default**, and when on it runs a throttled background check **once a day** that never blocks a render.

## Trust note

The update integrity anchor is **git's content hashing over HTTPS to the pinned origin** — a malicious mirror, CDN, or TLS downgrade cannot silently alter what you pull. Unlike a tool that signs releases with an **offline key**, this project does **not** independently sign commits, so the remaining trust assumptions are: (1) the **GitHub repository/account** isn't compromised to push malicious commits, and (2) the **first install** — you're trusting the initial clone. Because of (1), **auto-update is opt-in**; for a manual update you can always review the diff on GitHub first, and since the scripts are plain bash, you can read exactly what changed.
