terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  dynamodb_point_in_time_recovery = {
    dev  = false
    prod = true
  }
  dynamodb_server_side_encryption = {
    dev  = false
    prod = true
  }
  aws_lambda_function_memory_size = {
    dev  = 128
    prod = 256
  }
  aws_lambda_function_timeout = {
    dev  = 3
    prod = 10
  }
}

resource "random_pet" "lambda_bucket" {
  prefix = "lambda-bucket-"
  length = 4
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket.id
}

resource "aws_dynamodb_table" "deliveries" {
  name         = "deliveries-${terraform.workspace}"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "delivery_id"
    type = "S"
  }

  hash_key = "delivery_id"

  ttl {
    attribute_name = "expiryPeriod"
    enabled = true
  }

  point_in_time_recovery {
    enabled = local.dynamodb_point_in_time_recovery[terraform.workspace]
  }

  server_side_encryption {
    enabled = local.dynamodb_server_side_encryption[terraform.workspace]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dynamodb_lambda_policy" {
  name = "dynamodb_lambda_policy"
  role = aws_iam_role.iam_for_lambda.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : ["dynamodb:*"],
        "Resource" : "${aws_dynamodb_table.deliveries.arn}"
      }
    ]
  })
}

data "archive_file" "create_delivery_archive" {
  source_file = "lambdas/create_delivery.py"
  output_path = "lambdas/create_delivery.zip"
  type        = "zip"
}

resource "aws_s3_object" "lambda_create_delivery" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "create_delivery.zip"
  source = data.archive_file.create_delivery_archive.output_path

  etag = filemd5(data.archive_file.create_delivery_archive.output_path)
}

resource "aws_lambda_function" "create_delivery" {
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.deliveries.name
    }
  }
  function_name = "create-delivery-${terraform.workspace}"

  s3_key    = aws_s3_object.lambda_create_delivery.key
  s3_bucket = aws_s3_bucket.lambda_bucket.id

  runtime = "python3.9"
  handler = "create_delivery.lambda_handler"

  memory_size = local.aws_lambda_function_memory_size[terraform.workspace]
  timeout     = local.aws_lambda_function_timeout[terraform.workspace]
  role        = aws_iam_role.iam_for_lambda.arn
}

resource "aws_apigatewayv2_api" "deliveries_api" {
  name          = "deliveries-api-${terraform.workspace}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "deliveries_api" {
  api_id = aws_apigatewayv2_api.deliveries_api.id

  name        = "deliveries-api-${terraform.workspace}"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.deliveries_api.name}"

  retention_in_days = 30
}

resource "aws_apigatewayv2_integration" "create_delivery" {
  api_id = aws_apigatewayv2_api.deliveries_api.id

  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.create_delivery.invoke_arn
}

resource "aws_lambda_permission" "create_delivery" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_delivery.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.deliveries_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_route" "create_delivery" {
  api_id    = aws_apigatewayv2_api.deliveries_api.id
  route_key = "POST /deliveries"

  target = "integrations/${aws_apigatewayv2_integration.create_delivery.id}"
}
