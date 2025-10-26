#!/usr/bin/env bash
# GitLab Runner NixOS Infrastructure Management Script

set -euo pipefail

# Function to print status
print_status() {
    local message=$1
    echo "${message}"
}

# Function to ensure terraform is initialized
ensure_terraform_init() {
    print_status "Ensuring Terraform is initialized..."

    # Check if .terraform directory exists
    if [[ ! -d ".terraform" ]]; then
        print_status "Running terraform init..."
        if terraform init; then
            print_status "SUCCESS: terraform init completed"
        else
            print_status "ERROR: terraform init failed"
            return 1
        fi
    else
        print_status "Terraform already initialized"
    fi

    return 0
}

# Function to run linting
lint_terraform() {
    print_status "Running Terraform linting..."

    # Check if we're in a Terraform directory
    if [[ ! -f "main.tf" && ! -f "variables.tf" ]]; then
        print_status "WARNING: No Terraform files found in current directory"
        return 0
    fi

    # Ensure terraform is initialized
    if ! ensure_terraform_init; then
        return 1
    fi

    # Run tflint
    print_status "Running tflint..."
    if tflint; then
        print_status "SUCCESS: tflint passed"
    else
        print_status "ERROR: tflint found issues"
        return 1
    fi

    # Run terraform validate
    print_status "Running terraform validate..."
    if terraform validate; then
        print_status "SUCCESS: terraform validate passed"
    else
        print_status "ERROR: terraform validate found issues"
        return 1
    fi

    # Run terraform fmt check
    print_status "Checking terraform formatting..."
    if terraform fmt -check -recursive; then
        print_status "SUCCESS: terraform fmt check passed"
    else
        print_status "WARNING: terraform fmt issues found, running fmt..."
        terraform fmt -recursive
        print_status "SUCCESS: terraform fmt applied"
    fi
}

# Function to run all checks
check_all() {
    print_status "Running comprehensive Terraform checks..."

    local exit_code=0

    # Run linting
    if ! lint_terraform; then
        exit_code=1
    fi

    if [[ $exit_code -eq 0 ]]; then
        print_status "SUCCESS: All checks passed!"
    else
        print_status "ERROR: Some checks failed!"
    fi

    return $exit_code
}

# Main script logic
case "${1:-check}" in
    "lint")
        lint_terraform
    ;;
    "check"|"all")
        check_all
    ;;
    "validate")
        ensure_terraform_init && terraform validate
    ;;
    "fmt")
        terraform fmt -recursive
    ;;
    "init")
        terraform init
    ;;
    "plan")
        ensure_terraform_init && terraform plan
    ;;
    "apply")
        ensure_terraform_init && terraform apply
    ;;
    "destroy")
        ensure_terraform_init && terraform destroy
    ;;
    "help"|"-h"|"--help")
        echo "GitLab Runner NixOS Infrastructure Management"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  lint      Run tflint and terraform validate"
        echo "  check     Run all checks (default)"
        echo "  validate  Run terraform validate only"
        echo "  fmt       Run terraform fmt"
        echo "  init      Run terraform init"
        echo "  plan      Run terraform plan"
        echo "  apply     Run terraform apply"
        echo "  destroy   Run terraform destroy"
        echo "  help      Show this help message"
    ;;
    *)
        print_status "ERROR: Unknown command: $1"
        print_status "Run '$0 help' for usage information"
        exit 1
    ;;
esac
