# shellcheck shell=bash

set -euo pipefail

# Function to print status
print_status() {
  local message=$1
  echo "${message}"
}

# Function to run shellcheck on shell scripts
lint_shell() {
  print_status "Running ShellCheck linting..."

  # Find all shell scripts in the current directory and subdirectories
  local shell_files=()
  while IFS= read -r -d '' file; do
    shell_files+=("$file")
  done < <(find . -type f \( -name "*.sh" -o -name "*.bash" \) -print0)

  if [[ ${#shell_files[@]} -eq 0 ]]; then
    print_status "WARNING: No shell scripts found"
    return 0
  fi

  print_status "Found ${#shell_files[@]} shell script(s) to check"

  local exit_code=0
  for file in "${shell_files[@]}"; do
    print_status "Checking: $file"
    if shellcheck "$file"; then
      print_status "SUCCESS: $file passed shellcheck"
    else
      print_status "ERROR: $file failed shellcheck"
      exit_code=1
    fi
  done

  if [[ $exit_code -eq 0 ]]; then
    print_status "SUCCESS: All shell scripts passed shellcheck!"
  else
    print_status "ERROR: Some shell scripts failed shellcheck!"
  fi

  return $exit_code
}

# Function to format shell scripts
format_shell() {
  print_status "Formatting shell scripts..."

  # Find all shell scripts in the current directory and subdirectories
  local shell_files=()
  while IFS= read -r -d '' file; do
    shell_files+=("$file")
  done < <(find . -type f \( -name "*.sh" -o -name "*.bash" \) -print0)

  if [[ ${#shell_files[@]} -eq 0 ]]; then
    print_status "WARNING: No shell scripts found"
    return 0
  fi

  print_status "Found ${#shell_files[@]} shell script(s) to format"

  local exit_code=0
  for file in "${shell_files[@]}"; do
    print_status "Formatting: $file"
    if shfmt -w -i 2 -ci -sr "$file"; then
      print_status "SUCCESS: $file formatted"
    else
      print_status "ERROR: Failed to format $file"
      exit_code=1
    fi
  done

  if [[ $exit_code -eq 0 ]]; then
    print_status "SUCCESS: All shell scripts formatted!"
  else
    print_status "ERROR: Some shell scripts failed to format!"
  fi

  return $exit_code
}

# Main script logic
case "${1:-check}" in
  "check" | "lint")
    lint_shell
    ;;
  "format" | "fmt")
    format_shell
    ;;
  "help" | "-h" | "--help")
    echo "ShellCheck Linting and Formatting Tool"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  check     Run shellcheck on all shell scripts (default)"
    echo "  lint      Same as check"
    echo "  format    Format all shell scripts with shfmt"
    echo "  fmt       Same as format"
    echo "  help      Show this help message"
    ;;
  *)
    print_status "ERROR: Unknown command: ${1:-}"
    print_status "Run '$0 help' for usage information"
    exit 1
    ;;
esac
