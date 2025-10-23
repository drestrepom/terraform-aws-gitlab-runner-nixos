import json
import logging
import math
import os
from datetime import UTC, datetime

import boto3
import urllib3

# Configure logger for Lambda
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def get_gitlab_jobs(
    http,
    gitlab_url: str,
    project_id: str,
    gitlab_token: str,
    runner_tag: str,
) -> tuple[int, int]:
    """
    Query GitLab API for pending and running jobs.

    Returns:
        Tuple[pending_count, running_count]

    """
    headers = {"PRIVATE-TOKEN": gitlab_token, "Content-Type": "application/json"}

    # Get pending jobs
    pending_url = f"{gitlab_url}/api/v4/projects/{project_id}/jobs?scope[]=pending"
    pending_response = http.request("GET", pending_url, headers=headers)
    pending_jobs = json.loads(pending_response.data.decode("utf-8"))

    # Get running jobs
    running_url = f"{gitlab_url}/api/v4/projects/{project_id}/jobs?scope[]=running"
    running_response = http.request("GET", running_url, headers=headers)
    running_jobs = json.loads(running_response.data.decode("utf-8"))

    # Filter by runner tag
    pending_for_us = [job for job in pending_jobs if runner_tag in job.get("tag_list", [])]
    running_for_us = [job for job in running_jobs if runner_tag in job.get("tag_list", [])]

    return len(pending_for_us), len(running_for_us)


def get_asg_state(autoscaling, asg_name: str) -> dict:
    """
    Get current state of the Auto Scaling Group.

    Returns:
        Dict with ASG state information

    """
    asg_response = autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])

    if not asg_response["AutoScalingGroups"]:
        msg = f"ASG {asg_name} not found"
        raise ValueError(msg)

    asg = asg_response["AutoScalingGroups"][0]

    # Count instances by lifecycle state
    pending_instances = 0
    running_instances = 0
    terminating_instances = 0

    for instance in asg.get("Instances", []):
        lifecycle_state = instance["LifecycleState"]

        if lifecycle_state in ["Pending", "Pending:Wait", "Pending:Proceed"]:
            pending_instances += 1
        elif lifecycle_state == "InService":
            running_instances += 1
        elif lifecycle_state in [
            "Terminating",
            "Terminating:Wait",
            "Terminating:Proceed",
        ]:
            terminating_instances += 1

    return {
        "current_desired": asg["DesiredCapacity"],
        "current_max": asg["MaxSize"],
        "pending_instances": pending_instances,
        "running_instances": running_instances,
        "terminating_instances": terminating_instances,
        "total_instances": pending_instances + running_instances,
    }


def calculate_needed_capacity(  # noqa: PLR0913
    pending_jobs: int,
    running_jobs: int,
    total_instances: int,
    jobs_per_instance: int,
    scale_factor: float,
    max_growth_rate: int,
    min_idle_instances: int,
    max_instances: int,
    current_max: int,
) -> tuple[int, int, int]:
    """
    Calculate needed capacity following fleeting plugin logic.

    Returns:
        Tuple[needed_capacity, needed_for_running, additional_capacity]

    """
    # Capacity for running jobs (mandatory)
    needed_for_running = math.ceil(running_jobs / jobs_per_instance)

    # Additional capacity for pending jobs (with scale factor)
    scaled_pending = pending_jobs * scale_factor
    additional_capacity = math.ceil(scaled_pending / jobs_per_instance)

    # Preliminary total
    preliminary_needed = needed_for_running + additional_capacity

    # Apply growth rate limit
    if preliminary_needed > total_instances + max_growth_rate:
        needed_capacity = total_instances + max_growth_rate
    else:
        needed_capacity = preliminary_needed

    # Apply min and max constraints
    needed_capacity = max(needed_capacity, min_idle_instances)
    needed_capacity = min(needed_capacity, max_instances, current_max)

    return needed_capacity, needed_for_running, additional_capacity


def apply_scaling_decision(  # noqa: PLR0913
    autoscaling,
    asg_name: str,
    needed_capacity: int,
    current_desired: int,
    running_jobs: int,
    total_instances: int,
    jobs_per_instance: int,
    scale_in_threshold: float,
) -> str:
    """
    Apply scaling decision (scale out, scale in, or none).

    Returns:
        Scaling action taken: "scale_out", "scale_in", or "none"

    """
    if needed_capacity > current_desired:
        # Scale out
        autoscaling.set_desired_capacity(
            AutoScalingGroupName=asg_name,
            DesiredCapacity=needed_capacity,
            HonorCooldown=False,
        )
        delta = needed_capacity - current_desired
        logger.info(
            "SCALING OUT: %s → %s (+%s)",
            current_desired,
            needed_capacity,
            delta,
        )
        return "scale_out"

    if needed_capacity < current_desired:
        # Scale in (with protection)
        if running_jobs > 0:
            utilization = running_jobs / (total_instances * jobs_per_instance)
            if utilization > scale_in_threshold:
                logger.info(
                    "Scale-in deferred: utilization %.1f%% > threshold %.1f%%",
                    utilization * 100,
                    scale_in_threshold * 100,
                )
                return "none"

        # Safe to scale in
        autoscaling.set_desired_capacity(
            AutoScalingGroupName=asg_name,
            DesiredCapacity=needed_capacity,
            HonorCooldown=True,
        )
        delta = current_desired - needed_capacity
        logger.info("SCALING IN: %s → %s (-%s)", current_desired, needed_capacity, delta)
        return "scale_in"

    logger.info("Capacity optimal: %s instances", current_desired)
    return "none"


def send_cloudwatch_metrics(  # noqa: PLR0913
    cloudwatch,
    project_id: str,
    asg_name: str,
    pending_jobs: int,
    running_jobs: int,
    needed_capacity: int,
    current_desired: int,
    pending_instances: int,
    running_instances: int,
    imminent_capacity: int,
) -> None:
    """Send metrics to CloudWatch."""
    metric_data = [
        {"MetricName": "PendingJobs", "Value": pending_jobs, "Unit": "Count"},
        {"MetricName": "RunningJobs", "Value": running_jobs, "Unit": "Count"},
        {"MetricName": "DesiredCapacity", "Value": needed_capacity, "Unit": "Count"},
        {"MetricName": "CurrentCapacity", "Value": current_desired, "Unit": "Count"},
        {"MetricName": "PendingInstances", "Value": pending_instances, "Unit": "Count"},
        {"MetricName": "RunningInstances", "Value": running_instances, "Unit": "Count"},
        {"MetricName": "ImminentCapacity", "Value": imminent_capacity, "Unit": "Count"},
    ]

    timestamp = datetime.now(tz=UTC)
    for metric in metric_data:
        metric["Timestamp"] = timestamp
        metric["Dimensions"] = [
            {"Name": "ProjectId", "Value": str(project_id)},
            {"Name": "ASGName", "Value": asg_name},
        ]

    cloudwatch.put_metric_data(Namespace="GitLab/CI", MetricData=metric_data)


def lambda_handler(event, context) -> dict:  # noqa: ARG001
    """
    GitLab-driven autoscaler with gradual scaling.

    Main orchestration function that delegates to specialized functions.
    """
    # Load environment variables
    gitlab_token = os.environ["GITLAB_TOKEN"]
    project_id = os.environ["GITLAB_PROJECT_ID"]
    gitlab_url = os.environ.get("GITLAB_URL", "https://gitlab.com")
    runner_tag = os.environ.get("RUNNER_TAG", "nixos")
    asg_name = os.environ.get("ASG_NAME", "nixos-gitlab-runners")

    # Scaling configuration
    jobs_per_instance = int(os.environ.get("JOBS_PER_INSTANCE", "1"))
    min_idle_instances = int(os.environ.get("MIN_IDLE_INSTANCES", "0"))
    max_instances = int(os.environ.get("MAX_INSTANCES", "10"))
    scale_factor = float(os.environ.get("SCALE_FACTOR", "1.0"))
    max_growth_rate = int(os.environ.get("MAX_GROWTH_RATE", "10"))
    scale_in_threshold = float(os.environ.get("SCALE_IN_THRESHOLD", "0.3"))

    # Initialize clients
    http = urllib3.PoolManager()
    cloudwatch = boto3.client("cloudwatch")
    autoscaling = boto3.client("autoscaling")

    try:
        # Step 1: Get GitLab jobs
        pending_count, running_count = get_gitlab_jobs(
            http,
            gitlab_url,
            project_id,
            gitlab_token,
            runner_tag,
        )

        # Step 2: Get ASG state
        asg_state = get_asg_state(autoscaling, asg_name)

        # Log current state
        logger.info("ASG State:")
        logger.info("  - Desired: %s", asg_state["current_desired"])
        logger.info("  - Pending: %s (starting up)", asg_state["pending_instances"])
        logger.info("  - Running: %s (in service)", asg_state["running_instances"])
        logger.info("  - Terminating: %s", asg_state["terminating_instances"])
        logger.info("  - Total: %s", asg_state["total_instances"])

        logger.info("Jobs State:")
        logger.info("  - Pending: %s", pending_count)
        logger.info("  - Running: %s", running_count)

        # Calculate imminent capacity
        imminent_capacity = asg_state["total_instances"] * jobs_per_instance
        logger.info("Imminent capacity: %s jobs", imminent_capacity)
        logger.info(
            "   (%s instances x %s jobs/instance)",
            asg_state["total_instances"],
            jobs_per_instance,
        )

        # Step 3: Calculate needed capacity
        needed_capacity, needed_for_running, additional_capacity = calculate_needed_capacity(
            pending_count,
            running_count,
            asg_state["total_instances"],
            jobs_per_instance,
            scale_factor,
            max_growth_rate,
            min_idle_instances,
            max_instances,
            asg_state["current_max"],
        )

        # Log capacity calculation
        logger.info("Capacity calculation:")
        logger.info("  - For running jobs: %s instances", needed_for_running)
        logger.info(
            "  - For pending jobs: %s instances (scaled by %s)",
            additional_capacity,
            scale_factor,
        )
        logger.info("  - Final needed: %s instances", needed_capacity)

        # Step 4: Apply scaling decision
        scaling_action = apply_scaling_decision(
            autoscaling,
            asg_name,
            needed_capacity,
            asg_state["current_desired"],
            running_count,
            asg_state["total_instances"],
            jobs_per_instance,
            scale_in_threshold,
        )

        # Step 5: Send metrics to CloudWatch
        send_cloudwatch_metrics(
            cloudwatch,
            project_id,
            asg_name,
            pending_count,
            running_count,
            needed_capacity,
            asg_state["current_desired"],
            asg_state["pending_instances"],
            asg_state["running_instances"],
            imminent_capacity,
        )

        # Return success response
        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "pending_jobs": pending_count,
                    "running_jobs": running_count,
                    "current_capacity": asg_state["current_desired"],
                    "needed_capacity": needed_capacity,
                    "pending_instances": asg_state["pending_instances"],
                    "running_instances": asg_state["running_instances"],
                    "imminent_capacity": imminent_capacity,
                    "scaling_action": scaling_action,
                    "scale_factor": scale_factor,
                    "max_growth_rate": max_growth_rate,
                }
            ),
        }

    except Exception as e:
        error_msg = f"Error: {e!s}"
        logger.exception(error_msg)

        # Send error metric
        try:
            cloudwatch.put_metric_data(
                Namespace="GitLab/CI",
                MetricData=[
                    {
                        "MetricName": "CollectorErrors",
                        "Value": 1,
                        "Unit": "Count",
                        "Timestamp": datetime.now(tz=UTC),
                        "Dimensions": [{"Name": "ProjectId", "Value": str(project_id)}],
                    }
                ],
            )
        except Exception:
            logger.warning("Failed to send error metric to CloudWatch")

        return {"statusCode": 500, "body": json.dumps({"error": error_msg})}
