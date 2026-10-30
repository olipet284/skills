# Personal Skills

An editable collection of skills for coding agents.

## Why this repo

I want to adopt useful ideas from other skills and adjust them as my workflow changes, instead of relying on skills I cannot change. Keeping them in my own repo lets me edit them on the fly: be like water.

The main inspiration for this repo is [Matt Pocock's skills](https://github.com/mattpocock/skills).

## Setup

Install [gum](https://github.com/charmbracelet/gum) first. Gum 0.7 or newer is required.

Run:

```sh
./setup.sh
```

Choose the coding agents to install to, then choose skills within each discovered group. All agents start selected. A skill starts selected only when it is already symlinked from this repo in at least one selected agent. Each skill picker shows the skill name and description from its `SKILL.md`.

Selected skill directories are symlinked into each agent's user-level skills folder, so edits in this repo are available to the installed agents. If a selected skill already exists there, gum asks before replacing it. Setup removes only links it previously created when they are no longer selected. Other installed skills are left alone and reported under their agent.

When Codex is selected, setup generates ignored `agents/openai.yaml` UI metadata from selected skills' frontmatter. Existing hand-written metadata is preserved.

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
