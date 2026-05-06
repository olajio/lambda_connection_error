#!/bin/sh
# From https://aws.amazon.com/blogs/aws/new-for-aws-lambda-container-image-support/

if [ -z "${AWS_LAMBDA_RUNTIME_API}" ]; then
    # Wrap with Lambda Runtime Interface Emulator for local run
    exec /usr/bin/aws-lambda-rie python3 -m awslambdaric $1
else
    exec python3 -m awslambdaric $1
fi