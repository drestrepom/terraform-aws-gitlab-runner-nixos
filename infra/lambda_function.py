import json
import os
import urllib3
import boto3
from datetime import datetime
import math


def lambda_handler(event, context):
    """
    Simple GitLab-driven autoscaler
    Replicates the fleeting plugin logic:
    - Queries pending jobs in GitLab
    - Calculates required capacity
    - Adjusts ASG desired capacity
    """

    # Environment variables
    gitlab_token = os.environ["GITLAB_TOKEN"]
    project_id = os.environ["GITLAB_PROJECT_ID"]
    gitlab_url = os.environ.get("GITLAB_URL", "https://gitlab.com")
    runner_tag = os.environ.get("RUNNER_TAG", "nixos")
    asg_name = os.environ.get("ASG_NAME", "nixos-gitlab-runners")
    
    # Scaling configuration (similar to the fleeting plugin)
    jobs_per_instance = int(os.environ.get("JOBS_PER_INSTANCE", "1"))
    min_idle_instances = int(os.environ.get("MIN_IDLE_INSTANCES", "0"))
    max_instances = int(os.environ.get("MAX_INSTANCES", "10"))

    # Initialize clients
    http = urllib3.PoolManager()
    cloudwatch = boto3.client("cloudwatch")
    autoscaling = boto3.client("autoscaling")

    try:
        headers = {"PRIVATE-TOKEN": gitlab_token, "Content-Type": "application/json"}

        # ============================================
        # 1. Query jobs in GitLab (just like the plugin)
        # ============================================
        pending_url = f"{gitlab_url}/api/v4/projects/{project_id}/jobs?scope[]=pending"
        pending_response = http.request("GET", pending_url, headers=headers)
        pending_jobs = json.loads(pending_response.data.decode("utf-8"))

        running_url = f"{gitlab_url}/api/v4/projects/{project_id}/jobs?scope[]=running"
        running_response = http.request("GET", running_url, headers=headers)
        running_jobs = json.loads(running_response.data.decode("utf-8"))

        # Filter by tag
        pending_for_us = [job for job in pending_jobs if runner_tag in job.get("tag_list", [])]
        running_for_us = [job for job in running_jobs if runner_tag in job.get("tag_list", [])]

        pending_count = len(pending_for_us)
        running_count = len(running_for_us)

        # ============================================
        # 2. Get current ASG state
        # ============================================
        asg_response = autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])

        if not asg_response["AutoScalingGroups"]:
            raise Exception(f"ASG {asg_name} not found")

        asg = asg_response["AutoScalingGroups"][0]
        current_desired = asg["DesiredCapacity"]
        current_max = asg["MaxSize"]

        # ============================================
        # 3. Calculate required capacity
        # (Logic identical to the fleeting plugin)
        # ============================================
        
        # Capacity for pending jobs
        needed_for_pending = math.ceil(pending_count / jobs_per_instance)
        
        # Capacity for running jobs (should already be covered)
        needed_for_running = math.ceil(running_count / jobs_per_instance)
        
        # Total needed = maximum of both + minimum idle
        needed_capacity = max(needed_for_pending, needed_for_running, min_idle_instances)
        
        # Apply maximum limit
        needed_capacity = min(needed_capacity, max_instances, current_max)

        # ============================================
        # 4. Adjust ASG if necessary
        # ============================================
        scaling_action = "none"
        
        if needed_capacity > current_desired:
            # Scale out
            autoscaling.set_desired_capacity(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=needed_capacity,
                HonorCooldown=False  # Fast response like the plugin
            )
            scaling_action = "scale_out"
            print(f"⬆️  Scaling OUT: {current_desired} → {needed_capacity}")
            
        elif needed_capacity < current_desired:
            # Scale in (only if no jobs are running)
            if running_count == 0:
                autoscaling.set_desired_capacity(
                    AutoScalingGroupName=asg_name,
                    DesiredCapacity=needed_capacity,
                    HonorCooldown=True  # Respect cooldown when scaling in
                )
                scaling_action = "scale_in"
                print(f"⬇️  Scaling IN: {current_desired} → {needed_capacity}")
            else:
                print(f"⏸️  Scale in deferred (jobs still running)")
        else:
            print(f"✅ Capacity optimal: {current_desired} instances")

        # ============================================
        # 5. Send metrics to CloudWatch (essentials only)
        # ============================================
        metric_data = [
            {
                "MetricName": "PendingJobs",
                "Value": pending_count,
                "Unit": "Count",
                "Timestamp": datetime.utcnow(),
            },
            {
                "MetricName": "RunningJobs",
                "Value": running_count,
                "Unit": "Count",
                "Timestamp": datetime.utcnow(),
            },
            {
                "MetricName": "DesiredCapacity",
                "Value": needed_capacity,
                "Unit": "Count",
                "Timestamp": datetime.utcnow(),
            },
            {
                "MetricName": "CurrentCapacity",
                "Value": current_desired,
                "Unit": "Count",
                "Timestamp": datetime.utcnow(),
            },
        ]

        # Add dimensions
        for metric in metric_data:
            metric["Dimensions"] = [
                {"Name": "ProjectId", "Value": str(project_id)},
                {"Name": "ASGName", "Value": asg_name},
            ]

        cloudwatch.put_metric_data(Namespace="GitLab/CI", MetricData=metric_data)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "pending_jobs": pending_count,
                "running_jobs": running_count,
                "current_capacity": current_desired,
                "needed_capacity": needed_capacity,
                "scaling_action": scaling_action,
            }),
        }

    except Exception as e:
        error_msg = f"Error: {str(e)}"
        print(error_msg)

        cloudwatch.put_metric_data(
            Namespace="GitLab/CI",
            MetricData=[
                {
                    "MetricName": "CollectorErrors",
                    "Value": 1,
                    "Unit": "Count",
                    "Timestamp": datetime.utcnow(),
                    "Dimensions": [{"Name": "ProjectId", "Value": str(project_id)}],
                }
            ],
        )

        return {"statusCode": 500, "body": json.dumps({"error": error_msg})}
