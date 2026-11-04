# 1. Project Overview

## 1.1 Project Title

**Project Retrograde – Academic Performance Portal with Login-Based AWS Auto Scaling**

## 1.2 Background

Project Retrograde is a web-based academic performance portal designed to allow candidate/student users to sign in and view their academic performance information.

The application is implemented using FastAPI and an HTML frontend. Its cloud infrastructure is designed to distribute incoming web requests and dynamically adjust the number of EC2 application instances based on a custom application metric: the number of active logins.

Unlike traditional scaling approaches that rely exclusively on infrastructure metrics such as CPU utilization, this project uses a business-level metric (active logged-in users) to initiate scaling actions.

## 1.3 Problem Statement

Web applications may experience periods of increased demand, particularly when large numbers of students access their academic results simultaneously.

A single server may become a bottleneck during these periods, while permanently maintaining multiple servers can increase operational costs during periods of low demand.

Project Retrograde explores an AWS-based solution that distributes incoming traffic through an Application Load Balancer and dynamically adjusts EC2 capacity through an Auto Scaling Group based on active-login metrics.

## 1.4 Project Objectives

The main objectives of the project are to:

- Develop a web-based academic performance portal.
- Implement backend functionality using FastAPI.
- Track active user sessions and login activity.
- Publish custom application metrics to Amazon CloudWatch.
- Configure CloudWatch alarms to trigger EC2 Auto Scaling policies.
- Distribute incoming HTTP traffic using an Application Load Balancer.
- Provision cloud infrastructure using Terraform.
- Develop a login simulation utility to test the configured scaling threshold.
- Demonstrate how application-level metrics can influence cloud infrastructure scaling decisions.

## 1.5 Project Scope

The project covers the development and deployment architecture of an academic performance portal using AWS services.

The scope includes:

- Development of the FastAPI backend.
- Design of the HTML frontend.
- Login and session tracking.
- Custom CloudWatch metric publishing.
- EC2 instance provisioning.
- Application Load Balancer configuration.
- EC2 Auto Scaling Group configuration.
- Amazon S3 storage for application deployment files.
- IAM roles and permissions.
- Automated infrastructure provisioning using Terraform.
- Functional and scaling tests.

The supplied Terraform configuration uses an HTTP listener on port 80 and forwards requests to the application on port 8000. Production-grade authentication, HTTPS configuration and shared persistent session storage are not demonstrated in the current implementation.

## 1.6 Technologies and AWS Services

The project uses the following technologies and services:

| Technology / Service | Purpose |
|---|---|
| Python | Backend development and automation |
| FastAPI | Backend web application framework |
| Uvicorn | Runs the FastAPI application |
| Jinja2 | HTML template rendering |
| Amazon EC2 | Hosts the application |
| EC2 Auto Scaling | Dynamically adjusts instance capacity |
| Application Load Balancer | Distributes incoming traffic |
| Amazon CloudWatch | Collects metrics and evaluates alarms |
| Amazon S3 | Stores application deployment files |
| AWS IAM | Manages permissions and access |
| AWS Systems Manager | Supports instance management |
| Terraform | Infrastructure as Code |
| GitHub Actions | Repository automation and validation |

## 1.7 Expected Outcomes

The expected outcomes of the project include:

1. A functioning academic performance portal.
2. Successful distribution of incoming requests through an Application Load Balancer.
3. Collection of active-login metrics through Amazon CloudWatch.
4. Automatic scaling of EC2 instances when configured login thresholds are exceeded.
5. Reduction of unnecessary compute capacity during periods of lower demand.
6. A reproducible infrastructure deployment process using Terraform.
7. Practical demonstration of application-level Auto Scaling using AWS services.

## 1.8 Project Team and Responsibilities

The project is undertaken by a group of members with different responsibilities.

The following information should be completed using the actual group assignments:

| Role | Responsibility | Assigned Member |
|---|---|---|
| AWS Console Administrator | Manages AWS resources and infrastructure | [Member Name] |
| Scaling Policy Creator | Configures Auto Scaling policies | [Member Name] |
| Test Engineer | Performs functional and scaling tests | [Member Name] |
| Documentation Specialist | Prepares technical documentation and project reports | [Member Name] |
| [Additional Role] | [Responsibility] | [Member Name] |

## 1.9 Conclusion

Project Retrograde demonstrates how AWS cloud services can be integrated to create a scalable web application. By combining application-level monitoring, custom CloudWatch metrics, an Application Load Balancer and EC2 Auto Scaling, the project explores an approach to adjusting computing resources according to application demand.

The project also provides practical experience in cloud infrastructure management, automation, application development, monitoring and testing.
