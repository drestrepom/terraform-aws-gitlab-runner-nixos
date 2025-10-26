#!/usr/bin/env bash
# Nix Linting and Formatting Script

set -euo pipefail

# Detect if we're running in CI
is_ci() {
  [[ -n "${CI:-}" ]] || [[ -n "${GITLAB_CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]
}

# Function to print status
print_status() {
  local message=$1
  echo "${message}"
}

# Function to run nixpkgs-fmt on nix files
lint_nix() {
  print_status "Running Nix linting..."
  
  if is_ci; then
    print_status "CI detected - running check mode"
    if nixpkgs-fmt --check .; then
      print_status "SUCCESS: All nix files passed nixpkgs-fmt!"
      return 0
    else
      print_status "ERROR: Some nix files failed nixpkgs-fmt!"
      print_status "Run 'nix run .#nix-lint format' to fix formatting issues"
      return 1
    fi
  else
    print_status "Local environment - running check with diff preview"
    if nixpkgs-fmt --check .; then
      print_status "SUCCESS: All nix files passed nixpkgs-fmt!"
      return 0
    else
      print_status "ERROR: Some nix files failed nixpkgs-fmt!"
      print_status "Showing diff of what would be changed:"
      nixpkgs-fmt --check . 2>&1 || true
      print_status "Run 'nix run .#nix-lint format' to fix formatting issues"
      return 1
    fi
  fi
}

# Function to format nix files
format_nix() {
  print_status "Formatting nix files..."

  if nixpkgs-fmt .; then
    print_status "SUCCESS: All nix files formatted!"
    return 0
  else
    print_status "ERROR: Some nix files failed to format!"
    return 1
  fi
}

# Function to run nixfmt (alternative formatter)
lint_nixfmt() {
  print_status "Running nixfmt linting..."

  if nixfmt --check .; then
    print_status "SUCCESS: All nix files passed nixfmt!"
    return 0
  else
    print_status "ERROR: Some nix files failed nixfmt!"
    return 1
  fi
}

# Main script logic
case "${1:-check}" in
  "check" | "lint")
    lint_nix
    ;;
  "format" | "fmt")
    format_nix
    ;;
  "nixfmt")
    lint_nixfmt
    ;;
  "help" | "-h" | "--help")
    echo "Nix Linting and Formatting Tool"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  check     Run nixpkgs-fmt check on all nix files (default)"
    echo "  lint      Same as check"
    echo "  format    Format all nix files with nixpkgs-fmt"
    echo "  fmt       Same as format"
    echo "  nixfmt    Run nixfmt check on all nix files"
    echo "  help      Show this help message"
    ;;
  *)
    print_status "ERROR: Unknown command: ${1:-}"
    print_status "Run '$0 help' for usage information"
    exit 1
    ;;
esac
