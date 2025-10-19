import json
import os
import urllib3
import boto3
from datetime import datetime


def lambda_handler(event, context):
    """
    Lambda function to collect GitLab job metrics and send to CloudWatch
    """

    # Environment variables
    gitlab_token = os.environ["GITLAB_TOKEN"]
    project_id = os.environ["GITLAB_PROJECT_ID"]
    gitlab_url = os.environ.get("GITLAB_URL", "https://gitlab.com")

    # Initialize clients
    http = urllib3.PoolManager()
    cloudwatch = boto3.client("cloudwatch")

    try:
        # GitLab API endpoint for project jobs
        api_url = f"{gitlab_url}/api/v4/projects/{project_id}/jobs"

        # Headers for GitLab API
        headers = {"PRIVATE-TOKEN": gitlab_token, "Content-Type": "application/json"}

        # Get pending jobs
        pending_response = http.request("GET", f"{api_url}?scope[]=pending", headers=headers)

        # Get running jobs
        running_response = http.request("GET", f"{api_url}?scope[]=running", headers=headers)

        if pending_response.status == 200 and running_response.status == 200:
            pending_jobs = json.loads(pending_response.data.decode("utf-8"))
            running_jobs = json.loads(running_response.data.decode("utf-8"))

            pending_count = len(pending_jobs)
            running_count = len(running_jobs)
            total_active_jobs = pending_count + running_count

            print(f"Pending jobs: {pending_count}")
            print(f"Running jobs: {running_count}")
            print(f"Total active jobs: {total_active_jobs}")

            # Send metrics to CloudWatch
            cloudwatch.put_metric_data(
                Namespace="GitLab/CI",
                MetricData=[
                    {
                        "MetricName": "PendingJobs",
                        "Value": pending_count,
                        "Unit": "Count",
                        "Dimensions": [{"Name": "ProjectId", "Value": str(project_id)}],
                        "Timestamp": datetime.utcnow(),
                    },
                    {
                        "MetricName": "RunningJobs",
                        "Value": running_count,
                        "Unit": "Count",
                        "Dimensions": [{"Name": "ProjectId", "Value": str(project_id)}],
                        "Timestamp": datetime.utcnow(),
                    },
                    {
                        "MetricName": "TotalActiveJobs",
                        "Value": total_active_jobs,
                        "Unit": "Count",
                        "Dimensions": [{"Name": "ProjectId", "Value": str(project_id)}],
                        "Timestamp": datetime.utcnow(),
                    },
                ],
            )

            return {
                "statusCode": 200,
                "body": json.dumps(
                    {
                        "message": "Metrics collected successfully",
                        "pending_jobs": pending_count,
                        "running_jobs": running_count,
                        "total_active_jobs": total_active_jobs,
                    }
                ),
            }
        error_msg = f"GitLab API error - Pending: {pending_response.status}, Running: {running_response.status}"
        print(error_msg)
        return {"statusCode": 500, "body": json.dumps({"error": error_msg})}

    except Exception as e:
        error_msg = f"Error collecting GitLab metrics: {str(e)}"
        print(error_msg)
        return {"statusCode": 500, "body": json.dumps({"error": error_msg})}
