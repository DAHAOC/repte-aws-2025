import json
import boto3
from decimal import Decimal

# Nom de la taula de DynamoDB
TABLE_NAME = "CloudResume-Visits"

def lambda_handler(event, context):
    try:
        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(TABLE_NAME)

        # 1. Intentem incrementar el contador de visites
        response = table.update_item(
            Key={'id': 'visit_count'},
            # Eliminada la indentació estranya al final de la línia
            UpdateExpression='SET visits = if_not_exists(visits, :start) + :inc', 
            ExpressionAttributeValues={
                ':inc': Decimal(1),
                ':start': Decimal(0)
            },
            ReturnValues='UPDATED_NEW'
        )
    
        # 2. Agafem el nou valor del contador (Aquesta línia estava malament indentada)
        new_count = int(response['Attributes']['visits'])

        # 3. Preparem la resposta per el navegador (CORS)
        return {
            'statusCode': 200,
            'headers': {
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
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({'error': str(e)})
        }