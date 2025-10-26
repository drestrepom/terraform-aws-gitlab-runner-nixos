# Terraform Module: GitLab Runner with Native Nix Support on AWS

[![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.3-blue.svg)](https://www.terraform.io/downloads.html)
[![AWS Provider](https://img.shields.io/badge/AWS-%3E%3D5.0-orange.svg)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Terraform module for deploying auto-scaling GitLab runners on AWS with **native Nix flake support** - no Docker required!

## 🚀 Why This Module?

### The Problem with Docker-based Runners

Most GitLab runners use Docker images to run Nix flakes. This approach has significant drawbacks:

```mermaid
graph LR
    A[Job Starts] --> B[Pull Docker Image]
    B --> C[Start Container]
    C --> D[Run Nix Build]
    D --> E[Build from Scratch]
    E --> F[Job Complete]
    F --> G[Container Destroyed]
    G --> H[All Builds Lost]
```

**Problems:**
- ❌ Every job starts from scratch
- ❌ No caching between jobs
- ❌ Wasted time rebuilding derivations
- ❌ Complicated caching strategies that don't work well

### The Solution: Native Nix with Persistent Store

This module runs Nix natively on NixOS instances with a persistent Nix store:

```mermaid
graph LR
    A[Job Starts] --> B[Runner Available]
    B --> C[Run Nix Build]
    C --> D{Derivation in Store?}
    D -->|Yes| E[Use Cached Build]
    D -->|No| F[Build Once]
    F --> G[Store in Nix Store]
    E --> H[Job Complete Fast]
    G --> H
    H --> I[Store Persists]
    I --> A
```

**Benefits:**
- ✅ Derivations cached in the Nix store
- ✅ Subsequent builds are significantly faster
- ✅ No Docker overhead
- ✅ Simple, elegant solution
- ✅ Native NixOS environment

## 🎯 Features

- **Native Nix Support**: Run Nix flakes without Docker
- **Persistent Nix Store**: Build once, use many times
- **Auto-scaling**: Intelligent scaling based on GitLab job queue
- **High Availability**: Multi-AZ deployment
- **Flexible Networking**: BYO VPC or create new
- **Monitoring**: CloudWatch metrics and dashboards
- **Security**: SSM access, encrypted volumes, IMDSv2
- **Customizable**: Additional NixOS configuration blocks

## 📋 Requirements

- Terraform >= 1.3
- AWS Provider >= 5.0
- GitLab account with runner token
- AWS account with appropriate permissions

## 🚀 Quick Start

### 1. Create a GitLab Runner

In your GitLab project/group, create a new runner and get the authentication token:

1. Go to **Settings → CI/CD → Runners**
2. Click **New project runner** (or **New group runner**)
3. Configure runner settings:
   - Tags: `nixos`, `nix`, `shell`
   - Run untagged jobs: Your choice
4. Click **Create runner**
5. **Copy the token** (starts with `glrt-`)

### 2. Use the Module

```hcl
module "gitlab_runner" {
  source = "github.com/your-org/terraform-aws-gitlab-runner-nixos"

  # Required: Environment and GitLab configuration
  environment          = "production"
  gitlab_url           = "https://gitlab.com"  # or your GitLab instance
  gitlab_runner_token  = "glrt-xxxxxxxxxxxxx"  # Token from step 1

  # Optional: GitLab API for intelligent autoscaling
  enable_gitlab_metrics = true
  gitlab_token         = "glpat-xxxxxxxxxxxxx"  # Personal access token with read_api scope
  gitlab_project_id    = 12345

  # Capacity configuration
  max_instances               = 10
  min_idle_instances          = 1
  concurrent_jobs_per_instance = 2

  # Cost optimization
  on_demand_percentage = 10  # 90% spot instances

  # Tags for runners
  gitlab_runner_tags = ["nixos", "nix", "arm64", "shell"]

  tags = {
    Team        = "platform"
    CostCenter  = "engineering"
  }
}

output "runner_info" {
  value = {
    autoscaling_group = module.gitlab_runner.autoscaling_group_name
    vpc_id            = module.gitlab_runner.vpc_id
    nat_instance_ip   = module.gitlab_runner.nat_instance_public_ip
  }
}
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Test Your Runner

Create a `.gitlab-ci.yml` in your repository:

```yaml
test:
  tags:
    - nixos
  script:
    - nix --version
    - nix flake show
    - nix build
```

## 📚 Usage Examples

### Basic Setup

```hcl
module "gitlab_runner" {
  source = "github.com/your-org/terraform-aws-gitlab-runner-nixos"

  environment         = "dev"
  gitlab_url          = "https://gitlab.com"
  gitlab_runner_token = var.gitlab_runner_token

  max_instances      = 5
  min_idle_instances = 0
}
```

### Production Setup

```hcl
module "gitlab_runner" {
  source = "github.com/your-org/terraform-aws-gitlab-runner-nixos"

  environment         = "production"
  gitlab_url          = "https://gitlab.example.com"
  gitlab_runner_token = var.gitlab_runner_token

  # Intelligent autoscaling
  enable_gitlab_metrics = true
  gitlab_token         = var.gitlab_api_token
  gitlab_project_id    = 12345

  # Capacity
  max_instances               = 20
  min_idle_instances          = 2
  concurrent_jobs_per_instance = 2

  # Monitoring
  enable_cloudwatch_monitoring = true
  enable_ssm_access           = true
}
```

### Using Existing VPC

```hcl
module "gitlab_runner" {
  source = "github.com/your-org/terraform-aws-gitlab-runner-nixos"

  environment         = "staging"
  gitlab_url          = "https://gitlab.com"
  gitlab_runner_token = var.gitlab_runner_token

  # Use existing VPC
  create_vpc = false
  vpc_id     = "vpc-xxxxx"
  subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]

  max_instances = 10
}
```

## 🏗️ Architecture

### Infrastructure Diagram

```mermaid
graph TB
    subgraph AWS["AWS Cloud"]
        subgraph VPC["VPC (10.0.0.0/16)"]
            subgraph PublicSubnets["Public Subnets (Multi-AZ)"]
                IGW["Internet Gateway"]
                NAT["NAT Instance"]
            end

            subgraph PrivateSubnets["Private Subnets (Multi-AZ)"]
                subgraph ASG["Auto Scaling Group"]
                    Runner1["NixOS Runner<br/>└─ Nix Store"]
                    Runner2["NixOS Runner<br/>└─ Nix Store"]
                    Runner3["NixOS Runner<br/>└─ Nix Store"]
                end
            end

            subgraph Lambda["Lambda Function"]
                LambdaFunc["Auto-Scaling Logic<br/>• Checks GitLab API<br/>• Scales ASG<br/>• Publishes metrics"]
            end

            subgraph CloudWatch["CloudWatch"]
                Metrics["Metrics & Dashboards"]
            end
        end

        subgraph External["External Services"]
            GitLab["GitLab CI/CD"]
        end
    end

    %% Connections
    IGW -->|"Internet"| NAT
    NAT -->|"Outbound"| Runner1
    NAT -->|"Outbound"| Runner2
    NAT -->|"Outbound"| Runner3

    LambdaFunc -->|"Scale"| ASG
    LambdaFunc -->|"Metrics"| Metrics
    LambdaFunc -->|"API"| GitLab

    Runner1 -->|"Jobs"| GitLab
    Runner2 -->|"Jobs"| GitLab
    Runner3 -->|"Jobs"| GitLab

    %% Styling
    classDef aws fill:#f3e8ff,stroke:#7c3aed,stroke-width:3px,color:#581c87
    classDef vpc fill:#e9d5ff,stroke:#8b5cf6,stroke-width:3px,color:#581c87
    classDef public fill:#ddd6fe,stroke:#a855f7,stroke-width:3px,color:#581c87
    classDef private fill:#c4b5fd,stroke:#c084fc,stroke-width:3px,color:#581c87
    classDef lambda fill:#a78bfa,stroke:#d946ef,stroke-width:3px,color:#581c87
    classDef external fill:#fbbf24,stroke:#f59e0b,stroke-width:3px,color:#92400e

    class AWS aws
    class VPC vpc
    class PublicSubnets public
    class PrivateSubnets private
    class Lambda lambda
    class External external
    
    %% Link styling - make connections more visible
    linkStyle 0 stroke:#7c3aed,stroke-width:3px
    linkStyle 1 stroke:#7c3aed,stroke-width:3px
    linkStyle 2 stroke:#7c3aed,stroke-width:3px
    linkStyle 3 stroke:#7c3aed,stroke-width:3px
    linkStyle 4 stroke:#d946ef,stroke-width:3px
    linkStyle 5 stroke:#d946ef,stroke-width:3px
    linkStyle 6 stroke:#d946ef,stroke-width:3px
    linkStyle 7 stroke:#f59e0b,stroke-width:3px
    linkStyle 8 stroke:#f59e0b,stroke-width:3px
    linkStyle 9 stroke:#f59e0b,stroke-width:3px
```

### How It Works

1. **Runner Registration**: Runners register with GitLab using the provided token
2. **Job Polling**: Runners poll GitLab for new jobs
3. **Job Execution**: Jobs run natively on NixOS with the shell executor
4. **Nix Store**: Derivations are cached in the persistent Nix store
5. **Auto-Scaling**: Lambda function monitors GitLab queue and scales ASG
6. **Flexible Deployment**: Support for both spot and on-demand instances

### Autoscaling Logic

The module implements intelligent autoscaling inspired by GitLab's fleeting plugin:

```
Desired Capacity = ceil(
  pending_jobs / jobs_per_instance * scale_factor
) + min_idle_instances

Capped at:
  - Maximum: max_instances
  - Growth Rate: max_growth_rate per iteration
```

Scale-in occurs when utilization falls below `scale_in_threshold`.

## 📖 Module Documentation

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `environment` | Environment name (e.g., production, staging) | `string` | n/a | yes |
| `gitlab_url` | GitLab instance URL | `string` | `"https://gitlab.com"` | no |
| `gitlab_token` | GitLab Personal Access Token with 'create_runner' scope | `string` | n/a | yes |
| `gitlab_project_id` | GitLab Project ID where the runner will be registered | `number` | n/a | yes |
| `gitlab_runner_tags` | Tags for the GitLab runner | `list(string)` | `["nixos", "nix", "arm64", "shell"]` | no |
| `max_instances` | Maximum number of runner instances | `number` | `10` | no |
| `min_idle_instances` | Minimum number of idle instances to keep warm | `number` | `0` | no |
| `concurrent_jobs_per_instance` | Concurrent jobs per runner instance | `number` | `2` | no |
| `instance_types` | List of EC2 instance types | `list(string)` | `["t4g.medium", ...]` | no |
| `on_demand_percentage` | Percentage of on-demand vs spot instances | `number` | `10` | no |
| `root_volume_size` | Root volume size in GB | `number` | `40` | no |
| `gitlab_runner_volume_size` | Additional EBS volume size for GitLab Runner builds in GB | `number` | `100` | no |
| `gitlab_runner_volume_type` | Type of the GitLab Runner volume (gp2, gp3, io1, io2) | `string` | `gp3` | no |
| `enable_gitlab_metrics` | Enable GitLab API metrics collection | `bool` | `true` | no |
| `create_vpc` | Create a new VPC | `bool` | `true` | no |
| `vpc_id` | Existing VPC ID (if create_vpc is false) | `string` | `""` | no |
| `subnet_ids` | Existing subnet IDs (if create_vpc is false) | `list(string)` | `[]` | no |
| `enable_nat_gateway` | Use NAT Gateway instead of NAT Instance | `bool` | `false` | no |
| `enable_ssm_access` | Enable AWS Systems Manager access | `bool` | `true` | no |
| `custom_nixos_config` | Custom NixOS configuration to override defaults | `string` | `""` | no |
| `additional_nixos_configs` | List of additional NixOS configuration blocks to import | `list(string)` | `[]` | no |

<details>
<summary><b>View all inputs (50+)</b></summary>

See the [variables.tf](variables.tf) file for complete documentation of all input variables.

</details>

### Outputs

| Name | Description |
|------|-------------|
| `autoscaling_group_name` | Name of the Auto Scaling Group |
| `autoscaling_group_arn` | ARN of the Auto Scaling Group |
| `runner_iam_role_arn` | ARN of the IAM role used by runners |
| `runner_security_group_id` | ID of the security group for runners |
| `vpc_id` | ID of the VPC |
| `subnet_ids` | IDs of the subnets |
| `nat_instance_public_ip` | Public IP of the NAT instance (if used) |
| `lambda_function_name` | Name of the autoscaling Lambda function |
| `ssm_connect_command` | AWS CLI command to connect via SSM |
| `scaling_status_command` | AWS CLI command to check scaling status |

<details>
<summary><b>View all outputs</b></summary>

See the [outputs.tf](outputs.tf) file for complete documentation of all outputs.

</details>

## 🛠️ Advanced Configuration

### Custom NixOS Configuration

You can provide custom NixOS configuration:

```hcl
module "gitlab_runner" {
  source = "github.com/your-org/terraform-aws-gitlab-runner-nixos"

  environment         = "production"
  gitlab_runner_token = var.token

  custom_nixos_config = file("${path.module}/custom-runner-config.nix")
}
```

### Additional NixOS Configuration Blocks

You can also provide additional NixOS configuration blocks that will be imported into the base configuration:

```hcl
module "gitlab_runner" {
  source = "github.com/your-org/terraform-aws-gitlab-runner-nixos"

  environment         = "production"
  gitlab_runner_token = var.token

  additional_nixos_configs = [
    # Custom package configuration
    "{ config, pkgs, ... }: { environment.systemPackages = with pkgs; [ vim ]; }",
    # Custom service configuration
    "{ config, pkgs, ... }: { services.nginx.enable = true; }",
    # Custom user configuration
    "{ config, pkgs, ... }: { users.users.myuser = { isNormalUser = true; }; }"
  ]
}
```

This approach allows you to add specific configurations without overriding the entire base configuration, making it more modular and maintainable.

### Autoscaling Parameters

Fine-tune the autoscaling behavior:

```hcl
module "gitlab_runner" {
  source = "github.com/your-org/terraform-aws-gitlab-runner-nixos"

  environment         = "production"
  gitlab_runner_token = var.token

  # Scaling algorithm parameters
  scale_factor       = 1.2   # Slightly over-provision
  max_growth_rate    = 5     # Add max 5 instances per minute
  scale_in_threshold = 0.3   # Scale in when < 30% utilized

  # Lambda check frequency
  lambda_check_interval = 1  # Check every minute
}
```

### Security Hardening

```hcl
module "gitlab_runner" {
  source = "github.com/your-org/terraform-aws-gitlab-runner-nixos"

  environment         = "production"
  gitlab_runner_token = var.token

  # Disable SSM access
  enable_ssm_access = false

  # No SSH access to NAT instance
  allowed_ssh_cidr_blocks = []

  # Additional security groups
  additional_security_group_ids = [
    aws_security_group.additional.id
  ]
}
```

## 🔍 Monitoring

### CloudWatch Metrics

The module publishes the following metrics to CloudWatch:

- **Namespace**: `GitLab/CI`
  - `PendingJobs`: Number of pending jobs in queue
  - `RunningJobs`: Number of currently running jobs
  - `AvailableRunners`: Number of available runners

- **Namespace**: `GitLab/Runner`
  - `RunnerHealthy`: Health status of individual runners

### CloudWatch Dashboard

Access the CloudWatch dashboard:

```bash
terraform output cloudwatch_dashboard_url
```

### Checking Runner Status

```bash
# Get ASG status
terraform output -raw scaling_status_command | bash

# Connect to runner via SSM
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw autoscaling_group_name) \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

aws ssm start-session --target $INSTANCE_ID

# Once connected, check runner status
sudo systemctl status gitlab-runner
sudo gitlab-runner verify
```

### Lambda Logs

```bash
terraform output -raw lambda_logs_command | bash
```

## 💰 Cost Optimization

### Cost Optimization Tips

1. **Use spot instances**: Set `on_demand_percentage = 0-10%` (default)
2. **NAT Instance over Gateway**: More cost-effective option available
3. **Minimal idle instances**: Set `min_idle_instances = 0-1`
4. **Right-size instances**: Start with `t4g.small` or `t4g.medium`
5. **Enable intelligent scaling**: Use GitLab API metrics
6. **Multi-region**: Deploy only where needed

## 🐛 Troubleshooting

### Runners not registering

```bash
# Check runner logs
aws ssm start-session --target <instance-id>
sudo journalctl -u gitlab-runner -f

# Verify token
sudo cat /etc/gitlab-runner-authentication.env

# Test GitLab connectivity
curl -v https://gitlab.com
```

### Autoscaling not working

```bash
# Check Lambda logs
aws logs tail /aws/lambda/<function-name> --follow

# Verify IAM permissions
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names <asg-name>

# Check GitLab API token
curl -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/<project-id>/jobs?scope=pending"
```

### Slow builds

```bash
# Check Nix store size
du -sh /nix/store

# Verify cache is working
nix path-info --all | wc -l

# Check system resources
htop
df -h
```

### Connectivity issues

```bash
# From NAT instance, test routing
ping 8.8.8.8
traceroute gitlab.com

# Check iptables
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v

# From runner, test Internet
curl -v https://gitlab.com
curl -v https://cache.nixos.org
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by [cattle-ops/terraform-aws-gitlab-runner](https://github.com/cattle-ops/terraform-aws-gitlab-runner)
- Built on the excellent NixOS project
- Autoscaling logic inspired by GitLab's fleeting plugin

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/your-org/terraform-aws-gitlab-runner-nixos/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/terraform-aws-gitlab-runner-nixos/discussions)

---

**Made with ❤️ for the Nix community**
