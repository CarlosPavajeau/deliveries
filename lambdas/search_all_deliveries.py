import boto3
import os
import json

def lambda_handler(event, context):
    dynamodb = boto3.resource('dynamodb')
    table_name = os.environ['DELIVERY_TABLE_NAME']
    table = dynamodb.Table(table_name)

    table.load()

    response = table.scan()
    items = response['Items']
    print(items)

    return {
        'statusCode': 200,
        'body': json.dumps(items)
    }