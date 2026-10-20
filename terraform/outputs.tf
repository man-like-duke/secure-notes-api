output "api_endpoint" {
  description = "API Gateway endpoint for the Secure Notes API"
  value       = aws_apigatewayv2_api.secure_notes.api_endpoint
}

output "github_actions_role_arn" {
  description = "IAM role assumed by GitHub Actions through OIDC"
  value       = aws_iam_role.github_actions.arn
}

output "lambda_function_name" {
  description = "Deployed Lambda function name"
  value       = aws_lambda_function.secure_notes.function_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.secure_notes.repository_url
}