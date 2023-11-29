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
    dynamodb.put_item(
        TableName=os.environ['TABLE_NAME'],
        Item={
            'delivery_id': {'S': delivery_id},
            'recipient_name': {'S': recipient_name},
            'delivery_address': {'S': delivery_address},
            'status': {'S': 'pending'}
        }
    )
    
    # Return a response
    response = {
        'statusCode': 200,
        'body': json.dumps({'message': 'Delivery request created successfully'})
    }
    
    return response
