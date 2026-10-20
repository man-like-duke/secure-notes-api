terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.13.0"
}

provider "aws" {
  region = var.aws_region
}

# checkov:skip=CKV_AWS_136:ECR repository uses AES256 to avoid replacing the existing repository and deployed image; KMS encryption is intentionally deferred for this low-cost demo environment.
resource "aws_ecr_repository" "secure_notes" {
  name                 = "secure-notes-api"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }


  tags = {
    Project     = "secure-notes-api"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "lambda_execution" {
  name = "secure-notes-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project     = "secure-notes-api"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

resource "aws_iam_role" "github_actions" {
  name = "secure-notes-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:man-like-duke/secure-notes-api:ref:refs/heads/master"
          }
        }
      }
    ]
  })
}
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "secure-notes-github-actions-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:*",
          "lambda:*",
          "apigateway:*",
          "apigatewayv2:*",
          "logs:*",
          "iam:GetRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "xray:*"
        ]
        Resource = "*"
      }
    ]
  })
}
# checkov:skip=CKV_AWS_272:Code signing is intentionally deferred for this portfolio demo; the Lambda is deployed from an immutable ECR image managed by Terraform.
# checkov:skip=CKV_AWS_116:No DLQ is configured because this Lambda is invoked synchronously through API Gateway and has no asynchronous event source.
# checkov:skip=CKV_AWS_117:Lambda is intentionally kept outside a VPC because it has no private network dependencies; avoiding a VPC also avoids unnecessary NAT and networking cost.
resource "aws_lambda_function" "secure_notes" {
  function_name = "secure-notes-api"

  package_type = "Image"
  image_uri    = "${aws_ecr_repository.secure_notes.repository_url}:0.1.1"

  role = aws_iam_role.lambda_execution.arn

  timeout     = 30
  memory_size = 512

  tracing_config {
    mode = "Active"
  }

  architectures = ["x86_64"]

  tags = {
    Project     = "secure-notes-api"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs
  ]
}

resource "aws_apigatewayv2_api" "secure_notes" {
  name          = "secure-notes-api"
  protocol_type = "HTTP"

  tags = {
    Project     = "secure-notes-api"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.secure_notes.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.secure_notes.invoke_arn
  payload_format_version = "2.0"
}

# checkov:skip=CKV_AWS_309:Authorization is intentionally set to NONE for this portfolio demo; the API is a public synchronous endpoint and does not require an authorizer.
resource "aws_apigatewayv2_route" "default" {
  api_id             = aws_apigatewayv2_api.secure_notes.id
  route_key          = "$default"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"
}
# checkov:skip=CKV_AWS_158:CloudWatch Logs use the AWS-managed encryption default for this low-cost portfolio demo; customer-managed KMS encryption is intentionally deferred to avoid unnecessary key management and cost.
# checkov:skip=CKV_AWS_338:Seven-day log retention is intentional for this low-cost portfolio demo to limit unnecessary log storage costs.
resource "aws_cloudwatch_log_group" "api_gateway_access" {
  name              = "/aws/apigateway/secure-notes-api"
  retention_in_days = 7

  tags = {
    Project     = "secure-notes-api"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.secure_notes.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_access.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      requestTime             = "$context.requestTime"
      httpMethod              = "$context.httpMethod"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }
}
resource "aws_lambda_permission" "api_gateway" {
  statement_id = "AllowAPIGatewayInvoke"

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secure_notes.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.secure_notes.execution_arn}/*/*"
}
