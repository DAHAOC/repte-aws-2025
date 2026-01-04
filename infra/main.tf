# 1. CONFIGURACIÓ INICIAL
provider "aws" {
  region = "us-east-1"
}

variable "github_token" {
  description = "Token de GitHub per a Amplify"
  type        = string
  sensitive   = true
}

# Agafem el rol que ja ens dona el laboratori
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# 2. DNS (Route 53)
resource "aws_route53_zone" "main" {
  name = "aws10.dahao.cat"
}

# 3. BASE DE DADES (DynamoDB)
resource "aws_dynamodb_table" "visitor_count" {
  name         = "CloudResume-Visits"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# 4. BACKEND (Lambda)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../lambda/handler.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "visitor_counter" {
  filename         = "lambda_function.zip"
  function_name    = "CloudResumeCounter"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.9"
}

# 5. API GATEWAY AMB CORS AUTOMÀTIC
resource "aws_api_gateway_rest_api" "api" {
  name = "CloudResumeAPI"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "visits"
}

# Mètode GET
resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.visitor_counter.invoke_arn
}

# Mètode OPTIONS per CORS
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_integration]
}

# Deployment i Stage (CORREGIT)
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on  = [aws_api_gateway_integration.lambda_integration, aws_api_gateway_integration.options_integration]
  
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api))
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

resource "aws_lambda_permission" "apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# 6. FRONTEND (AWS Amplify)
resource "aws_amplify_app" "cv_app" {
  name       = "Cloud-Resume-Amplify"
  repository = "https://github.com/DAHAOC/repte-aws-2025"
  access_token = var.github_token
  
  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        build:
          commands: []
      artifacts:
        baseDirectory: frontend
        files:
          - '**/*'
  EOT
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.cv_app.id
  branch_name = "main" 
}

resource "aws_amplify_domain_association" "domain" {
  app_id      = aws_amplify_app.cv_app.id
  domain_name = aws_route53_zone.main.name
  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = "cv"
  }
}

# 7. OUTPUTS
output "api_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/visits"
}

output "nameservers" {
  value = aws_route53_zone.main.name_servers
}