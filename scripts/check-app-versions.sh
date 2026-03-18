#!/usr/bin/env bash
# Check if catalog apps have newer versions available at their source.
#
# Outputs both Helm chart version and app version (from Chart.yaml appVersion).
# These can differ: e.g. mlflow chart 1.8.1 deploys MLflow app 3.7.0.
#
# Supports:
#   - Helm repo apps (from .catalog-source.yaml with helmrepo + helmrepoUrl)
#   - OCI apps (from helmrelease url; requires 'crane' for OCI registry)
#
# Usage:
#   ./scripts/check-app-versions.sh [--json] [--app NAME]
#
# Options:
#   --json    Output as JSON
#   --app N   Check only app N
#
# Requires: helm (for Helm repo apps), crane (optional, for OCI apps), curl (for GitHub fallback)
#
# When Chart.yaml has no appVersion (e.g. kagent), app version is fetched from
# GitHub releases API. Set GITHUB_TOKEN to avoid rate limits (60/hr unauthenticated).

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

JSON_OUTPUT=false
APP_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    JSON_OUTPUT=true
    shift
    ;;
  --app)
    APP_FILTER="$2"
    shift 2
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

# Normalize version for comparison (strip 'v' prefix)
normalize_version() {
  local v="$1"
  v="${v#v}"
  echo "$v"
}

# Compare two versions; output 0 if v1 < v2, 1 if v1 >= v2
version_lt() {
  local v1 v2
  v1=$(normalize_version "$1")
  v2=$(normalize_version "$2")
  local lower
  lower=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -1)
  [[ $v1 == "$lower" ]] && [[ $v1 != "$v2" ]]
}

# Normalize version string for sorting (strip 'v' prefix)
normalize_for_sort() {
  sed 's/^v//'
}

# Get latest stable version from a list (prefer non-prerelease)
latest_stable() {
  local versions="$1"
  echo "$versions" | grep -v -E -- '-(alpha|beta|rc|dev)' | normalize_for_sort | sort -V | tail -1
}

# Get latest version (including prerelease)
latest_any() {
  local versions="$1"
  echo "$versions" | normalize_for_sort | sort -V | tail -1
}

# Discover catalog apps and their current versions
# Output: app_name version (one per line, per app's latest catalog version)
get_catalog_versions() {
  local app_filter="$1"
  for app_dir in applications/*/; do
    [[ -d $app_dir ]] || continue
    local app
    app=$(basename "$app_dir")
    [[ -n $app_filter && $app != "$app_filter" ]] && continue

    local latest_ver=""
    for ver_dir in "$app_dir"*/; do
      [[ -d $ver_dir ]] || continue
      local has_helmrelease=false
      [[ -f "${ver_dir}helmrelease.yaml" ]] && has_helmrelease=true
      [[ -f "${ver_dir}helmrelease/helmrelease.yaml" ]] && has_helmrelease=true
      if [[ -d "${ver_dir}helmrelease" ]]; then
        for f in "${ver_dir}helmrelease/"*.yaml; do
          [[ -f $f ]] && {
            has_helmrelease=true
            break
          }
        done
      fi
      [[ $has_helmrelease == true ]] || continue
      local ver
      ver=$(basename "$ver_dir")
      if [[ -z $latest_ver ]] || version_lt "$latest_ver" "$ver"; then
        latest_ver="$ver"
      fi
    done
    [[ -n $latest_ver ]] && echo "$app $latest_ver"
  done
}

# Get latest chart version and app version from Helm repo
# Args: repo_name chart_name repo_url
# Output: chart_version|app_version (or empty)
helm_repo_latest() {
  local repo_name="$1"
  local chart_name="$2"
  local repo_url="$3"
  helm repo add "$repo_name" "$repo_url" &>/dev/null || true
  helm repo update "$repo_name" &>/dev/null || true
  local table
  table=$(helm search repo "$repo_name/$chart_name" --versions 2>/dev/null | tail -n +2)
  if [[ -z $table ]]; then
    echo ""
    return 1
  fi
  local versions
  versions=$(echo "$table" | awk '{print $2}')
  local chart_ver
  chart_ver=$(echo "$versions" | grep -v -E -- '-(alpha|beta|rc|dev)' | normalize_for_sort | sort -V | tail -1)
  [[ -z $chart_ver ]] && chart_ver=$(echo "$versions" | normalize_for_sort | sort -V | tail -1)
  if [[ -z $chart_ver ]]; then
    echo ""
    return 1
  fi
  local app_ver
  app_ver=$(echo "$table" | awk -v cv="$chart_ver" '$2==cv {print $3; exit}')
  echo "${chart_ver}|${app_ver:-}"
}

# Get latest chart version and app version from OCI registry (requires crane, helm)
# Args: oci_ref (e.g. ghcr.io/kagent-dev/kagent/helm/kagent), app_name (optional, for GitHub fallback)
# Output: chart_version|app_version (chart_version may have v prefix if that's the OCI tag)
oci_registry_latest() {
  local oci_ref="$1"
  local app_name="${2:-}"
  oci_ref="${oci_ref#oci://}"
  if ! command -v crane &>/dev/null; then
    echo ""
    return 1
  fi
  local tags
  tags=$(crane ls "$oci_ref" 2>/dev/null) || return 1
  if [[ -z $tags ]]; then
    echo ""
    return 1
  fi
  # Find latest: pair normalized|original, sort by normalized, take original from last
  local chart_ver
  chart_ver=$(echo "$tags" | grep -v -E -- '-(alpha|beta|rc|dev)' | while read -r t; do printf '%s|%s\n' "$(echo "$t" | normalize_for_sort)" "$t"; done | sort -t'|' -k1 -V | tail -1 | cut -d'|' -f2)
  [[ -z $chart_ver ]] && chart_ver=$(echo "$tags" | while read -r t; do printf '%s|%s\n' "$(echo "$t" | normalize_for_sort)" "$t"; done | sort -t'|' -k1 -V | tail -1 | cut -d'|' -f2)
  if [[ -z $chart_ver ]]; then
    echo ""
    return 1
  fi
  local app_ver=""
  if command -v helm &>/dev/null; then
    app_ver=$(helm show chart "oci://$oci_ref" --version "$chart_ver" 2>/dev/null | grep -E '^appVersion:' | sed 's/appVersion:[[:space:]]*//;s/[[:space:]]*$//' || true)
  fi
  # Fallback: fetch app version from GitHub releases API when Chart.yaml has no appVersion
  if [[ -z $app_ver && -n $app_name ]] && command -v curl &>/dev/null; then
    local github_repo
    github_repo=$(get_github_repo_for_app "$app_name")
    if [[ -n $github_repo ]]; then
      app_ver=$(github_release_app_version "$github_repo" "$chart_ver" 2>/dev/null) || true
    fi
  fi
  echo "${chart_ver}|${app_ver:-}"
}

# Map app name to GitHub repo (owner/repo) for OCI apps without appVersion in Chart.yaml
# Used to fetch app version from GitHub releases API
get_github_repo_for_app() {
  case "$1" in
  kagent) echo "kagent-dev/kagent" ;;
  agentgateway) echo "kgateway-dev/kgateway" ;; # Helm chart lives in kgateway repo
  kserve) echo "kserve/kserve" ;;
  *) echo "" ;;
  esac
}

# Get app version from GitHub releases API when Chart.yaml has no appVersion
# Args: owner/repo, chart_version (e.g. 0.7.23 or v0.7.23)
# Output: release tag_name if found (e.g. v0.7.23), empty otherwise
github_release_app_version() {
  local repo="$1"
  local chart_ver="$2"
  [[ -z $repo ]] && return 1
  local url="https://api.github.com/repos/${repo}/releases?per_page=100"
  local auth=""
  [[ -n ${GITHUB_TOKEN:-} ]] && auth="Authorization: Bearer ${GITHUB_TOKEN}"
  local releases
  releases=$(curl -sL -f ${auth:+-H "$auth"} "$url" 2>/dev/null) || return 1
  local chart_norm
  chart_norm=$(echo "$chart_ver" | normalize_for_sort)
  local tag=""
  while read -r t; do
    [[ -z $t ]] && continue
    local tnorm
    tnorm=$(echo "$t" | normalize_for_sort)
    if [[ $tnorm == "$chart_norm" ]]; then
      tag="$t"
      break
    fi
  done < <(echo "$releases" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"\([^"]*\)"$/\1/')
  echo "${tag:-}"
}

# Get app version for a specific chart version from Helm repo
# Args: repo_name chart_name repo_url chart_version
get_helm_catalog_app_version() {
  local repo_name="$1" chart_name="$2" repo_url="$3" chart_ver="$4"
  helm repo add "$repo_name" "$repo_url" &>/dev/null || true
  helm repo update "$repo_name" &>/dev/null || true
  helm search repo "$repo_name/$chart_name" --version "$chart_ver" 2>/dev/null | tail -n +2 | awk -v cv="$chart_ver" '$2==cv {print $3; exit}'
}

# Get app version for a specific chart version from OCI (helm show chart, then GitHub fallback)
# Args: oci_ref app_name chart_version
get_oci_catalog_app_version() {
  local oci_ref="$1" app_name="$2" chart_ver="$3"
  oci_ref="${oci_ref#oci://}"
  local app_ver=""
  if command -v helm &>/dev/null; then
    app_ver=$(helm show chart "oci://$oci_ref" --version "$chart_ver" 2>/dev/null | grep -E '^appVersion:' | sed 's/appVersion:[[:space:]]*//;s/[[:space:]]*$//' || true)
  fi
  if [[ -z $app_ver && -n $app_name ]] && command -v curl &>/dev/null; then
    local github_repo
    github_repo=$(get_github_repo_for_app "$app_name")
    if [[ -n $github_repo ]]; then
      app_ver=$(github_release_app_version "$github_repo" "$chart_ver" 2>/dev/null) || true
    fi
  fi
  echo "${app_ver:-}"
}

# Parse .catalog-source.yaml (simple YAML)
get_helmrepo_from_catalog_source() {
  local app="$1"
  local file="applications/$app/.catalog-source.yaml"
  [[ -f $file ]] || return 1
  local helmrepo helmrepo_url
  helmrepo=$(grep -E '^helmrepo:' "$file" | sed 's/helmrepo:[[:space:]]*//;s/[[:space:]]*$//')
  helmrepo_url=$(grep -E '^helmrepoUrl:' "$file" | sed 's/helmrepoUrl:[[:space:]]*//;s/[[:space:]]*$//')
  [[ -n $helmrepo && -n $helmrepo_url ]] || return 1
  echo "${helmrepo}|${helmrepo_url}"
}

# Get OCI URL from helmrelease for apps without .catalog-source helmrepo
get_oci_url_from_helmrelease() {
  local app="$1"
  local ver="$2"
  local dir="applications/$app/$ver/helmrelease"
  [[ -d $dir ]] || return 1
  local url
  url=$(grep -h -E '^[[:space:]]*url:[[:space:]]*oci://' "$dir"/*.yaml 2>/dev/null | head -1 | sed 's/.*oci:\/\///;s/[[:space:]]*$//')
  [[ -n $url ]] || return 1
  echo "$url"
}

# Check if app uses our OCI (nutanix-cloud-native/charts) - those come from helm repo, not upstream OCI
is_internal_oci() {
  local url="$1"
  [[ $url == *"nutanix-cloud-native"* ]] || [[ $url == *"deepak-muley"* ]]
}

declare -a RESULTS

run_check() {
  local app_filter="$1"
  local catalog
  catalog=$(get_catalog_versions "$app_filter")

  while read -r app catalog_ver; do
    [[ -n $app ]] || continue
    local latest="" source_type="" catalog_app_ver=""

    # Try Helm repo first (from .catalog-source.yaml)
    local helmrepo_info
    helmrepo_info=$(get_helmrepo_from_catalog_source "$app" 2>/dev/null) || true
    if [[ -n $helmrepo_info ]]; then
      local repo_name chart_name repo_url
      # Format: repo_name/chart_name|repo_url
      repo_name="${helmrepo_info%%/*}"
      chart_name="${helmrepo_info#*/}"
      chart_name="${chart_name%%|*}"
      repo_url="${helmrepo_info#*|}"
      latest=$(helm_repo_latest "$repo_name" "$chart_name" "$repo_url" 2>/dev/null) || true
      catalog_app_ver=$(get_helm_catalog_app_version "$repo_name" "$chart_name" "$repo_url" "$catalog_ver" 2>/dev/null) || true
      source_type="helm"
    fi

    # If no helmrepo, try OCI from helmrelease (upstream OCI only)
    local oci_url=""
    if [[ -z $latest ]]; then
      oci_url=$(get_oci_url_from_helmrelease "$app" "$catalog_ver" 2>/dev/null) || true
      if [[ -n $oci_url ]] && ! is_internal_oci "$oci_url"; then
        latest=$(oci_registry_latest "$oci_url" "$app" 2>/dev/null) || true
        catalog_app_ver=$(get_oci_catalog_app_version "$oci_url" "$app" "$catalog_ver" 2>/dev/null) || true
        source_type="oci"
      fi
    fi

    local latest_chart="" latest_app=""
    if [[ -n $latest ]] && [[ $latest == *"|"* ]]; then
      latest_chart="${latest%%|*}"
      latest_app="${latest#*|}"
    elif [[ -n $latest ]]; then
      latest_chart="$latest"
    fi

    local status="unknown"
    if [[ -n $latest_chart ]]; then
      if version_lt "$catalog_ver" "$latest_chart"; then
        status="update_available"
      else
        status="up_to_date"
      fi
    fi

    RESULTS+=("$app|$catalog_ver|$catalog_app_ver|$latest_chart|$latest_app|$status|$source_type")
  done <<<"$catalog"
}

run_check "$APP_FILTER"

# Output
if [[ $JSON_OUTPUT == true ]]; then
  echo "["
  for i in "${!RESULTS[@]}"; do
    IFS='|' read -r app catalog_ver catalog_app_ver latest_chart latest_app status source_type <<<"${RESULTS[$i]}"
    [[ $i -gt 0 ]] && echo ","
    echo -n "  {\"app\":\"$app\",\"catalogChartVersion\":\"$catalog_ver\",\"catalogAppVersion\":\"${catalog_app_ver:-}\",\"latestChartVersion\":\"${latest_chart:-}\",\"latestAppVersion\":\"${latest_app:-}\",\"status\":\"$status\",\"sourceType\":\"${source_type:-}\"}"
  done
  echo ""
  echo "]"
else
  {
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "APP" "CATALOG" "CURR_APP" "LATEST_CHART" "LATEST_APP" "STATUS" "SOURCE"
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "---" "------" "-------" "-----------" "----------" "------" "------"
    for r in "${RESULTS[@]}"; do
      IFS='|' read -r app catalog_ver catalog_app_ver latest_chart latest_app status source_type <<<"$r"
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$app" "$catalog_ver" "${catalog_app_ver:--}" "${latest_chart:--}" "${latest_app:--}" "$status" "${source_type:-}"
    done
  } | column -t -s $'\t'
fi
