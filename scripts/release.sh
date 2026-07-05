#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PORTS_MAKEFILE="${ROOT_DIR}/ports/www/adguardhome/Makefile"
PLUGIN_MAKEFILE="${ROOT_DIR}/dns/adguardhome/Makefile"

prog_name=$(basename "$0")

usage() {
    cat <<USAGE
Usage:
  ${prog_name} show
  ${prog_name} tag
  ${prog_name} assert-tag <tag>
  ${prog_name} set-adguardhome <distversion> [portrevision]
  ${prog_name} bump-adguardhome-revision
  ${prog_name} set-plugin <plugin_version> [plugin_revision]
  ${prog_name} bump-plugin-revision
  ${prog_name} create-tag [--push] [--message <text>]
  ${prog_name} create-gh-release [--draft] [--prerelease] [--notes <text> | --notes-file <path>] [--title <text>] [--target <ref>]

Notes:
  - Release tag format is: rel/adguardhome-v<ADGUARDHOME_PKGVER>+os-adguardhome-v<PLUGIN_PKGVER>
  - ADGUARDHOME_PKGVER is DISTVERSION plus _PORTREVISION when PORTREVISION > 0.
  - PLUGIN_PKGVER is PLUGIN_VERSION plus _PLUGIN_REVISION when PLUGIN_REVISION > 0.
USAGE
}

die() {
    echo "error: $*" >&2
    exit 1
}

validate_token() {
    value=$1
    label=$2
    if [ -z "$value" ]; then
        die "${label} must not be empty"
    fi
    case "$value" in
        *[[:space:]]*)
            die "${label} must not contain whitespace"
            ;;
    esac
}

normalize_nonneg_int() {
    value=$1
    label=$2

    if [ -z "$value" ]; then
        value=0
    fi

    case "$value" in
        *[!0-9]*)
            die "${label} must be a non-negative integer"
            ;;
    esac

    # Strip leading zeros while keeping 0 stable.
    value=$(printf '%s' "$value" | sed -E 's/^0+//')
    if [ -z "$value" ]; then
        value=0
    fi
    printf '%s\n' "$value"
}

read_make_var() {
    file=$1
    key=$2

    awk -v key="$key" '
        {
            line = $0
            sub(/#.*/, "", line)
            if (line ~ "^[[:space:]]*" key "[[:space:]]*\\??=[[:space:]]*") {
                sub("^[[:space:]]*" key "[[:space:]]*\\??=[[:space:]]*", "", line)
                gsub(/[[:space:]]+$/, "", line)
                print line
                exit
            }
        }
    ' "$file"
}

set_make_var() {
    file=$1
    key=$2
    value=$3

    tmp_file=$(mktemp "${TMPDIR:-/tmp}/release-sh.XXXXXX")

    if ! awk -v key="$key" -v value="$value" '
        BEGIN {
            updated = 0
        }
        {
            if ($0 ~ "^[[:space:]]*" key "[[:space:]]*\\??=") {
                print key "=\t\t" value
                updated = 1
                next
            }
            print
        }
        END {
            if (!updated) {
                exit 7
            }
        }
    ' "$file" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$file"
}

insert_make_var_after() {
    file=$1
    after_key=$2
    key=$3
    value=$4

    tmp_file=$(mktemp "${TMPDIR:-/tmp}/release-sh.XXXXXX")

    if ! awk -v after_key="$after_key" -v key="$key" -v value="$value" '
        BEGIN {
            inserted = 0
        }
        {
            print
            if (!inserted && $0 ~ "^[[:space:]]*" after_key "[[:space:]]*\\??=") {
                print key "=\t\t" value
                inserted = 1
            }
        }
        END {
            if (!inserted) {
                exit 8
            }
        }
    ' "$file" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$file"
}

remove_make_var() {
    file=$1
    key=$2

    tmp_file=$(mktemp "${TMPDIR:-/tmp}/release-sh.XXXXXX")

    awk -v key="$key" '
        $0 !~ "^[[:space:]]*" key "[[:space:]]*\\??=" {
            print
        }
    ' "$file" > "$tmp_file"

    mv "$tmp_file" "$file"
}

upsert_make_var() {
    file=$1
    key=$2
    value=$3
    after_key=$4

    if [ -n "$(read_make_var "$file" "$key")" ]; then
        set_make_var "$file" "$key" "$value" || die "failed to set ${key} in ${file}"
    else
        insert_make_var_after "$file" "$after_key" "$key" "$value" || die "failed to insert ${key} in ${file}"
    fi
}

adguardhome_distversion() {
    value=$(read_make_var "$PORTS_MAKEFILE" "DISTVERSION")
    validate_token "$value" "DISTVERSION"
    printf '%s\n' "$value"
}

adguardhome_portrevision() {
    value=$(read_make_var "$PORTS_MAKEFILE" "PORTREVISION")
    normalize_nonneg_int "$value" "PORTREVISION"
}

plugin_version() {
    value=$(read_make_var "$PLUGIN_MAKEFILE" "PLUGIN_VERSION")
    validate_token "$value" "PLUGIN_VERSION"
    printf '%s\n' "$value"
}

plugin_revision() {
    value=$(read_make_var "$PLUGIN_MAKEFILE" "PLUGIN_REVISION")
    normalize_nonneg_int "$value" "PLUGIN_REVISION"
}

pkg_version() {
    base=$1
    revision=$2

    if [ "$revision" -gt 0 ]; then
        printf '%s_%s\n' "$base" "$revision"
        return
    fi

    printf '%s\n' "$base"
}

adguardhome_pkg_version() {
    pkg_version "$(adguardhome_distversion)" "$(adguardhome_portrevision)"
}

plugin_pkg_version() {
    pkg_version "$(plugin_version)" "$(plugin_revision)"
}

release_tag() {
    printf 'rel/adguardhome-v%s+os-adguardhome-v%s\n' "$(adguardhome_pkg_version)" "$(plugin_pkg_version)"
}

ensure_clean_git_tree() {
    git diff --quiet || die "working tree has unstaged changes"
    git diff --cached --quiet || die "index has staged changes"
}

cmd_show() {
    echo "adguardhome DISTVERSION: $(adguardhome_distversion)"
    echo "adguardhome PORTREVISION: $(adguardhome_portrevision)"
    echo "adguardhome package version: $(adguardhome_pkg_version)"
    echo "os-adguardhome PLUGIN_VERSION: $(plugin_version)"
    echo "os-adguardhome PLUGIN_REVISION: $(plugin_revision)"
    echo "os-adguardhome package version: $(plugin_pkg_version)"
    echo "release tag: $(release_tag)"
}

cmd_tag() {
    release_tag
}

cmd_assert_tag() {
    [ $# -eq 1 ] || die "assert-tag expects exactly one argument"

    actual=$1
    expected=$(release_tag)

    if [ "$actual" != "$expected" ]; then
        die "tag mismatch: got '${actual}', expected '${expected}'"
    fi

    echo "tag is valid: ${actual}"
}

cmd_set_adguardhome() {
    [ $# -ge 1 ] && [ $# -le 2 ] || die "set-adguardhome expects: <distversion> [portrevision]"

    new_distversion=$1
    new_portrevision=${2:-0}

    validate_token "$new_distversion" "DISTVERSION"
    new_portrevision=$(normalize_nonneg_int "$new_portrevision" "PORTREVISION")

    set_make_var "$PORTS_MAKEFILE" "DISTVERSION" "$new_distversion" || die "failed to update DISTVERSION"

    if [ "$new_portrevision" -eq 0 ]; then
        remove_make_var "$PORTS_MAKEFILE" "PORTREVISION"
    else
        upsert_make_var "$PORTS_MAKEFILE" "PORTREVISION" "$new_portrevision" "DISTVERSION"
    fi

    echo "NOTE: update ports/www/adguardhome/distinfo to match the new version" >&2
    echo "      (run 'make -C ports/www/adguardhome makesum' on FreeBSD)." >&2

    cmd_show
}

cmd_bump_adguardhome_revision() {
    [ $# -eq 0 ] || die "bump-adguardhome-revision takes no arguments"

    current=$(adguardhome_portrevision)
    next=$((current + 1))

    upsert_make_var "$PORTS_MAKEFILE" "PORTREVISION" "$next" "DISTVERSION"

    echo "bumped PORTREVISION: ${current} -> ${next}"
    cmd_show
}

cmd_set_plugin() {
    [ $# -ge 1 ] && [ $# -le 2 ] || die "set-plugin expects: <plugin_version> [plugin_revision]"

    new_plugin_version=$1
    new_plugin_revision=${2:-0}

    validate_token "$new_plugin_version" "PLUGIN_VERSION"
    new_plugin_revision=$(normalize_nonneg_int "$new_plugin_revision" "PLUGIN_REVISION")

    set_make_var "$PLUGIN_MAKEFILE" "PLUGIN_VERSION" "$new_plugin_version" || die "failed to update PLUGIN_VERSION"
    upsert_make_var "$PLUGIN_MAKEFILE" "PLUGIN_REVISION" "$new_plugin_revision" "PLUGIN_VERSION"

    cmd_show
}

cmd_bump_plugin_revision() {
    [ $# -eq 0 ] || die "bump-plugin-revision takes no arguments"

    current=$(plugin_revision)
    next=$((current + 1))

    upsert_make_var "$PLUGIN_MAKEFILE" "PLUGIN_REVISION" "$next" "PLUGIN_VERSION"

    echo "bumped PLUGIN_REVISION: ${current} -> ${next}"
    cmd_show
}

cmd_create_tag() {
    push_tag=false
    message=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --push)
                push_tag=true
                ;;
            --message)
                shift
                [ $# -gt 0 ] || die "--message expects a value"
                message=$1
                ;;
            *)
                die "unknown option for create-tag: $1"
                ;;
        esac
        shift
    done

    ensure_clean_git_tree

    tag=$(release_tag)

    if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1; then
        die "tag already exists locally: ${tag}"
    fi

    if [ -z "$message" ]; then
        message="Release ${tag}"
    fi

    git tag -a "$tag" -m "$message"
    echo "created local tag: ${tag}"

    if [ "$push_tag" = true ]; then
        git push origin "$tag"
        echo "pushed tag: ${tag}"
    fi
}

cmd_create_gh_release() {
    draft=false
    prerelease=false
    notes_text=""
    notes_file=""
    title=""
    target_ref=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --draft)
                draft=true
                ;;
            --prerelease)
                prerelease=true
                ;;
            --notes)
                shift
                [ $# -gt 0 ] || die "--notes expects a value"
                notes_text=$1
                ;;
            --notes-file)
                shift
                [ $# -gt 0 ] || die "--notes-file expects a value"
                notes_file=$1
                ;;
            --title)
                shift
                [ $# -gt 0 ] || die "--title expects a value"
                title=$1
                ;;
            --target)
                shift
                [ $# -gt 0 ] || die "--target expects a value"
                target_ref=$1
                ;;
            *)
                die "unknown option for create-gh-release: $1"
                ;;
        esac
        shift
    done

    [ -z "$notes_text" ] || [ -z "$notes_file" ] || die "use either --notes or --notes-file, not both"

    command -v gh >/dev/null 2>&1 || die "gh CLI is required for create-gh-release"
    ensure_clean_git_tree

    tag=$(release_tag)

    if [ -z "$title" ]; then
        title=$tag
    fi

    if [ -z "$target_ref" ]; then
        target_ref=$(git rev-parse HEAD)
    fi

    set -- release create "$tag" --title "$title" --target "$target_ref"

    if [ "$draft" = true ]; then
        set -- "$@" --draft
    fi
    if [ "$prerelease" = true ]; then
        set -- "$@" --prerelease
    fi

    if [ -n "$notes_text" ]; then
        set -- "$@" --notes "$notes_text"
    elif [ -n "$notes_file" ]; then
        set -- "$@" --notes-file "$notes_file"
    else
        set -- "$@" --generate-notes
    fi

    echo "running: gh $*"
    gh "$@"
}

main() {
    [ $# -gt 0 ] || {
        usage
        exit 1
    }

    cmd=$1
    shift

    case "$cmd" in
        show)
            cmd_show "$@"
            ;;
        tag)
            cmd_tag "$@"
            ;;
        assert-tag)
            cmd_assert_tag "$@"
            ;;
        set-adguardhome)
            cmd_set_adguardhome "$@"
            ;;
        bump-adguardhome-revision)
            cmd_bump_adguardhome_revision "$@"
            ;;
        set-plugin)
            cmd_set_plugin "$@"
            ;;
        bump-plugin-revision)
            cmd_bump_plugin_revision "$@"
            ;;
        create-tag)
            cmd_create_tag "$@"
            ;;
        create-gh-release)
            cmd_create_gh_release "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            die "unknown command: ${cmd}"
            ;;
    esac
}

main "$@"
