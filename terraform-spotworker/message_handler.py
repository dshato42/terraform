import boto3

if __name__ == "__main__":
    sqs = boto3.resource('sqs')
    incoming_queue = sqs.get_queue_by_name(QueueName='incoming-queue.fifo')
    outgoing_queue = sqs.get_queue_by_name(QueueName='outgoing-queue.fifo')
    while True:
        response = sqs.receive_message (QueueUrl=incoming_queue.url)
        if response:
            message_to_send = '{0} instance name'.format(response['messages'][0])
            response = outgoing_queue.send_message(
                MessageBody=message_to_send,
                MessageGroupId='arcusteam_test'
            )
            receipt_handle = message_to_send['ReceiptHandle']
            # Let the queue know that the message is processed
            message_to_send.delete()
