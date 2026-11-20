#!/usr/bin/env bash
set -eo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skills_root="$repo_root/skills"

if ! command -v gum >/dev/null 2>&1; then
  echo "gum is required. Install it from https://github.com/charmbracelet/gum and rerun setup.sh." >&2
  exit 1
fi
gum_help="$(gum choose --help 2>&1 || true)"
if ! grep -q -- '--selected' <<< "$gum_help"; then
  echo "gum 0.7 or newer is required for preselected choices." >&2
  exit 1
fi
if ! grep -q -- '--label-delimiter' <<< "$gum_help"; then
  echo "gum with --label-delimiter support is required." >&2
  exit 1
fi
if [[ ! -d "$skills_root" ]]; then
  echo "No skills/ directory found beside setup.sh." >&2
  exit 1
fi

agents=(Claude Codex Copilot Pi CoCo OpenCode)

agent_root() {
  case "$1" in
    Claude)  printf '%s/.claude/skills' "$HOME" ;;
    Codex)   printf '%s/.agents/skills' "$HOME" ;;
    Copilot) printf '%s/.copilot/skills' "$HOME" ;;
    Pi)      printf '%s/.pi/agent/skills' "$HOME" ;;
    CoCo)    printf '%s/.snowflake/cortex/skills' "$HOME" ;;
    OpenCode) printf '%s/.config/opencode/skills' "$HOME" ;;
  esac
}

join_by() {
  local sep="$1"
  shift
  local first=1 out="" item
  for item in "$@"; do
    if (( first )); then
      out="$item"
      first=0
    else
      out="$out$sep$item"
    fi
  done
  printf '%s' "$out"
}

skill_metadata() {
  awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function clean(value, first, last, single, pair) {
      value = trim(value)
      single = sprintf("%c", 39)
      first = substr(value, 1, 1)
      last = substr(value, length(value), 1)
      if ((first == "\"" || first == single) && last == first) {
        value = substr(value, 2, length(value) - 2)
        if (first == single) {
          pair = single single
          gsub(pair, single, value)
        }
      }
      return value
    }
    /^---[[:space:]]*$/ {
      if (!frontmatter) {
        frontmatter = 1
        next
      }
      exit
    }
    !frontmatter { next }
    /^name:[[:space:]]*/ {
      value = $0
      sub(/^name:[[:space:]]*/, "", value)
      name = clean(value)
      next
    }
    /^description:[[:space:]]*/ {
      value = $0
      sub(/^description:[[:space:]]*/, "", value)
      if (value ~ /^[>|]/) {
        block = 1
        description = ""
      } else {
        block = 0
        description = clean(value)
      }
      next
    }
    block && /^[[:space:]]+/ {
      value = trim($0)
      if (value != "") {
        description = (description == "" ? value : description " " value)
      }
      next
    }
    block && /^[[:space:]]*$/ { next }
    { block = 0 }
    END {
      gsub(/[[:space:]]+/, " ", description)
      print name "\t" trim(description)
    }
  ' "$1"
}

declare -A source_by_name=()
declare -A description_by_name=()
all_sources=()
all_names=()
all_descriptions=()

for group_dir in "$skills_root"/*/; do
  [[ -d "$group_dir" ]] || continue
  for skill_dir in "$group_dir"*/; do
    skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    skill_dir="${skill_dir%/}"
    metadata="$(skill_metadata "$skill_file")"
    IFS=$'\t' read -r name description <<< "$metadata"
    if [[ -z "$name" || -z "$description" || ! "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
      echo "Skipping $skill_file: valid name and description frontmatter are required." >&2
      continue
    fi
    if [[ -n "${source_by_name[$name]:-}" ]]; then
      echo "Duplicate skill name '$name'; skill names must be unique across groups." >&2
      exit 1
    fi
    source_by_name[$name]="$skill_dir"
    description_by_name[$name]="$description"
    all_sources+=("$skill_dir")
    all_names+=("$name")
    all_descriptions+=("$description")
  done
done

if (( ${#all_names[@]} == 0 )); then
  echo "No usable skills found under $skills_root." >&2
  exit 1
fi

# A skill counts as installed for an agent only when its folder is a symlink
# pointing at this worktree's copy of that skill.
is_installed() {
  local agent="$1" name="$2"
  local expected="${source_by_name[$name]:-}" dest
  [[ -n "$expected" ]] || return 1
  dest="$(agent_root "$agent")/$name"
  [[ -L "$dest" && "$(readlink -- "$dest" 2>/dev/null)" == "$expected" ]]
}

mode_label="$(env -u GUM_CHOOSE_SELECTED gum choose --header='What do you want to do?' 'Install skills' 'Uninstall skills')" || {
  echo "Action selection cancelled; nothing changed." >&2
  exit 1
}
case "$mode_label" in
  'Install skills') mode=install ;;
  'Uninstall skills') mode=uninstall ;;
  *)
    echo "Unknown action '$mode_label'; nothing changed." >&2
    exit 1
    ;;
esac

agent_selection="$(env -u GUM_CHOOSE_SELECTED gum choose --no-limit --selected='*' --header='Select coding agents' "${agents[@]}")" || {
  echo "Agent selection cancelled; nothing changed." >&2
  exit 1
}
selected_agents=()
while IFS= read -r agent; do
  [[ -n "$agent" ]] && selected_agents+=("$agent")
done <<< "$agent_selection"
if (( ${#selected_agents[@]} == 0 )); then
  echo "No agents selected; nothing changed."
  exit 0
fi
agents_label="$(join_by ', ' "${selected_agents[@]}")"

# Candidates come from what is on disk right now, so a second run naturally
# excludes whatever the previous run installed.
options=()
for name in "${all_names[@]}"; do
  installed_agents=()
  missing_agents=()
  for agent in "${selected_agents[@]}"; do
    if is_installed "$agent" "$name"; then
      installed_agents+=("$agent")
    else
      missing_agents+=("$agent")
    fi
  done
  description="${description_by_name[$name]}"
  if [[ "$mode" == install ]]; then
    (( ${#missing_agents[@]} > 0 )) || continue
    label="${name} — ${description} — missing: $(join_by ', ' "${missing_agents[@]}")"
  else
    (( ${#installed_agents[@]} > 0 )) || continue
    label="${name} — ${description} — installed in: $(join_by ', ' "${installed_agents[@]}")"
  fi
  options+=("${label}::${name}")
done

selected_names=()
if (( ${#options[@]} == 0 )); then
  if [[ "$mode" == install ]]; then
    echo "Nothing to install: every repo skill is already installed in the selected agents."
  else
    echo "Nothing to uninstall: no managed links found in the selected agents."
  fi
else
  if [[ "$mode" == install ]]; then
    header="Install skills into: $agents_label"
    chosen="$(env -u GUM_CHOOSE_SELECTED gum choose --no-limit --selected='*' --label-delimiter='::' --header="$header" "${options[@]}")" || {
      echo "Skill selection cancelled; nothing changed." >&2
      exit 1
    }
  else
    header="Uninstall skills from: $agents_label"
    chosen="$(env -u GUM_CHOOSE_SELECTED gum choose --no-limit --label-delimiter='::' --header="$header" "${options[@]}")" || {
      echo "Skill selection cancelled; nothing changed." >&2
      exit 1
    }
  fi
  while IFS= read -r name; do
    [[ -n "$name" ]] && selected_names+=("$name")
  done <<< "$chosen"
fi

for name in "${selected_names[@]}"; do
  source="${source_by_name[$name]:-}"
  if [[ -z "$source" ]]; then
    echo "Skipping unknown skill '$name'." >&2
    continue
  fi
  for agent in "${selected_agents[@]}"; do
    install_root="$(agent_root "$agent")"
    destination="$install_root/$name"
    if [[ "$mode" == install ]]; then
      if is_installed "$agent" "$name"; then
        continue
      fi
      if [[ -e "$destination" || -L "$destination" ]]; then
        if gum confirm --affirmative='Overwrite' --negative='Keep' "Overwrite existing $agent skill '$name' at $destination?"; then
          rm -rf -- "$destination"
        else
          echo "$agent: keeping existing $destination" >&2
          continue
        fi
      fi
      mkdir -p "$install_root"
      if ln -s -- "$source" "$destination"; then
        echo "$agent: linked $name"
      else
        echo "$agent: could not link $name to $destination" >&2
      fi
    else
      if is_installed "$agent" "$name"; then
        rm -f -- "$destination"
        echo "$agent: unlinked $name"
      elif [[ -e "$destination" || -L "$destination" ]]; then
        echo "$agent: leaving unmanaged $destination" >&2
      fi
    fi
  done
done

yaml_quote() {
  local escaped
  escaped="$(printf '%s' "$1" | sed "s/'/''/g")"
  printf "'%s'" "$escaped"
}

generate_openai_yaml() {
  local skill_dir="$1"
  local name="$2"
  local description="$3"
  local yaml_file="$skill_dir/agents/openai.yaml"
  local display_name short_description temp_file

  if [[ -e "$yaml_file" || -L "$yaml_file" ]]; then
    [[ ! -L "$yaml_file" ]] && grep -Fqx '# Generated by setup.sh' "$yaml_file" || return 0
  fi

  display_name="$(printf '%s' "$name" | awk -F- '{ for (i = 1; i <= NF; i++) { $i = toupper(substr($i, 1, 1)) substr($i, 2) } OFS = " "; print }')"
  short_description="$description"
  if (( ${#short_description} > 64 )); then
    short_description="$(printf '%s' "$short_description" | cut -c 1-64)"
    short_description="${short_description% *}"
  fi

  mkdir -p "$skill_dir/agents"
  temp_file="$(mktemp "$skill_dir/agents/openai.yaml.XXXXXX")"
  {
    echo '# Generated by setup.sh'
    echo 'interface:'
    printf '  display_name: %s\n' "$(yaml_quote "$display_name")"
    printf '  short_description: %s\n' "$(yaml_quote "$short_description")"
  } > "$temp_file"
  mv "$temp_file" "$yaml_file"
}

for i in "${!all_names[@]}"; do
  name="${all_names[$i]}"
  source="${all_sources[$i]}"
  yaml_file="$source/agents/openai.yaml"
  if is_installed Codex "$name"; then
    generate_openai_yaml "$source" "$name" "${all_descriptions[$i]}"
  elif [[ -f "$yaml_file" && ! -L "$yaml_file" ]] && grep -Fqx '# Generated by setup.sh' "$yaml_file"; then
    rm -f -- "$yaml_file"
  fi
done

echo
echo "Skills missing from some agent folders:"
found_gap=false
for name in "${all_names[@]}"; do
  gaps=()
  for agent in "${agents[@]}"; do
    is_installed "$agent" "$name" || gaps+=("$agent")
  done
  if (( ${#gaps[@]} > 0 )); then
    printf '  %s: missing in %s\n' "$name" "$(join_by ', ' "${gaps[@]}")"
    found_gap=true
  fi
done
[[ "$found_gap" == true ]] || echo "  none — every skill is installed in all agents"

echo
echo "Installed skills not found in this repo:"
found_external=false
for agent in "${agents[@]}"; do
  install_root="$(agent_root "$agent")"
  [[ -d "$install_root" ]] || continue
  external_skills=()
  for installed_skill in "$install_root"/*; do
    [[ -f "$installed_skill/SKILL.md" ]] || continue
    installed_name="$(basename "$installed_skill")"
    found_in_repo=false
    [[ -n "${source_by_name[$installed_name]:-}" ]] && found_in_repo=true
    if [[ "$found_in_repo" == false ]]; then
      external_skills+=("$installed_name")
    fi
  done
  if (( ${#external_skills[@]} > 0 )); then
    printf '%s:\n' "$agent"
    printf '  - %s\n' "${external_skills[@]}"
    found_external=true
  fi
done
[[ "$found_external" == true ]] || echo "  none"
