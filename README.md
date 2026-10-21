# SecureCloud — DevSecOps Deployment Platform

A cost-conscious DevSecOps project demonstrating how to build, secure, test, containerize, and deploy a Python application using automated security gates, Infrastructure as Code, and passwordless GitHub-to-AWS authentication.

The application itself is intentionally simple. The focus of the project is the **delivery and security platform surrounding the application**.

---

## Overview

SecureCloud implements a CI/CD workflow in which application changes are automatically tested and subjected to multiple security checks before they can be deployed.

### Workflow

```text
Developer
   │
   ▼
GitHub
   │
   ├── Pull Request / Push
   │
   ▼
GitHub Actions
   │
   ├── Gitleaks ─────────── Secret scanning
   ├── Semgrep ──────────── Static analysis
   ├── pip-audit ────────── Python dependency scanning
   ├── Checkov ───────────── Terraform/IaC security
   └── Trivy ─────────────── Container vulnerability scanning
   │
   ▼
Security gates pass
   │
   ▼
GitHub Actions
   │
   ├── OIDC authentication
   │
   ▼
AWS IAM
   │
   ▼
Amazon ECR
   │
   ▼
AWS Lambda
   │
   ▼
API Gateway
   │
   ▼
Secure Notes API
```

Deployment was intentionally restricted to the `master` branch and required all security jobs to pass.

---

## Application

The application is a small REST API built with FastAPI.

### Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/` | Health/status response |
| GET | `/notes` | Retrieve notes |
| POST | `/notes` | Create a note |

The application is deliberately state-light and is not intended to represent a production database-backed service. Its purpose is to provide a realistic application artifact for demonstrating the DevSecOps workflow.

### Tests

The application includes Pytest tests covering the API behavior.

Baseline test result:

```text
3 passed
```

---

## Technology Stack

### Application

- Python 3.14.6
- FastAPI
- Pydantic
- Uvicorn
- Pytest
- Mangum

### Containerization

- Docker
- AWS Lambda Python container image
- Amazon ECR

### Infrastructure

- Terraform
- AWS Lambda
- Amazon API Gateway HTTP API
- AWS IAM
- Amazon CloudWatch Logs

### DevSecOps

- GitHub Actions
- Gitleaks
- Semgrep
- pip-audit
- Checkov
- Trivy

### Cloud Authentication

- GitHub Actions OIDC
- AWS IAM temporary credentials

---

# Security Pipeline

Every deployment passes through multiple independent security controls.

## 1. Gitleaks

Scans the repository for accidentally committed credentials and secrets.

Gitleaks was also run against the repository's Git history to check for exposed secrets.

---

## 2. Semgrep

Performs static analysis against the application source code.

Custom Semgrep configuration is maintained in:

```text
.semgrep/rules.yml
```

---

## 3. pip-audit

Scans Python dependencies for known vulnerabilities.

Dependencies are pinned in:

```text
requirements.txt
```

This makes the dependency set reproducible and allows the security pipeline to identify vulnerable versions.

---

## 4. Checkov

Scans Terraform configuration for AWS security and infrastructure best-practice violations.

The project intentionally documents security exceptions where a control was not appropriate for this cost-conscious demonstration environment.

Configuration:

```text
terraform/.checkov.yaml
```

The final local Checkov validation completed with:

```text
34 passed
0 failed
0 skipped
```

---

## 5. Trivy

Scans the Docker image for known vulnerabilities.

The deployment gate is configured to fail on:

- HIGH vulnerabilities
- CRITICAL vulnerabilities

The scan is scoped to application/library vulnerabilities so that vulnerabilities inherited from the vendor-managed AWS Lambda base-image operating system do not incorrectly block deployment when they cannot be remediated within the application layer.

The project documents the remaining accepted exceptions in:

```text
.trivyignore
```

The application-layer Python vulnerabilities discovered during development were remediated by upgrading the affected packages.

---

# AWS Deployment

The application was deployed to AWS using a serverless architecture.

```text
                    ┌─────────────────────┐
                    │    API Gateway      │
                    │     HTTP API        │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │       Lambda        │
                    │   Secure Notes API  │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │        ECR          │
                    │   Container Image   │
                    └─────────────────────┘
```

Terraform was used to provision and manage the infrastructure.

The deployment deliberately avoided:

- EKS
- RDS
- NAT Gateway
- Application Load Balancer
- ECS/Fargate
- Always-on EC2 infrastructure

This kept the project inexpensive while still demonstrating real cloud deployment and security practices.

---

# GitHub Actions → AWS Authentication

The project does **not** store long-lived AWS access keys in GitHub.

Instead, GitHub Actions authenticates to AWS using OpenID Connect.

```text
GitHub Actions
      │
      │ OIDC token
      ▼
AWS IAM OIDC Provider
      │
      │ AssumeRoleWithWebIdentity
      ▼
GitHub Actions IAM Role
      │
      ▼
Temporary AWS credentials
```

The IAM trust policy restricts which GitHub repository and branch can assume the deployment role.

The deployment role was also tightened to follow least-privilege principles.

The final deployment permissions were limited to the operations required for the CI deployment:

- ECR authentication
- ECR image upload
- Lambda function inspection
- Lambda function code update

No permanent AWS access keys are required.

---

# Image Management

ECR image tags use the Git commit SHA rather than mutable tags such as `latest`.

Example:

```text
secure-notes-api:<git-commit-sha>
```

The ECR repository was configured with immutable image tags.

This provides:

- Reproducible deployments
- Traceability from deployment → Git commit
- Protection against accidental tag overwrites

Docker image provenance was disabled during the CI build because AWS Lambda rejected the initial OCI image index produced by the default Docker build behavior.

The image was rebuilt as a standard Docker image manifest compatible with Lambda.

---

# Terraform and CI/CD Separation

A deliberate separation was maintained between infrastructure management and application deployment.

### Terraform manages

- Lambda infrastructure
- API Gateway
- ECR
- IAM
- CloudWatch
- GitHub OIDC configuration

### GitHub Actions manages

- Application image builds
- Security gates
- ECR image publishing
- Lambda application-code/image updates

Because GitHub Actions updates the Lambda image after Terraform provisions the infrastructure, Terraform ignores subsequent changes to the Lambda `image_uri`:

```hcl
lifecycle {
  ignore_changes = [
    image_uri
  ]
}
```

This prevents Terraform from attempting to roll the Lambda application back to an older image during later infrastructure plans.

---

# Engineering Problems Solved

This project was intentionally developed through real failures rather than treating the deployment as a theoretical exercise.

## AWS Lambda rejected the initial container image

The first ECR image was published as an OCI image index, which Lambda rejected.

The image was rebuilt with:

```powershell
docker build --provenance=false --platform linux/amd64 ...
```

The resulting image used a Lambda-compatible Docker manifest.

---

## GitHub OIDC authentication initially failed

GitHub Actions initially received an AWS authorization failure when attempting to assume the deployment role.

The issue was traced to the IAM trust policy's GitHub subject claim.

The trust relationship was corrected and restricted to the repository and deployment branch.

---

## Terraform concurrency configuration conflicted with the AWS account limit

An initial Lambda reserved-concurrency configuration caused an AWS account-level unreserved-concurrency limitation.

The unnecessary reserved concurrency setting was removed rather than weakening the account's available capacity.

---

## Checkov identified overly broad IAM permissions

The initial GitHub Actions deployment role used broad permissions.

The policy was subsequently reduced to the specific ECR and Lambda actions required by the deployment workflow.

This turned the deployment role into a significantly more defensible least-privilege design.

---

## Trivy identified vulnerable application dependencies

The initial container scan identified HIGH-severity Python package vulnerabilities.

The affected packages were upgraded and the final scan was scoped appropriately to distinguish application dependencies from vulnerabilities inherited from the AWS-managed Lambda base image.

---

## Terraform detected application-image drift

Terraform initially detected that the Lambda image had changed because GitHub Actions deployed a commit-SHA image after Terraform had provisioned the infrastructure.

The architecture was corrected by making Terraform responsible for infrastructure while GitHub Actions remained responsible for application releases.

---

# Cost Control

Cost was a deliberate architectural constraint.

The project used serverless AWS components and avoided infrastructure that could generate significant ongoing charges.

The AWS environment was deployed, tested end-to-end, and subsequently destroyed after validation.

The Terraform-managed environment was successfully removed:

```text
Destroy complete! Resources: 13 destroyed.
```

ECR images were also removed before destroying the repository.

This demonstrates an additional operational practice:

> Infrastructure that is no longer required should not be left running simply because it was created for a demonstration.

---

# Repository Structure

```text
secure-notes-api/
│
├── .github/
│   └── workflows/
│       └── security-pipeline.yml
│
├── .semgrep/
│   └── rules.yml
│
├── app/
│   ├── __init__.py
│   └── main.py
│
├── tests/
│   └── test_main.py
│
├── terraform/
│   ├── .checkov.yaml
│   ├── .terraform.lock.hcl
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
│
├── .dockerignore
├── .gitignore
├── .python-version
├── .trivyignore
├── Dockerfile
├── README.md
└── requirements.txt
```

---

# Local Development

Create and activate a Python virtual environment:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

Install dependencies:

```powershell
pip install -r requirements.txt
```

Run tests:

```powershell
python -m pytest
```

Run the API locally:

```powershell
uvicorn app.main:app --reload
```

---

# Project Status

The AWS deployment environment has been intentionally torn down after successful end-to-end validation.

The repository remains fully available for:

- Code review
- CI/CD demonstration
- Security pipeline review
- Terraform review
- Technical interviews
- Re-deployment when required

The project is primarily intended as a **DevSecOps engineering demonstration**, rather than as a production application.

---

# Key Takeaways

This project demonstrates practical experience with:

- DevSecOps security gates
- Secure CI/CD pipelines
- GitHub Actions
- GitHub OIDC
- AWS IAM
- Least-privilege access
- Docker
- Amazon ECR
- AWS Lambda
- API Gateway
- Terraform
- Infrastructure as Code security
- Container vulnerability management
- Dependency vulnerability management
- Static application security testing
- Secret detection
- Cost-conscious cloud architecture
- Troubleshooting real deployment failures
- Separating infrastructure lifecycle from application release lifecycle
