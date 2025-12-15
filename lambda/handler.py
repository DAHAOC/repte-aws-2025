import json
import boto3
from decimal import Decimal

# Nom de la taula de DynamoDB
TABLE_NAME = "CloudResume-Visits"

def lambda_handler(event, context):
    try:
        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(TABLE_NAME)


        # Intentem incrementar el contador de visites
        response = table.update_item(
            Key={'id': 'visit_count'},
            UpdateExpression='SET visits = if_not_exists(visits, : start) + :inc',
            ExpressionAttributeValues={
                ':inc': Decimal(1),
                ':start': Decimal(0)
            },
            ReturnValues='UPDATED_NEW'
        )
    
    # Agafem el nou valor del contador

     new_count = int(response['Attributes']['visits'])

    # Preparem la resposta per el navegador (Cross-Origin Resource Sharing - CORS)
    return {
        'statusCode': 200,
        'headers': {
            # Permetre que Amplify pugui accedir a aquesta API
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET,OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        'body': json.dumps({'visits': new_count})
    }

    except Exception as e: 
        print(f"Error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
    