# Complete Example

This example demonstrates a production-ready GitLab Runner setup with native Nix support.

## Features

- ✅ Intelligent autoscaling based on GitLab API
- ✅ Cost optimization with 100% spot instances
- ✅ Multi-AZ deployment
- ✅ Persistent Nix store for fast builds

## Prerequisites

1. **GitLab Personal Access Token**
   - Go to GitLab → User Settings → Access Tokens
   - Create a token with `api` scope (for metrics) and ensure you have permission to create runners in your project
   - Copy the token (starts with `glpat-`)

2. **GitLab Project ID**
   - Go to your project on GitLab
   - Project Settings → General → Copy the Project ID

3. **AWS Credentials**
   - Configure AWS CLI: `aws configure`
   - Or set environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

## Usage

### 1. Configure Variables

Copy the example tfvars file and edit the required fields:

```bash
cp terraform.tfvars.example terraform.tfvars
```

**Required fields** - Edit `terraform.tfvars`:

```hcl
gitlab_token      = "glpat-xxxxxxxxxxxxxxxxxxxx"  # Your Personal Access Token
gitlab_project_id = 12345                         # Your GitLab Project ID
```

All other fields have sensible defaults and can be left as-is or customized for your needs.

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review Plan

```bash
terraform plan
```

### 4. Deploy

```bash
terraform apply
```

### 5. Test

Create a `.gitlab-ci.yml` file in your repository:

```yaml
test_nix:
  tags:
    - nixos
  script:
    - nix --version
    - echo "Nix store has $(nix path-info --all | wc -l) derivations"
    - nix flake show
```

## Cleanup

```bash
terraform destroy
```

## Customization

### Use Larger Instances

```hcl
instance_types = ["c6g.xlarge", "c7g.xlarge"]
root_volume_size = 100  # Larger Nix store
```

### More Availability

```hcl
min_idle_instances = 3  # Keep more instances warm for faster job pickup
```

### Different Region

```hcl
aws_region = "eu-west-1"
```

## Support

For issues and questions:

- Module Issues: [GitHub Issues](https://github.com/your-org/terraform-aws-gitlab-runner-nixos/issues)
- General Help: [GitHub Discussions](https://github.com/your-org/terraform-aws-gitlab-runner-nixos/discussions)
