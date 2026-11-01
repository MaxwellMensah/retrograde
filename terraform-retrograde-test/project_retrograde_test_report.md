# Project Retrograde: Infrastructure Test Report & Showcase

## 1. Executive Summary

**Project Retrograde** is a high-availability, self-scaling cloud application platform deployed on Amazon Web Services (AWS) using Infrastructure as Code (IaC) via Terraform. 

The objective of this test execution was to evaluate and prove the dynamic elasticity of the infrastructure under simulated traffic loads. Using custom application-level telemetry published to Amazon CloudWatch, the system detects user login bursts and automatically scales compute capacity from a baseline single instance up to multiple instances behind an Application Load Balancer (ALB). Once peak demand subsides, a automated scale-in mechanism scales the infrastructure back down to minimal baseline capacity to eliminate unnecessary operational costs.

---

## 2. Architecture & Infrastructure Overview

The infrastructure was deployed as an isolated environment via Terraform. The environment comprises 19 distinct AWS resources configured to enforce least privilege, high availability, and dynamic autoscaling.

```
                    +------------------------------------+
                    |        Internet Traffic           |
                    +------------------------------------+
                                      |
                                      v
                    +------------------------------------+
                    |   Application Load Balancer (ALB)  |
                    |    (Public Subnets across AZs)     |
                    +------------------------------------+
                                      |
                           (Port 8000 Forwarding)
                                      v
                    +------------------------------------+
                    |     Auto Scaling Group (ASG)       |
                    |   Target: 1 to 3 x t3.micro EC2s   |
                    +------------------------------------+
                      /                                \
                     v                                  v
+-----------------------------------+   +------------------------------------+
|         Private S3 Bucket         |   |         Amazon CloudWatch          |
| (Holds app code & Jinja templates)|   |  (Ingests custom ActiveLogins)     |
+-----------------------------------+   +------------------------------------+
```

### Key Architectural Components

1. **VPC & Networking:** Utilizes an existing Amazon VPC (`mygroupvpc`) spanning multiple Availability Zones (AZs). Public subnets were dynamically resolved to provision the ALB across multiple AZs for regional redundancy.
2. **Application Load Balancer (ALB):**
   * Serves as the public ingress point on HTTP port 80.
   * Enforces session stickiness using `lb_cookie` (24-hour duration) to ensure predictable metric emission and user tracking across pooled instances.
   * Performs continuous health checking on `/health` (15s interval, 2-strike healthy/3-strike unhealthy threshold).
3. **Application Storage & Provisioning (S3):**
   * A private Amazon S3 bucket stores the FastAPI application core (`app.py`) and HTML frontend templates (`retro_test.html`).
   * Content integrity is maintained via `md5` file hashes (`etag`). Updates to application files automatically trigger Launch Template version refreshes in Terraform.
4. **Compute & Auto Scaling Group (ASG):**
   * **Base AMI:** Amazon Linux 2023 (`al2023-ami-2023*-x86_64`).
   * **Instance Profile & Security:** EC2 instances run inside a strict Security Group that only permits incoming traffic on port 8000 originating directly from the ALB Security Group.
   * **Bootstrap Script (`user_data.sh.tpl`):** On launch, EC2 instances pull application artifacts from S3, install Python dependencies (`FastAPI`, `Uvicorn`, `Jinja2`, `Boto3`), configure environment variables, and launch the application as a `systemd` service (`retrograde.service`).
5. **Telemetry & IAM Permissions:**
   * An IAM role with embedded inline policies permits EC2 instances to pull artifacts from the private S3 bucket and publish telemetry to CloudWatch under the custom metric namespace `Retrograde/Portal`.
   * AWS Systems Manager (SSM) Session Manager policy is attached for secure, keyless SSH access during debugging.

---

## 3. Dynamic Auto-Scaling Design

Instead of relying on generic CPU or memory metrics, Project Retrograde scales directly on real-time business telemetry: **Active Logins**.

```
                           [ ActiveLogins Metric ]
                                      |
                    +-----------------+-----------------+
                    |                                   |
           Active Logins > 12                  Active Logins < 8
         (1-Minute Period, 1 Eval)           (5-Minute Period, 5 Evals)
                    |                                   |
                    v                                   v
      [ Alarm: retrograde-logins-high ]    [ Alarm: retrograde-logins-low ]
                    |                                   |
                    v                                   v
         Scale Out Step Policy               Scale In Step Policy
         (Capacity set to 2 or 3)           (Capacity reduced to min=1)
```

* **Custom Metric:** `ActiveLogins` emitted to namespace `Retrograde/Portal`.
* **Scale-Out Trigger (`retrograde-logins-high`):** Evaluated when total active logins exceed 12 (`GreaterThanThreshold`).
  * **13 to 24 users:** Scales capacity from 1 to 2 instances.
  * **25+ users:** Scales capacity to 3 instances.
* **Scale-In Trigger (`retrograde-logins-low`):** Evaluated when active logins drop below 8 (`LessThanThreshold`) over a sustained 5-minute evaluation window, returning capacity to the baseline minimum of 1 instance.

---

## 4. Test Execution & Step-by-Step Verification

### Step 1: Automated Deployment & Validation
Deployment was executed using Terraform from VS Code:
```bash
cd terraform-retrograde-test
terraform init
terraform plan
terraform apply -auto-approve
```
* **Result:** 19 resources successfully created in 5m 12s. Outputs returned the active ALB endpoint (`http://retrograde-alb-792843536.us-east-1.elb.amazonaws.com`).

### Step 2: Load Simulation (13 Concurrent Users)
The load generation script `simulate_logins.py` was executed to simulate user traffic crossing the trigger threshold:
```bash
python simulate_logins.py --url http://retrograde-alb-792843536.us-east-1.elb.amazonaws.com --users 13
```
* **Terminal Output Verification:**
  ```text
  🚀 Scaling Triggered (ASG launching)
  active logins on the instance that answered: 15 (threshold: more than 12)
  answered by instance i-0a0710777d72569b3 | instances in service: 1
  ```

### Step 3: AWS Console Telemetry Verification
1. **Amazon CloudWatch Metrics:** Navigated to `Retrograde/Portal` > `ActiveLogins`. Switched graph statistics to **Sum**. A vertical spike confirmed the active user count jumped to 15.
2. **Amazon CloudWatch Alarms:** The `retrograde-logins-high` alarm transitioned to the **ALARM** state (Red).
3. **Auto Scaling Group Activity:** Inspected `retrograde-asg` Activity History. An event was logged: `Launching a new EC2 instance: i-0b47280853a917ffc in response to CloudWatch alarm`.
4. **AWS CLI Query:** Executed the instance status query:
   ```bash
   aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names retrograde-asg \
     --query 'AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState,HealthStatus]' \
     --output table --region us-east-1
   ```
   * **Output:**
     ```text
     --------------------------------------------
     |          DescribeAutoScalingGroups       |
     +-------------------+------------+---------+
     |  i-0a0710777d72569b3 | InService  | Healthy |
     |  i-0b47280853a917ffc | InService  | Healthy |
     +-------------------+------------+---------+
     ```

### Step 4: Scale-In Behavior Verification
Following completion of the script, active login connections timed out. 
1. `ActiveLogins` metric dropped below the threshold of 8.
2. Sustained low traffic satisfied the 5-minute evaluation period for `retrograde-logins-low`.
3. Auto Scaling Group initiated instance termination, removing `i-0b47280853a917ffc`.
4. Web UI status indicator updated to confirm return to baseline:
   > **Normal Capacity (1 Instance) [2 Active Logins]**

---

## 5. Teardown & Environment Cleanup

To maintain cost efficiency, the infrastructure was decommissioned using Terraform:
```bash
terraform destroy -auto-approve
```
* **Result:** All 19 resources (ALB, Target Group, ASG, Launch Templates, Security Groups, IAM Policies, S3 Bucket, CloudWatch Alarms) were cleanly removed. Zero persistent orphan resources remained.

---

## 6. Key Learnings & Engineering Highlights

1. **Business-Centric Scaling:** Scaling on custom application metrics (`ActiveLogins`) provides faster, more accurate elasticity than traditional system-level metrics (CPU/RAM).
2. **Infrastructure as Code Control:** Decoupling application test infrastructure (`terraform-retrograde-test`) from baseline code ensured safe, non-destructive validation without impacting primary configurations.
3. **Graceful De-provisioning:** Configuring `force_destroy = true` on the application S3 bucket enabled frictionless single-command teardown (`terraform destroy`), avoiding blocked deletions due to non-empty bucket constraints.