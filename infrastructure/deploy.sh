#!/bin/bash
# TurboTurf Fleet Management - AWS Deployment Script

set -e

ENVIRONMENT=${1:-dev}
REGION=${AWS_REGION:-us-east-1}
STACK_NAME="turboturf-$ENVIRONMENT"

echo "Deploying TurboTurf Fleet Management"
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "Stack: $STACK_NAME"
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI not installed"
    exit 1
fi

# Validate template
echo "Validating CloudFormation template..."
aws cloudformation validate-template \
    --template-body file://turboturf-stack.yaml \
    --region "$REGION"

# Deploy stack
echo "Deploying stack..."
aws cloudformation deploy \
    --template-file turboturf-stack.yaml \
    --stack-name "$STACK_NAME" \
    --parameter-overrides Environment="$ENVIRONMENT" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION"

# Get outputs
echo ""
echo "Deployment complete! Stack outputs:"
aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs' \
    --output table

# Extract API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

echo ""
echo "API Endpoint: $API_ENDPOINT"
echo ""
echo "Configure your apps with:"
echo "  Android: FleetManager.apiEndpoint = \"$API_ENDPOINT\""
echo "  Flutter: FleetCloudClient.configure(apiEndpoint: \"$API_ENDPOINT\")"
