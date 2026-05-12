---
name: keychain-secrets
description: Manage local API keys and other secrets for agents using macOS Keychain without exposing secret values in chat or plaintext files. Use when the user wants to store, update, list, annotate, retrieve, export, or inject secrets such as OPENAI_API_KEY, ANTHROPIC_API_KEY, tokens, credentials, or agent environment variables.
metadata:
  short-description: Manage agent secrets via macOS Keychain
---

# Keychain Secrets

Use this skill to manage local secrets for agent workflows. The durable secret value must live in macOS Keychain; metadata such as env var name and notes may live in the skill index.

## Safety Rules

- Never paste secret values into the conversation.
- Prefer `run` to inject secrets into a subprocess environment without printing them.
- If a user asks to view a secret, warn that it will print locally and use `get --show`; do not repeat the value in the final answer.
- Do not store secret values in repo files, notes, logs, generated reports, or shell snippets shown in the chat.
- Use `put --prompt` or `put --stdin` instead of putting secrets directly in shell commands.

## Tool

Use the bundled script:

```bash
python scripts/keychain_secrets.py --help
```

The script stores values in macOS Keychain and keeps a plaintext metadata index at:

```text
~/Library/Application Support/KeychainSecrets/index.json
```

The index does not contain secret values.

## Common Workflows

Store or update a secret:

```bash
python scripts/keychain_secrets.py put OPENAI_API_KEY \
  --prompt \
  --note "OpenAI API key for Codex and Harbor evals"
```

List managed secrets and notes:

```bash
python scripts/keychain_secrets.py list
```

Install and open the native macOS app for configuring names, env vars, notes, and Keychain values without running a localhost service:

```bash
python scripts/keychain_secrets.py app
```

The app is installed at:

```text
~/Applications/KeychainSecrets.app
```

You can open it later from Finder, Spotlight, or:

```bash
open "$HOME/Applications/KeychainSecrets.app"
```

Start the legacy local web UI when a browser-based fallback is useful:

```bash
python scripts/keychain_secrets.py open
```

This starts the localhost service if needed and opens:

```text
http://127.0.0.1:8765
```

In the web UI, use `Edit` on a row to load its metadata into the form. Leave the secret field blank to update only env var name and note; provide the secret again when changing Keychain service or account.

Stop the local web UI:

```bash
python scripts/keychain_secrets.py stop
```

Show metadata for one secret:

```bash
python scripts/keychain_secrets.py info OPENAI_API_KEY
```

Run a command with one or more secrets injected as environment variables:

```bash
python scripts/keychain_secrets.py run OPENAI_API_KEY -- env | grep OPENAI_API_KEY
```

Export a shell command locally. This prints the secret to the terminal, so do not paste its output into chat:

```bash
python scripts/keychain_secrets.py export OPENAI_API_KEY
```

Delete a managed secret from Keychain and remove its metadata:

```bash
python scripts/keychain_secrets.py delete OPENAI_API_KEY
```

## Notes

- `security add-generic-password` without `-U` does not update an existing item. The script uses `-U`.
- Keychain values do not automatically become environment variables. Use `run` or evaluate the local `export` output in a shell.
- The default Keychain `service` and injected env var name are both the provided name, for example `OPENAI_API_KEY`.
- `app` installs and opens a native macOS app; no localhost service is involved.
- `open` starts the web UI only when needed and opens it. `launch` starts the web UI through a user-level `launchctl` job; `serve` runs it in the foreground for debugging.
- The web UI binds to `127.0.0.1` by default and never renders secret values back into the page.
