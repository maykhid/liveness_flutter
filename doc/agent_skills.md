# Agent skills

← [Back to the README](../README.md)

The package ships two [agent skills](https://agentskills.io) in its
`skills/` folder: instructions that Claude Code, Codex, Cursor, GitHub
Copilot, Gemini CLI and other coding agents load when a task calls for
them, so the agent integrates the package the way the README describes
instead of guessing.

| Skill | Helps with |
|---|---|
| `liveness-flutter` | The app: platform setup, choosing actions, tuning, custom UI, the controller, uploads, server challenges, attestors and anti-spoof models. It also keeps the agent from claiming more than the package does. |
| `liveness-flutter-server` | Your backend, in any language: issuing challenges and checking uploads, photo hashes and attestation tokens. Includes a reference verifier and a test vector. |

## Installing them

From your app's root, after adding `liveness_flutter` to `pubspec.yaml`:

```bash
dart run liveness_flutter:skills
```

This copies the skills from the version of the package you have
installed, so what your agent reads matches the API you're using. It
replaces any copies already there.

Where they go depends on which agents your project already has files for:

| Agent | Skills folder | Detected by |
|---|---|---|
| Claude Code | `.claude/skills` | `.claude/` or `CLAUDE.md` |
| Cursor | `.cursor/skills` | `.cursor/` |
| GitHub Copilot | `.github/skills` | `.github/skills/` or `.github/copilot-instructions.md` |
| Gemini CLI | `.gemini/skills` | `.gemini/` or `GEMINI.md` |
| Codex and other agents | `.agents/skills` | `.agents/` or `AGENTS.md` |

If it finds several, it installs into each. If it finds none, it uses
`.agents/skills`.

Options:

| Option | Does |
|---|---|
| `--agent <name>` | Install where this agent looks: `agents`, `claude`, `copilot`, `cursor`, `gemini` or `all`. Repeatable. |
| `--dir <path>` | Install into this folder instead. Repeatable. |
| `--skill <name>` | Install only this skill. Repeatable. |
| `--list` | List the skills in the installed package. |
| `--help` | Show every option. |

Commit the skills folder so everyone on the team, and your CI agents, get
the same skills. Run the command again after upgrading the package.

## Using them

Ask the agent for what you want, for example "add a liveness check
before the payout screen" or "verify liveness uploads on our API". The
agent picks the right skill from its description. You can also name it:
"use the liveness-flutter skill".

## A backend in another repository

The server skill doesn't need Dart. Either copy
`skills/liveness-flutter-server` from this repository into the backend's
skills folder, or run:

```bash
npx skills add maykhid/liveness_flutter
```

Both give you the repository's latest skills, which may be ahead of the
package version your app uses. Only `dart run liveness_flutter:skills`
matches your installed version, so for the backend, check the skill's
`metadata.written-for` against the app's package version.
