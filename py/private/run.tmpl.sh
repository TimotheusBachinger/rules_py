#!/usr/bin/env bash
# NB: we don't use a path from @bazel_tools//tools/sh:toolchain_type because that's configured for the exec
# configuration, while this script executes in the target configuration at runtime.

# This is a special comment for py_pex_binary to find the python entrypoint.
# __PEX_PY_BINARY_ENTRYPOINT__ {{ENTRYPOINT}}

{{BASH_RLOCATION_FN}}
runfiles_export_envvars

set -o errexit -o nounset -o pipefail

PWD="$(pwd)"

# Returns an absolute path to the given location if the path is relative, otherwise return
# the path unchanged.
function alocation {
  local P=$1
  if [[ "${P:0:1}" == "/" ]]; then
    echo -n "${P}"
  else
    echo -n "${PWD}/${P}"
  fi
}

function python_location {
  local PYTHON="{{ARG_PYTHON}}"
  local RUNFILES_INTERPRETER="{{RUNFILES_INTERPRETER}}"

  if [[ "${RUNFILES_INTERPRETER}" == "true" ]]; then
    echo -n "$(alocation $(rlocation ${PYTHON}))"
  else
    echo -n "${PYTHON}"
  fi
}

VENV_TOOL="$(rlocation {{VENV_TOOL}})"

RUNFILES_VIRTUAL_ENV="$(alocation "${RUNFILES_DIR}/{{ARG_VENV_NAME}}")"
VIRTUAL_ENV="${RUNFILES_VIRTUAL_ENV}"

PTH_ENTRY_PREFIX=""
PTH_FILE="$(rlocation {{ARG_PTH_FILE}})"

if [[ -n "${VENV_PATH:-}" ]]; then
  VIRTUAL_ENV="${VENV_PATH}"
  # Remove preexisting runfiles virtualenv symlink if it exists
  rm -rf "${RUNFILES_VIRTUAL_ENV}" > /dev/null || true
  # Create a symlink to the virtualenv in the runfiles dir
  ln -s "${VIRTUAL_ENV}" "${RUNFILES_VIRTUAL_ENV}"

  # We need to rewrite the pth file to be relative to the runfiles dir
  PTH="$(cat "${PTH_FILE}")"
  PTH="${PTH//"${VENV_PTH_STRIP}"/.}"
  PTH_FILE="$(mktemp)"
  echo "${PTH}" > "${PTH_FILE}"

  # And set the pth entry prefix to the runfiles dir
  PTH_ENTRY_PREFIX="${RUNFILES_DIR}"
fi


"${VENV_TOOL}" \
    --location "${VIRTUAL_ENV}" \
    --python "$(python_location)" \
    --pth-file "${PTH_FILE}"\
    --pth-entry-prefix "${PTH_ENTRY_PREFIX}" \
    --collision-strategy "{{ARG_COLLISION_STRATEGY}}" \
    --venv-name "{{ARG_VENV_NAME}}"

export VIRTUAL_ENV="${RUNFILES_VIRTUAL_ENV}"

PATH="${VIRTUAL_ENV}/bin:${PATH}"
export PATH

# Set all the env vars here, just before we launch
{{PYTHON_ENV}}

# This should detect bash and zsh, which have a hash command that must
# be called to get it to forget past commands.  Without forgetting
# past commands the $PATH changes we made may not be respected
if [ -n "${BASH:-}" -o -n "${ZSH_VERSION:-}" ] ; then
    hash -r 2> /dev/null
fi

exec "{{EXEC_PYTHON_BIN}}" {{INTERPRETER_FLAGS}} "$(rlocation {{ENTRYPOINT}})" "$@"