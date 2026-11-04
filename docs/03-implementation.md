# Project Retrograde – Application and Infrastructure Implementation

## 1. Introduction

This document explains how the Project Retrograde application and its AWS infrastructure are implemented.

The project combines a Python-based web application with AWS services to demonstrate cloud hosting, application monitoring, and automatic scaling.

The implementation consists of two major areas:

1. Application implementation – developing the academic performance portal and its API endpoints.
2. Infrastructure implementation – defining and configuring the AWS resources required to host and scale the application.

## 2. Project Repository Structure

The supplied repository is organized as follows:

```text
retrograde-main/
├── .github/
│   └── workflows/
│       └── main.yml
├── app.py
├── simulate_logins.py
├── requirements.txt
├── templates/
│   └── index.html
├── AWS_SETUP.md
├── README.md
└── terraform-retrograde-test/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── user_data.sh.tpl
    └── project_retrograde_test_report.md
```

### 2.1 Description of Important Files

| File | Responsibility |
|---|---|
| `app.py` | Contains the FastAPI application and API routes. |
| `simulate_logins.py` | Generates demonstration login activity for testing. |
| `requirements.txt` | Lists Python dependencies. |
| `templates/index.html` | Contains the portal's HTML interface. |
| `main.tf` | Defines the main AWS infrastructure resources. |
| `variables.tf` | Defines configurable Terraform variables. |
| `outputs.tf` | Defines values Terraform displays after deployment. |
| `user_data.sh.tpl` | Contains EC2 instance initialization instructions. |
| `main.yml` | Defines the GitHub Actions workflow. |
| `AWS_SETUP.md` | Provides AWS setup information. |
| `README.md` | Contains project information and setup instructions. |

## 3. Application Implementation

### 3.1 Backend Framework

The backend is developed using Python and FastAPI.

FastAPI is a Python framework used to build web APIs. It allows the application to receive HTTP requests, process application logic, and return responses.

The project uses Uvicorn to run the FastAPI application.

Jinja2 is used alongside HTML templates to provide the web interface.

### 3.2 Application Routes

The application exposes several routes for interacting with the academic portal.

| Route | Description |
|---|---|
| `/` | Displays the portal homepage. |
| `/api/login` | Processes demonstration user login requests. |
| `/api/session/heartbeat` | Refreshes session activity. |
| `/api/session/logout` | Ends an active session. |
| `/api/grades/{student_id}` | Retrieves grade information using a student identifier. |
| `/api/traffic-status` | Returns application traffic/session information. |
| `/health` | Provides an application health-check endpoint. |

These routes allow the application to demonstrate basic portal functionality and generate activity that can be monitored by AWS.

### 3.3 Login and Session Management

The login functionality allows a demonstration user to submit login information.

When a login request is processed, the application checks the supplied information against its sample student records.

The application then maintains session information in memory.

The session-management process includes:

1. Receiving a login request.
2. Checking the demonstration user information.
3. Creating session information.
4. Tracking the user's activity.
5. Updating activity through heartbeat requests.
6. Removing the session when the user logs out.

The application uses a session timeout value of approximately 600 seconds by default.

**Important limitation:** The current implementation uses process-local memory. Session information is not automatically shared across EC2 instances, and it may be lost when an instance restarts.

A shared session store should be introduced before the application is used in a production environment.

### 3.4 Academic Grade Retrieval

The application includes a route for retrieving academic grades using a student identifier.

This functionality demonstrates how the portal can provide academic information through an API.

However, the endpoint requires further security validation.

The application must verify that the authenticated user is authorized to access the requested student's information. Simply supplying a valid student identifier should not be sufficient.

A proper implementation should prevent one student from accessing another student's academic records.

## 4. Application Activity and CloudWatch Metrics

One of the central features of Project Retrograde is the use of application activity to influence AWS scaling decisions.

The application tracks login and session activity and publishes custom metrics to CloudWatch.

### 4.1 Custom Metrics

The reviewed implementation uses two custom metrics:

| Metric | Purpose |
|---|---|
| `ActiveLogins` | Represents the application's active login/session activity. |
| `LoginEvents` | Represents login-related events. |

The metrics are published under the CloudWatch namespace:

```text
Retrograde/Portal
```

The configuration includes dimensions that identify the Auto Scaling Group and individual instances.

### 4.2 Metric Publishing Process

The general process is:

1. A user performs a login-related activity.
2. The application updates its internal session information.
3. The application prepares the relevant metric data.
4. The application publishes the metric to CloudWatch.
5. CloudWatch stores the metric.
6. Configured alarms evaluate the metric.

The reviewed application is designed to publish metric information approximately once per minute.

### 4.3 Why Custom Metrics Are Used

Traditional infrastructure scaling may use metrics such as CPU utilization.

However, CPU utilization does not always accurately represent the number of people actively using an application.

Project Retrograde demonstrates an alternative approach by using application-level activity.

For example, an application may have many active users performing lightweight operations without significantly increasing CPU utilization.

Monitoring login activity provides another signal that can be used when deciding whether additional application capacity is required.

## 5. Login Activity Simulation

The repository contains a helper script called:

```text
simulate_logins.py
```

The script is intended to generate demonstration login activity and retrieve traffic-status information from the application.

It supports testing the relationship between application login activity and CloudWatch metric publication.

### 5.1 Simulation Process

The intended process is:

1. Start the application.
2. Execute the login simulation script against the intended test endpoint.
3. Allow the script to submit demonstration login requests.
4. Observe the application's responses.
5. Check whether the expected metrics appear in CloudWatch.
6. Compare the metric values against the configured alarm thresholds.

The script generates sequential demonstration activity. It should not be considered a distributed load-testing or denial-of-service tool.

## 6. Infrastructure Implementation Using Terraform

Terraform is used to define the AWS infrastructure.

Infrastructure as Code (IaC) allows infrastructure resources to be described in configuration files instead of being created entirely through manual console operations.

The project's Terraform configuration is located in:

```text
terraform-retrograde-test/
```

### 6.1 Terraform Configuration Files

#### main.tf

This file contains the main infrastructure definitions.

It is responsible for defining the AWS resources required by the project.

These include the networking/security configuration, load balancing, EC2 launch configuration, Auto Scaling, monitoring, and related resources.

#### variables.tf

This file contains configurable values used by the infrastructure.

Examples include:

- AWS region.
- VPC name.
- EC2 instance type.
- Allowed network CIDR.
- Auto Scaling capacity limits.
- CloudWatch scaling thresholds.

The VPC lookup uses a configurable name, with `mygroupvpc` as the reviewed default.

#### outputs.tf

This file defines useful values that Terraform can display after infrastructure deployment.

Outputs can include resource identifiers and the load balancer endpoint, depending on the configuration.

#### user_data.sh.tpl

This template contains the initialization commands intended to run when a new EC2 instance starts.

It is responsible for preparing the instance to run the application.

## 7. EC2 Instance Initialization

New EC2 instances must be configured before they can serve application requests.

The project uses an EC2 user-data/bootstrap process.

The intended initialization sequence is:

1. Launch the EC2 instance.
2. Execute the user-data script.
3. Prepare the operating system and required directories.
4. Retrieve the application files from Amazon S3.
5. Install the Python dependencies.
6. Configure the application startup process.
7. Start the FastAPI application using Uvicorn.
8. Allow the load balancer health check to determine whether the instance is ready.

This process makes it possible for additional EC2 instances to be created without manually installing the application on each one.

### 7.1 Important Deployment Path Issue

A mismatch was identified during repository review.

The Terraform/bootstrap configuration references:

```text
templates/retro_test.html
```

However, the supplied repository contains:

```text
templates/index.html
```

This mismatch may prevent the expected HTML template from being uploaded or retrieved correctly.

It is recorded as a deferred issue and must be corrected before relying on a fresh deployment.

## 8. IAM Implementation

The EC2 application instances require permissions to communicate with selected AWS services.

The project uses an IAM role attached through an EC2 instance profile.

The reviewed permissions support:

- Reading required objects from Amazon S3.
- Publishing custom metrics to CloudWatch.
- Describing Auto Scaling Groups.
- Using AWS Systems Manager through its managed policy.

### 8.1 Why an IAM Role Is Used

An IAM role provides temporary credentials to an authorized AWS service or resource.

In this project, the EC2 instance receives permissions through its attached instance profile.

This avoids placing permanent AWS access keys directly inside the application code.

### 8.2 Security Considerations

The IAM policy should follow the principle of least privilege.

This means that an instance should only receive the permissions necessary to perform its assigned tasks.

For example, an application instance that only needs to retrieve files from a specific S3 bucket should not receive unrestricted access to every bucket in the AWS account.

## 9. Auto Scaling Implementation

The Auto Scaling Group is responsible for adjusting the number of EC2 instances based on the configured scaling policies.

The project uses CloudWatch alarms to monitor the ActiveLogins metric.

### 9.1 Scale-Out Configuration

The reviewed configuration uses the following default condition:

```text
Metric: ActiveLogins
Threshold: Greater than 12
Evaluation period: 60 seconds
Evaluation periods: 1
```

When the configured condition is met, the associated scale-out policy can increase the Auto Scaling Group's desired capacity.

The reviewed configuration supports capacity increases to two or three instances, subject to the policy and group limits.

### 9.2 Scale-In Configuration

An optional scale-in policy is also configured.

Its reviewed default condition is:

```text
Metric: ActiveLogins
Threshold: Below 8
Evaluation period: 60 seconds
Evaluation periods: 5
```

This requires the low-activity condition to persist across five evaluation periods before the alarm can trigger the configured scale-in action.

### 9.3 Scaling Capacity

The reviewed Auto Scaling Group defaults are:

| Configuration | Value |
|---|---:|
| Minimum capacity | 1 |
| Maximum capacity | 3 |
| Default instance type | t3.micro |

The actual number of running instances depends on the scaling policy, alarm state, available capacity, and successful instance initialization.

## 10. GitHub Actions and Workflow Automation

The repository includes a GitHub Actions workflow.

GitHub Actions is used to automate development and repository workflows.

A correctly configured workflow can help the team run checks whenever changes are pushed to the repository.

Possible checks include:

- Python dependency installation.
- Application tests.
- Code quality checks.
- Terraform formatting.
- Terraform validation.

However, the reviewed workflow contains path references that do not match the supplied repository structure.

For example, it references a nested `retrograde/` directory even though the application files are located at the repository root.

The workflow also requires its Terraform working directory to match:

```text
terraform-retrograde-test/
```

These path issues are documented for later correction.

## 11. Implementation Summary

Project Retrograde brings together application development and cloud infrastructure automation.

The application is built with FastAPI and uses login/session activity as a source of custom monitoring metrics.

Terraform defines the AWS infrastructure, while EC2 instances retrieve application files from S3 during initialization.

CloudWatch monitors application activity and evaluates scaling alarms. The Auto Scaling Group can then adjust the number of application instances based on the configured policies.

The implementation demonstrates the relationship between application development, cloud infrastructure, monitoring, and automated scaling.

Before production use, the team must address the documented deployment path inconsistencies, improve authentication and authorization, introduce shared session storage, and configure HTTPS.
