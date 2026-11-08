#!/usr/bin/env bash
# Shared by Android setup/dev builds; this file is sourced, not executed.
if ! command -v flutter >/dev/null 2>&1 && [[ -x "$HOME/flutter/bin/flutter" ]]; then
  export PATH="$HOME/flutter/bin:$PATH"
fi
if [[ -z "${JAVA_HOME:-}" || ! -d "$JAVA_HOME" ]]; then
  if [[ -d /opt/homebrew/opt/openjdk@17 ]]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@17
  elif [[ -d "$HOME/.local/android-env/jdk" ]]; then
    export JAVA_HOME="$HOME/.local/android-env/jdk"
  elif [[ -x /usr/libexec/java_home ]]; then
    detected_java=$(/usr/libexec/java_home -v 17 2>/dev/null || true)
    [[ -z "$detected_java" ]] || export JAVA_HOME="$detected_java"
    unset detected_java
  fi
fi
[[ -z "${JAVA_HOME:-}" ]] || export PATH="$JAVA_HOME/bin:$PATH"
