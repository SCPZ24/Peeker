#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

search_sources() {
  local pattern="$1"
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$@"
  else
    grep -EnR "$pattern" "$@"
  fi
}

swift package dump-package | ruby -rjson -e '
  package = JSON.parse(STDIN.read)
  targets = package.fetch("targets").to_h { |target| [target.fetch("name"), target] }
  framework_targets = %w[PeekerCore FunctionCardKit PersistenceCore MacPlatform FeatureRuntimeKit]
  feature_targets = %w[TimerFeature TimerGRDBAdapter TimerModule PusherFeature PusherGRDBAdapter PusherModule]

  framework_targets.each do |name|
    dependencies = targets.fetch(name).fetch("dependencies").map { |dependency|
      dependency["byName"]&.first || dependency["target"]&.first
    }.compact
    leaked = dependencies & feature_targets
    abort "#{name} depends on concrete feature targets: #{leaked.join(", ")}" unless leaked.empty?
  end
'

framework_paths=(
  Sources/PeekerCore
  Sources/FunctionCardKit
  Sources/PersistenceCore
  Sources/MacPlatform
  Sources/FeatureRuntimeKit
)

if search_sources \
  'TimerFeature|PusherFeature|TimerGRDBAdapter|PusherGRDBAdapter|timer_|pusher_|timerRefresh|timerStatisticsMode|pusherRefresh|pusherCarryIncomplete|FeatureID\.(timer|pusher)|"(timer|pusher)"' \
  "${framework_paths[@]}"; then
  echo "Concrete feature knowledge leaked into framework sources." >&2
  exit 1
fi

app_sources=()
while IFS= read -r source; do
  app_sources+=("$source")
done < <(find Sources/PeekerApp -type f -name '*.swift' ! -name 'BuiltInFeatureModules.swift' -print)

if search_sources 'TimerModule|PusherModule|TimerFeature|PusherFeature|TimerGRDBAdapter|PusherGRDBAdapter' "${app_sources[@]}"; then
  echo "Concrete feature assembly is allowed only in BuiltInFeatureModules.swift." >&2
  exit 1
fi

echo "Feature boundary contract passed."
