# Personal Skills

An editable collection of skills for coding agents.

## Why this repo

I want to adopt useful ideas from other skills and adjust them as my workflow changes, instead of relying on skills I cannot change. Keeping them in my own repo lets me edit them on the fly: be like water.

The main inspiration for this repo is [Matt Pocock's skills](https://github.com/mattpocock/skills).

## Setup

Install [gum](https://github.com/charmbracelet/gum) first. Gum 0.7 or newer with `--label-delimiter` support is required.

Run:

```sh
./setup.sh
```

Setup is a two-step flow:

1. Choose **Install skills** or **Uninstall skills**.
2. Choose the coding agents to act on (all start selected).

The skill picker then lists only the skills relevant to that action, computed from what is on disk right now:

- **Install** shows skills that are not yet symlinked from this repo into at least one chosen agent. Every gap starts selected; unselect anything you do not want. Installing only ever adds links, so re-running is safe and a second run lists nothing new.
- **Uninstall** shows skills that are symlinked from this repo into at least one chosen agent. Nothing starts selected, so removals are always deliberate.

A skill is symlinked into each agent's user-level skills folder, so edits in this repo are available to the installed agents. If a destination already exists but is not a link to this repo (a real folder, or a link to somewhere else), gum asks before replacing it. Uninstall removes only links that point at this repo's copy; anything else is left alone.

Afterwards setup prints two reports across all supported agents: skills missing from some agent folders, and installed skills that do not exist in this repo.

When Codex has a skill installed, setup generates ignored `agents/openai.yaml` UI metadata from that skill's frontmatter. Existing hand-written metadata is preserved, and generated metadata is removed when the skill is no longer installed for Codex.

Supported agents: Claude Code, Codex, GitHub Copilot, Pi, Snowflake CoCo, and OpenCode.

## Skill layout

Put skills under a group folder inside `skills/`:

```text
skills/
└── group-name/
    └── skill-name/
        ├── SKILL.md
        └── optional supporting files
```

Group folders are discovered automatically. Each skill's `SKILL.md` must have `name` and `description` fields in its YAML frontmatter.
