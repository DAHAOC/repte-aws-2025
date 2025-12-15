terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Normalmente los Labs usan esta región, verifícalo
}

#Obtenir rol

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# Afegir recursos

# La Base de dades DynamoDB (Punto 8)
# PayPerRequest per no cobrar si no s'utilitza

resource "aws_dynamodb_table" "cv_table" {
  name           = "CloudResume-Visits"
  billing_mode   = "PAY_PER_REQUEST" 
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "CloudResume-Challenge"
    Environment = "AcademyLab"
  }
}



#  2. PAQUET DE DESPLEGAMENT FUNCIO LAMBDA (PUNT 10)

# Utilizem data source 'archive_file' per crear un zip del codi Python
# Terraform el executa automaticament abans de crear la lambda

data "archive_file" "lambda_zip" {
    type = "zip"
    source_dir = "../lambda"
    output_path = "handler.zip"
}


# 3. funcio AWS LAMBDA (punt 10)

resource "aws_lambda_function" "visits_counter" {
    filename = data.archive_file.lambda_zip.output_path
    function_name = "CloudResumeCounter"
    role = data.aws_iam_role.lab_role.arn # Rol de Lab
    handler = "handler.lambda_handler"
    runtime = "python3.10"
    source_code_hash = data.archive_file.lambda_zip.output_md5
    timeout = 10 # SEGONS
    
    # Donar Permisos a lambda per accedir a DynamoDB
    # Afegir politiques per AWS per si no els té
}

# 4.API GATEWAY (punt 9) 

# a.LA API PRINCIPAL

resource "aws_api_gateway_rest_api" "api" {
    name = "CloudResumeAPI"
    description = "API per obtenir el contador de visites"
}

# b. Recurs URL (ruta/visites)

resource "aws_api_gateway_resource" "visits_resource" {
    rest_api_id = aws_api_gateway_rest_api.api.id
    parent_id = aws_api_gateway_rest_api.api.root_resource_id
    path_part = "visits"
}

# c. Metode GET (llegir comptador)

resource "aws_api_gateway_method" "visits_get_method" {
    rest_api_id = aws_api_gateway_rest_api.api.id
    resource_id = aws_api_gateway_resource.visits_resource.id
    http_method = "GET"
    authorization = "NONE" # PUBLIC

}

# d.Conexio de la API amb la Lambda
resource "aws_api_gateway_integration" "visits_integration" {
    rest_api_id = aws_api_gateway_rest_api.api.id
    resource_id = aws_api_gateway_resource.visits_resource.id
    http_method = aws_api_gateway_method.visits_get_method.http_method
    integration_http_method = "POST"
    type = "AWS_PROXY"
    uri = aws_lambda_function.visits_counter.invoke_arn
}

# e.Permisos per que la API Gateway pugui cridar a la Lambda

resource "aws_lambda_permission" "apigw_lambda_permission" {
    statement_id = "AllowAPIGatewayInvoke"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.visits_counter.function_name
    principal = "apigateway.amazonaws.com"
    
    # Limitar la crida nomes al meu API
    source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# f.Desplegar API (per posar-ho actiu)

resource "aws_api_gateway_deployment" "visits_deployment" {
    rest_api_id = aws_api_gateway_rest_api.api.id
    # Depen del metode per asegurar el orde de creació
    depends_on = [
        aws_api_gateway_integration.visits_integration,
    ]

    # forza un nou desplegament si el contigut camvia

    triggers = {
        redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api))
    }
}

# g.Crear la 'stage' (URL final)

resource "aws_api_gateway_stage" "prod_stage" {
    deployment_id = aws_api_gateway_deployment.visits_deployment.id
    rest_api_id = aws_api_gateway_rest_api.api.id
    stage_name = "prod"
}

# 5.OUTPUT (veure resultat en consola)

# Permet mostra el endpoint final que utilitzem en el frontend

output "api_gateway_url" {
    description = "URL del APi Gateway per visites"
    value = "${aws_api_gateway_rest_api.api.execution_arn}/${aws_api_gateway_stage.prod_stage.stage_name}/visits"
}