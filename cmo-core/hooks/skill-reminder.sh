#!/bin/bash
# Skill-loading reminder — injected on every user prompt submission.
#
# Inspects the current branch's diff (committed + staged + unstaged) and emits
# a TARGETED list of skills to load, derived from the file types actually in
# play. This avoids the "load everything that might match" noise the old static
# reminder produced, and — more importantly — keeps the project-analyzer /
# code-reviewer agents aligned with the conventions skills (since the diff
# drives both sides).
#
# Falls back to a brief generic reminder when:
#   - the cwd is not a git repo, or
#   - the diff is empty (no changes yet — the user may be about to start coding).
#
# Compatible with the macOS system bash (3.2 — no associative arrays).

emit_generic() {
	cat <<'EOF'
<system-reminder>
You MUST load the appropriate skill(s) via the Skill tool BEFORE writing, reviewing, or modifying any code.

Invoke as: Skill(skill="<name>") — e.g., Skill(skill="git-operations").

Available skill families:
- coding-standards (universal — load alongside any language skill)
- testing-standards (universal — load alongside the stack's testing skill)
- git-operations (any git/GitHub operation)
- security-review (auth / input-validation audits)
- python-conventions
- dotnet-conventions, dotnet-testing
- vue-conventions, react-conventions, bootstrap-scss, cmo-design-system, ionic-capacitor, frontend-testing
- firmware-conventions

Load all that match the work you're about to do.
</system-reminder>
EOF
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	emit_generic
	exit 0
fi

# Resolve the default branch (best-effort).
default_branch=""
if remote_head=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); then
	default_branch=${remote_head#origin/}
fi
if [ -z "$default_branch" ]; then
	for candidate in main master; do
		if git show-ref --verify --quiet "refs/heads/$candidate"; then
			default_branch=$candidate
			break
		fi
	done
fi

# Collect changed files: commits ahead of base + staged + unstaged.
collect_changed() {
	if [ -n "$default_branch" ]; then
		git diff --name-only "$default_branch"...HEAD 2>/dev/null || true
	fi
	git diff --name-only 2>/dev/null || true
	git diff --name-only --staged 2>/dev/null || true
}
changed=$(collect_changed | sort -u | sed '/^$/d')

if [ -z "$changed" ]; then
	emit_generic
	exit 0
fi

# Repo signals — disambiguate .ts / .js (could be Vue or React) and detect
# add-on stacks (Ionic, design system).
has_vue_dep=0
has_react_dep=0
has_cmo_ds_dep=0
has_ionic_capacitor=0
if [ -f package.json ]; then
	grep -q '"vue"[[:space:]]*:' package.json 2>/dev/null && has_vue_dep=1
	grep -q '"react"[[:space:]]*:' package.json 2>/dev/null && has_react_dep=1
	grep -q 'cmo-internal-design-system' package.json 2>/dev/null && has_cmo_ds_dep=1
	grep -qE '"@(ionic|capacitor)/' package.json 2>/dev/null && has_ionic_capacitor=1
fi

# Skill list — space-padded string for cheap dedupe on bash 3.2.
skills_list=" "
add_skill() {
	case "$skills_list" in
		*" $1 "*) : ;;
		*) skills_list="$skills_list$1 " ;;
	esac
}

is_test_path() {
	case "$1" in
		*test_*.py|*_test.py) return 0 ;;
		*Tests.cs|*.Tests.cs|*.IntegrationTests.cs) return 0 ;;
		*.spec.ts|*.spec.tsx|*.test.ts|*.test.tsx|*.spec.js|*.test.js|*.spec.jsx|*.test.jsx) return 0 ;;
		tests/*|*/tests/*|__tests__/*|*/__tests__/*|test/*|*/test/*) return 0 ;;
		IntegrationTests/*|*/IntegrationTests/*) return 0 ;;
	esac
	return 1
}

has_code=0

while IFS= read -r f; do
	[ -z "$f" ] && continue

	# Test-path detection runs before extension mapping so we can layer
	# testing-standards on top of the stack-specific skill below.
	if is_test_path "$f"; then
		add_skill testing-standards
	fi

	case "$f" in
		*.py|pyproject.toml|requirements.txt|setup.cfg|setup.py|Pipfile|Pipfile.lock|poetry.lock)
			has_code=1
			add_skill python-conventions
			;;
		*.cs|*.csproj|*.sln|*.slnx|Directory.Build.props|Directory.Packages.props|global.json)
			has_code=1
			add_skill dotnet-conventions
			if is_test_path "$f"; then
				add_skill dotnet-testing
			fi
			;;
		*.vue)
			has_code=1
			add_skill vue-conventions
			[ "$has_ionic_capacitor" = "1" ] && add_skill ionic-capacitor
			[ "$has_cmo_ds_dep" = "1" ] && add_skill cmo-design-system
			;;
		*.tsx|*.jsx)
			has_code=1
			add_skill react-conventions
			[ "$has_ionic_capacitor" = "1" ] && add_skill ionic-capacitor
			[ "$has_cmo_ds_dep" = "1" ] && add_skill cmo-design-system
			if is_test_path "$f"; then
				add_skill frontend-testing
			fi
			;;
		*.ts|*.js|*.mjs|*.cjs)
			has_code=1
			if [ "$has_react_dep" = "1" ] && [ "$has_vue_dep" != "1" ]; then
				add_skill react-conventions
			elif [ "$has_vue_dep" = "1" ] && [ "$has_react_dep" != "1" ]; then
				add_skill vue-conventions
			fi
			[ "$has_ionic_capacitor" = "1" ] && add_skill ionic-capacitor
			[ "$has_cmo_ds_dep" = "1" ] && add_skill cmo-design-system
			if is_test_path "$f"; then
				add_skill frontend-testing
			fi
			;;
		*.scss|*.css)
			has_code=1
			add_skill bootstrap-scss
			[ "$has_cmo_ds_dep" = "1" ] && add_skill cmo-design-system
			;;
		*.c|*.h|*.cpp|*.hpp|*.ino|platformio.ini)
			has_code=1
			add_skill firmware-conventions
			;;
		CMakeLists.txt)
			# CMake exists in many ecosystems; only assume firmware when a
			# clearly-embedded marker is also present.
			if [ -f platformio.ini ] || grep -qE 'STM32|ESP-IDF|Zephyr|nRF|FreeRTOS' CMakeLists.txt 2>/dev/null; then
				has_code=1
				add_skill firmware-conventions
			fi
			;;
	esac
done <<EOF
$changed
EOF

# Universal pairings.
[ "$has_code" = "1" ] && add_skill coding-standards
# Any diff implies the user will eventually commit/push.
add_skill git-operations

# Render the ordered list (universal first, then stack-specific).
ordered_universal="coding-standards testing-standards git-operations security-review"
ordered_stack="python-conventions dotnet-conventions dotnet-testing vue-conventions react-conventions bootstrap-scss cmo-design-system ionic-capacitor frontend-testing firmware-conventions"

emit_list() {
	for s in $1; do
		case "$skills_list" in
			*" $s "*) printf -- "- %s\n" "$s" ;;
		esac
	done
}

{
	echo "<system-reminder>"
	echo "Skill-loading guidance — derived from changed files on this branch."
	echo ""
	echo "Before writing, reviewing, or modifying code, load these skills via the Skill tool:"
	echo ""
	emit_list "$ordered_universal"
	emit_list "$ordered_stack"
	echo ""
	echo "Invoke as: Skill(skill=\"<name>\")."
	echo ""
	echo "If your next action needs a skill not on this list (e.g., security-review for an auth audit), load that one too."
	echo "</system-reminder>"
}
