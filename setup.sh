#!/usr/bin/env bash
set -eo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
skills_root="$repo_root/skills"

if ! command -v gum >/dev/null 2>&1; then
  echo "gum is required. Install it from https://github.com/charmbracelet/gum and rerun setup.sh." >&2
  exit 1
fi
if ! gum choose --help 2>&1 | grep -- '--selected' >/dev/null; then
  echo "gum 0.7 or newer is required for preselected choices." >&2
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

group_names=()
all_skill_dirs=()
all_groups=()
all_sources=()
all_names=()
all_descriptions=()

for group_dir in "$skills_root"/*/; do
  [[ -d "$group_dir" ]] || continue
  group="$(basename "$group_dir")"
  group_has_skills=false
  for skill_dir in "$group_dir"*/; do
    skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    skill_dir="${skill_dir%/}"
    all_skill_dirs+=("$skill_dir")
    metadata="$(skill_metadata "$skill_file")"
    IFS=$'\t' read -r name description <<< "$metadata"
    if [[ -z "$name" || -z "$description" || ! "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
      echo "Skipping $skill_file: valid name and description frontmatter are required." >&2
      continue
    fi
    for existing_name in "${all_names[@]}"; do
      if [[ "$existing_name" == "$name" ]]; then
        echo "Duplicate skill name '$name'; skill names must be unique across groups." >&2
        exit 1
      fi
    done
    if [[ "$group_has_skills" == false ]]; then
      group_names+=("$group")
      group_has_skills=true
    fi
    all_groups+=("$group")
    all_sources+=("$skill_dir")
    all_names+=("$name")
    all_descriptions+=("$description")
  done
done

if (( ${#all_sources[@]} == 0 )); then
  echo "No usable skills found under $skills_root." >&2
  exit 1
fi

agent_selection="$(gum choose --no-limit --selected='*' --header='Select coding agents' "${agents[@]}")" || {
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

is_linked_to_source_for_selected_agents() {
  local source="$1"
  local name="$2"
  local agent destination
  for agent in "${selected_agents[@]}"; do
    destination="$(agent_root "$agent")/$name"
    if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
      return 0
    fi
  done
  return 1
}

selected_sources=()
selected_names=()
selected_descriptions=()
for group in "${group_names[@]}"; do
  labels=()
  indices=()
  preselected_labels=()
  for i in "${!all_names[@]}"; do
    if [[ "${all_groups[$i]}" == "$group" ]]; then
      label="${all_names[$i]} — ${all_descriptions[$i]}"
      labels+=("$label")
      indices+=("$i")
      if is_linked_to_source_for_selected_agents "${all_sources[$i]}" "${all_names[$i]}"; then
        preselected_labels+=("$label")
      fi
    fi
  done
  (( ${#labels[@]} > 0 )) || continue
  selection_args=()
  for label in "${preselected_labels[@]}"; do
    selection_args+=(--selected "$label")
  done
  selection="$(GUM_CHOOSE_SELECTED= gum choose --no-limit --header="skills/$group" "${selection_args[@]}" "${labels[@]}")" || {
    echo "Skill selection cancelled; nothing changed." >&2
    exit 1
  }
  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    for j in "${!labels[@]}"; do
      if [[ "${labels[$j]}" == "$label" ]]; then
        index="${indices[$j]}"
        selected_sources+=("${all_sources[$index]}")
        selected_names+=("${all_names[$index]}")
        selected_descriptions+=("${all_descriptions[$index]}")
        break
      fi
    done
  done <<< "$selection"
done

if (( ${#selected_sources[@]} == 0 )); then
  echo "No skills selected; existing installations were left unchanged."
  exit 0
fi

is_known_install_path() {
  local candidate="$1"
  local agent root
  for agent in "${agents[@]}"; do
    root="$(agent_root "$agent")"
    case "$candidate" in
      "$root"/*) return 0 ;;
    esac
  done
  return 1
}

repo_key="$(printf '%s' "$repo_root" | cksum | awk '{print $1}')"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/personal-skills"
mkdir -p "$state_dir"
state_file="$state_dir/$repo_key.links"
next_state_file="$(mktemp "$state_dir/$repo_key.links.XXXXXX")"

desired_source_for_path() {
  local candidate="$1"
  local agent root i
  for agent in "${selected_agents[@]}"; do
    root="$(agent_root "$agent")"
    for i in "${!selected_sources[@]}"; do
      if [[ "$candidate" == "$root/${selected_names[$i]}" ]]; then
        printf '%s' "${selected_sources[$i]}"
        return 0
      fi
    done
  done
  return 1
}

is_managed_link_path() {
  local candidate="$1"
  local record_type path link_target
  [[ -f "$state_file" ]] || return 1
  while IFS=$'\t' read -r record_type path; do
    [[ "$record_type" == link && "$path" == "$candidate" && -L "$path" ]] || continue
    link_target="$(readlink "$path")"
    case "$link_target" in
      "$skills_root"/*) return 0 ;;
    esac
  done < "$state_file"
  return 1
}

approved_overwrites=()
for agent in "${selected_agents[@]}"; do
  install_root="$(agent_root "$agent")"
  for i in "${!selected_sources[@]}"; do
    destination="$install_root/${selected_names[$i]}"
    [[ -e "$destination" || -L "$destination" ]] || continue
    if [[ -L "$destination" && "$(readlink "$destination")" == "${selected_sources[$i]}" ]]; then
      continue
    fi
    if is_managed_link_path "$destination"; then
      continue
    fi
    if gum confirm --affirmative='Overwrite' --negative='Keep' "Overwrite existing $agent skill '${selected_names[$i]}' at $destination?"; then
      approved_overwrites+=("$destination")
    fi
  done
done

is_overwrite_approved() {
  local candidate="$1"
  local approved
  for approved in "${approved_overwrites[@]}"; do
    [[ "$approved" == "$candidate" ]] && return 0
  done
  return 1
}

if [[ -f "$state_file" ]]; then
  while IFS=$'\t' read -r record_type path; do
    [[ "$record_type" == link && -n "$path" ]] || continue
    is_known_install_path "$path" || continue
    [[ -L "$path" ]] || continue
    link_target="$(readlink "$path")"
    case "$link_target" in
      "$skills_root"/*)
        if desired_source="$(desired_source_for_path "$path")" && [[ "$desired_source" == "$link_target" ]]; then
          printf 'link\t%s\n' "$path" >> "$next_state_file"
        else
          rm -f "$path"
        fi
        ;;
    esac
  done < "$state_file"
fi
mv "$next_state_file" "$state_file"

codex_selected=false
for agent in "${selected_agents[@]}"; do
  [[ "$agent" == Codex ]] && codex_selected=true
done

is_selected_source() {
  local source="$1"
  local selected
  for selected in "${selected_sources[@]}"; do
    [[ "$selected" == "$source" ]] && return 0
  done
  return 1
}

for skill_dir in "${all_skill_dirs[@]}"; do
  yaml_file="$skill_dir/agents/openai.yaml"
  [[ -f "$yaml_file" && ! -L "$yaml_file" ]] || continue
  grep -Fqx '# Generated by setup.sh' "$yaml_file" || continue
  if [[ "$codex_selected" == false ]] || ! is_selected_source "$skill_dir"; then
    rm -f "$yaml_file"
  fi
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

if [[ "$codex_selected" == true ]]; then
  for i in "${!selected_sources[@]}"; do
    generate_openai_yaml "${selected_sources[$i]}" "${selected_names[$i]}" "${selected_descriptions[$i]}"
  done
fi

for agent in "${selected_agents[@]}"; do
  install_root="$(agent_root "$agent")"
  mkdir -p "$install_root"
  for i in "${!selected_sources[@]}"; do
    source="${selected_sources[$i]}"
    name="${selected_names[$i]}"
    destination="$install_root/$name"
    if [[ -e "$destination" || -L "$destination" ]]; then
      if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
        continue
      elif is_overwrite_approved "$destination"; then
        rm -rf "$destination"
      else
        echo "$agent: keeping existing $destination" >&2
        continue
      fi
    fi
    if ln -s "$source" "$destination"; then
      printf 'link\t%s\n' "$destination" >> "$state_file"
    else
      echo "$agent: could not link $name to $destination" >&2
    fi
  done
done

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
    for name in "${all_names[@]}"; do
      [[ "$name" == "$installed_name" ]] && found_in_repo=true
    done
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
