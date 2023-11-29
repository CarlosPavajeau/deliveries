output "base_url" {
  description = "Base URL for API Gateway stage."

  value = aws_apigatewayv2_stage.deliveries_api.invoke_url
}