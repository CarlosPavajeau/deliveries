import boto3
import os
import json

def lambda_handler(event, context):
    request_body = json.loads(event['body'])
    dynamodb = boto3.resource('dynamodb')

    
    # Extract the necessary information from the request body
    delivery_id = request_body['delivery_id']
    recipient_name = request_body['recipient_name']
    delivery_address = request_body['delivery_address']
    
    # Perform the necessary operations to create the delivery request
    table_name = os.environ['DELIVERY_TABLE_NAME']
    table = dynamodb.Table(table_name)

    table.load()

    table.put_item(
        Item={
            'delivery_id': delivery_id,
            'recipient_name': recipient_name,
            'delivery_address': delivery_address,
            'status': 'pending'
        }
    )
    
    # Return a response
    response = {
        'statusCode': 200,
        'body': json.dumps({'message': 'Delivery request created successfully'})
    }
    
    return response
