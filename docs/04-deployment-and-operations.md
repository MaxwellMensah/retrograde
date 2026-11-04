# Project Retrograde – Deployment and Operations Guide

## 1. Introduction

This document describes the deployment and operational procedures for Project Retrograde.

The project uses Terraform to define AWS infrastructure and EC2 user data to initialize application instances.

The deployment process is designed to create an environment in which users can access the academic performance portal through an Application Load Balancer while EC2 instances are managed by an Auto Scaling Group.

This guide covers:

- Deployment prerequisites.
- AWS environment preparation.
- Terraform initialization and deployment.
- Application verification.
- Monitoring and scaling verification.
- Troubleshooting.
- Resource cleanup.

**Important:** The procedures in this document describe the intended deployment process. Successful deployment must be demonstrated with actual AWS evidence. The presence of Terraform configuration files alone does not prove that the infrastructure has been deployed successfully.

## 2. Deployment Architecture

The deployment process involves the following components:

1. Terraform provisions the required AWS resources.
2. Amazon S3 stores the application deployment files.
3. EC2 instances launch through the configured launch template.
4. The EC2 bootstrap script retrieves the application files from S3.
5. Python dependencies are installed.
6. The FastAPI application starts on port 8000.
7. The Application Load Balancer checks the health of registered instances.
8. Users access the application through the load balancer.
9. CloudWatch monitors application activity and evaluates scaling alarms.

## 3. Deployment Prerequisites

Before deployment, the team should ensure that the required tools, permissions, and AWS resources are available.

### 3.1 Required Software

| Software | Purpose |
|---|---|
| Git | Cloning and managing the project repository. |
| Python | Running the FastAPI application locally and managing dependencies. |
| pip | Installing Python packages. |
| AWS CLI | Interacting with AWS services from the terminal. |
| Terraform | Provisioning AWS infrastructure. |
| Web browser | Accessing and testing the deployed application. |

### 3.2 AWS Requirements

The deployment environment requires:

- An active AWS account.
- An IAM identity with permission to create and manage the required resources.
- An existing VPC matching the configured VPC lookup.
- At least two suitable subnets in different Availability Zones for the Application Load Balancer.
- Appropriate network routes and internet connectivity for the intended public-facing architecture.
- An S3 bucket for application deployment files.
- Sufficient AWS service quotas for the requested resources.

The reviewed Terraform configuration uses `mygroupvpc` as the default VPC name lookup value. The team must confirm that this matches the actual VPC in its AWS environment.

### 3.3 AWS Credentials

AWS CLI credentials should be configured using an authorized IAM identity.

For example:

```bash
aws configure
```

The AWS CLI may request:

- AWS Access Key ID.
- AWS Secret Access Key.
- Default AWS Region.
- Default output format.

Use credentials belonging to an authorized project team identity.

Never place AWS credentials directly inside application source files, Terraform configuration, screenshots, or GitHub repositories.

## 4. Preparing the Project Repository

### 4.1 Clone the Repository

The project repository should first be downloaded to the local development machine.

Example:

```bash
git clone <PROJECT_REPOSITORY_URL>
```

Move into the project directory:

```bash
cd retrograde-main
```

The actual repository name may differ depending on the team's Git hosting configuration.

### 4.2 Review the Repository

Before deployment, confirm that the required files are available.

The expected important files include:

```text
app.py
simulate_logins.py
requirements.txt
templates/index.html
AWS_SETUP.md
README.md
terraform-retrograde-test/
```

Review the setup instructions and compare them against the actual repository structure.

### 4.3 Known Path Issues

The repository review identified several inconsistencies:

1. The Terraform/bootstrap configuration references `templates/retro_test.html`, while the repository contains `templates/index.html`.
2. The README refers to a nested `retrograde/` directory, while the application files are located at the repository root.
3. The GitHub Actions workflow references paths that do not match the supplied repository structure.
4. The dependency installation instructions should be checked against the actual `requirements.txt`.

These issues have been documented for later correction. They should be resolved before relying on a clean deployment.

## 5. Preparing the Python Application

The application can first be tested locally before deployment.

### 5.1 Create a Virtual Environment

From the application root directory, run:

```bash
python -m venv venv
```

Activate the virtual environment on Windows Command Prompt:

```cmd
venv\Scripts\activate
```

On Windows PowerShell:

```powershell
.\venv\Scripts\Activate.ps1
```

### 5.2 Install Dependencies

Install the dependencies listed in the project file:

```bash
pip install -r requirements.txt
```

### 5.3 Start the Application

Run the FastAPI application using Uvicorn:

```bash
uvicorn app:app --host 0.0.0.0 --port 8000
```

This command assumes that the FastAPI application object is named `app` inside `app.py`.

### 5.4 Test Locally

Open a browser and visit:

```text
http://127.0.0.1:8000
```

The application should display the portal homepage if it has started successfully.

Test the health endpoint:

```text
http://127.0.0.1:8000/health
```

The expected response should indicate that the application is healthy.

The local test helps identify application startup problems before AWS infrastructure is deployed.

## 6. Preparing the Amazon S3 Deployment Files

Amazon S3 is used to store application files that EC2 instances retrieve during initialization.

### 6.1 Uploading Application Files

The team should ensure that the required application files are uploaded to the configured S3 bucket.

These may include:

- `app.py`
- `requirements.txt`
- The required HTML template.
- Any additional application assets referenced by the code.

The exact object keys must match those used by the EC2 bootstrap script.

### 6.2 S3 Access Configuration

The S3 bucket should be configured securely.

Recommended controls include:

- Enable S3 Block Public Access.
- Avoid unnecessary public bucket policies.
- Use encryption at rest.
- Grant the EC2 instance role only the required object-reading permissions.
- Avoid uploading AWS credentials or other secrets.

### 6.3 Verify Object Names

The S3 object names must match the names expected by the bootstrap script.

The identified `retro_test.html` versus `index.html` mismatch should be resolved before deployment.

## 7. Deploying the AWS Infrastructure with Terraform

Terraform is responsible for provisioning the AWS resources required by Project Retrograde.

### 7.1 Open the Terraform Directory

From the repository root:

```bash
cd terraform-retrograde-test
```

### 7.2 Initialize Terraform

Run:

```bash
terraform init
```

This initializes Terraform and downloads the required provider plugins.

### 7.3 Format the Configuration

Run:

```bash
terraform fmt -check -recursive
```

This checks whether Terraform files follow the expected formatting conventions.

### 7.4 Validate the Configuration

Run:

```bash
terraform validate
```

This checks the Terraform configuration for structural and syntax-related errors.

### 7.5 Review the Deployment Plan

Run:

```bash
terraform plan
```

Terraform generates a proposed list of infrastructure changes.

The team should review this plan before applying it.

Confirm that:

- The intended VPC is selected.
- The correct subnets are used.
- Security group rules are appropriate.
- The S3 bucket and object references are correct.
- The IAM permissions are appropriate.
- The Auto Scaling limits are correct.
- The expected resources are being created or modified.

### 7.6 Apply the Configuration

After the team has reviewed and approved the deployment plan, run:

```bash
terraform apply
```

Terraform will request confirmation before proceeding unless an approved automation workflow is being used.

Review the proposed changes carefully before approving.

### 7.7 Record Terraform Outputs

After a successful deployment, inspect the available outputs:

```bash
terraform output
```

Record useful deployment information such as the load balancer endpoint.

Do not publish sensitive infrastructure identifiers or account information unnecessarily.

## 8. Verifying the Deployment

After Terraform completes, the team should confirm that the infrastructure and application are functioning correctly.

### 8.1 Verify EC2 Instances

Open the Amazon EC2 console.

Navigate to the Instances section.

Confirm that:

- The expected EC2 instances have launched.
- The instances are in the intended VPC and subnets.
- The instances use the expected launch template.
- The instance status checks pass.
- The intended security groups are attached.

### 8.2 Verify the Auto Scaling Group

Navigate to the EC2 Auto Scaling section.

Open the Project Retrograde Auto Scaling Group.

Check:

- Minimum capacity.
- Maximum capacity.
- Desired capacity.
- Current in-service instance count.
- Scaling policies.
- Activity history.

The default reviewed capacity limits are one minimum instance and three maximum instances.

### 8.3 Verify the Application Load Balancer

Open the EC2 Load Balancers section.

Select the Project Retrograde load balancer.

Confirm that:

- The load balancer exists.
- The listener is configured on port 80.
- The listener forwards requests to the correct target group.
- The intended subnets are attached.
- The security group permits the expected incoming traffic.

### 8.4 Verify Target Group Health

Open the target group associated with the load balancer.

Check the health status of registered EC2 instances.

The expected status for a functioning application target is:

```text
Healthy
```

If an instance is unhealthy, investigate the application startup process, health-check configuration, security groups, and application port.

### 8.5 Verify the Application

Copy the Application Load Balancer DNS name and open it in a browser.

The expected result is that the academic performance portal loads.

Also test the health endpoint using:

```text
http://<LOAD_BALANCER_DNS>/health
```

Replace the placeholder with the actual load balancer DNS name.

## 9. Monitoring the Application with CloudWatch

CloudWatch is used to monitor application activity and evaluate scaling conditions.

### 9.1 Check Custom Metrics

Open Amazon CloudWatch.

Navigate to Metrics and locate the custom namespace:

```text
Retrograde/Portal
```

Check for the following metrics:

- `ActiveLogins`
- `LoginEvents`

The metrics should appear after the application successfully publishes data.

### 9.2 Check CloudWatch Alarms

Navigate to CloudWatch Alarms.

Inspect the Project Retrograde scaling alarms.

Review:

- Metric name.
- Metric namespace.
- Metric dimensions.
- Statistic.
- Evaluation period.
- Threshold.
- Alarm state.
- Alarm history.

The reviewed scale-out condition uses ActiveLogins greater than 12 for one 60-second evaluation period.

The optional scale-in condition uses ActiveLogins below 8 for five 60-second evaluation periods.

### 9.3 Monitor Alarm History

Alarm history helps the team determine whether an alarm changed state.

Record:

- When the alarm entered the ALARM state.
- The metric value that triggered the alarm.
- The action associated with the alarm.
- Whether the scaling action succeeded.

## 10. Verifying Auto Scaling

The purpose of the project is to demonstrate how application activity can influence EC2 capacity.

The team should verify this through controlled testing.

### 10.1 Record Initial Capacity

Before testing, record:

- Desired capacity.
- Minimum capacity.
- Maximum capacity.
- Number of running instances.
- Number of healthy target group instances.

### 10.2 Generate Controlled Login Activity

Use the project's login activity helper script or another approved test method.

Generate a small amount of controlled demonstration activity.

Avoid excessive or unbounded requests.

### 10.3 Observe CloudWatch

Check whether the ActiveLogins metric changes as expected.

Confirm that the metric dimensions and values correspond to the intended application environment.

### 10.4 Observe the Scaling Alarm

If the configured threshold is reached, inspect the CloudWatch alarm state.

Record the transition and timestamp.

### 10.5 Observe Auto Scaling Activity

Open the Auto Scaling Group activity history.

Check whether the scaling policy initiated an instance launch.

Confirm that the new instance:

- Launched successfully.
- Completed initialization.
- Started the application.
- Passed its health checks.
- Registered as a healthy target.

### 10.6 Verify Scale-In

If scale-in is enabled, observe the configured low-activity condition using an approved test process.

Confirm that the group reduces capacity without going below its minimum capacity.

**Important:** A CloudWatch alarm changing state does not automatically prove that EC2 scaling succeeded. The team must inspect the Auto Scaling activity history and instance health.

## 11. Operational Monitoring

During project operation, the team should monitor the following areas:

| Area | What to monitor |
|---|---|
| EC2 | Instance status, health checks, and resource utilization. |
| Auto Scaling | Desired capacity, actual capacity, and scaling activities. |
| ALB | Request handling, target health, and load balancer metrics. |
| CloudWatch | Custom metrics, alarms, and logs. |
| S3 | Required application objects and access configuration. |
| IAM | Role permissions and unexpected permission changes. |
| Application | API availability, errors, login activity, and session behaviour. |
| Billing | Resource usage and accumulated AWS charges. |

## 12. Troubleshooting

The following table describes common problems and possible investigation steps.

| Problem | Possible cause | Recommended investigation |
|---|---|---|
| Portal does not load | ALB or application issue. | Check listener, target health, and application status. |
| Target is unhealthy | Application is not running or health check fails. | Check user-data logs, port 8000, health-check path, and security groups. |
| HTTP 502 or 503 | No healthy targets or backend failure. | Inspect target group health and application startup logs. |
| Application files are missing | S3 object or permission problem. | Check bucket, object keys, and instance role permissions. |
| Template does not load | Incorrect template filename or path. | Compare the S3 object key with the application and bootstrap configuration. |
| No CloudWatch metrics | Metric publication failed. | Check IAM permissions, namespace, dimensions, region, and application logs. |
| CloudWatch alarm does not trigger | Metric or alarm configuration mismatch. | Inspect metric values, statistic, threshold, and evaluation periods. |
| EC2 instance does not scale out | Scaling policy or ASG problem. | Inspect alarm actions, ASG limits, scaling activity history, and service quotas. |
| Login sessions behave inconsistently | Session state is stored locally on individual instances. | Investigate the instance handling each request and the session architecture. |

## 13. Deployment Cleanup and Resource Management

AWS resources may continue generating charges even when users are no longer accessing the application.

After testing, the team should review which resources are still required.

### 13.1 Review Resources

Before removing infrastructure, identify all resources created for Project Retrograde.

Confirm that none of the resources are shared with other projects or users.

### 13.2 Terraform Cleanup

If the team has approved removal of the test environment, navigate to the Terraform directory and review the destruction plan:

```bash
terraform plan -destroy
```

After confirming that the plan only affects the intended project resources, execute:

```bash
terraform destroy
```

Review the resources carefully before confirming.

### 13.3 Verify Cleanup

After destruction, check the AWS console to confirm that unnecessary resources have been removed.

Pay attention to:

- EC2 instances.
- Auto Scaling Groups.
- Load balancers.
- Target groups.
- Security groups.
- EBS volumes.
- S3 buckets and stored objects.
- CloudWatch alarms and log groups.
- IAM roles and policies created exclusively for the project.

Some resources may be shared or managed outside Terraform. Handle those separately and only with approval.

Retain required project evidence before deleting any resource or log that may be needed for assessment.

## 14. Deployment Evidence Requirements

The team should capture screenshots and other evidence during deployment.

Recommended evidence includes:

1. Terraform initialization output.
2. Terraform validation output.
3. Terraform deployment plan.
4. Terraform apply completion.
5. EC2 instance list.
6. Auto Scaling Group configuration.
7. Application Load Balancer configuration.
8. Target group health.
9. S3 bucket and application object list.
10. IAM role and permission configuration.
11. CloudWatch custom metrics.
12. CloudWatch alarm configuration.
13. CloudWatch alarm history.
14. Auto Scaling activity history.
15. Successful portal homepage.
16. Successful application health-check response.
17. Resource cleanup confirmation.

Screenshots should be readable and should not expose credentials, private keys, session tokens, student records, or unnecessary AWS account information.

## 15. Conclusion

Project Retrograde's deployment process combines infrastructure automation with application initialization and AWS monitoring.

Terraform defines the infrastructure, S3 provides application deployment files, EC2 instances host the FastAPI application, and the Application Load Balancer distributes incoming traffic.

CloudWatch monitors application activity and evaluates scaling conditions, while the Auto Scaling Group adjusts the number of EC2 instances when the configured policies are triggered.

Successful deployment must be confirmed through application tests, AWS resource checks, CloudWatch metrics, and Auto Scaling activity records.

The team should also ensure that all documented deployment inconsistencies are corrected before treating the environment as ready for a repeatable or production deployment.
