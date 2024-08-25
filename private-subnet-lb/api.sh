
export AWS_PAGER=""

CLUSTER_NAME="test-cluster"
FAMILY_PREFIX="nginx-cont"

VPC_ID=$(
    aws cloudformation describe-stacks \
        --output text \
        --query "Stacks[?StackName=='nginx-cont'][].Outputs[?OutputKey=='VpcId'].OutputValue"
)
echo "VpcId = $VPC_ID"
PUBLIC_SUBNET_ID=$(
    aws cloudformation describe-stacks \
        --output text \
        --query "Stacks[?StackName=='nginx-cont'][].Outputs[?OutputKey=='PublicSubnetId'].OutputValue"
)
echo "PublicSubnetId = $PUBLIC_SUBNET_ID"
PRIVATE_SUBNET_ID1=$(
    aws cloudformation describe-stacks \
        --output text \
        --query "Stacks[?StackName=='nginx-cont'][].Outputs[?OutputKey=='PrivateSubnetId1'].OutputValue"
)
echo "PrivateSubnetId1 = $PRIVATE_SUBNET_ID1"
PRIVATE_SUBNET_ID2=$(
    aws cloudformation describe-stacks \
        --output text \
        --query "Stacks[?StackName=='nginx-cont'][].Outputs[?OutputKey=='PrivateSubnetId2'].OutputValue"
)
echo "PrivateSubnetId2 = $PRIVATE_SUBNET_ID2"
SG_ID=$(
    aws ec2 describe-security-groups \
	--filters Name=vpc-id,Values=$VPC_ID \
	--output text \
	--query "SecurityGroups[?GroupName=='$FAMILY_PREFIX-SG'].GroupId" 
)
echo "SecurityGroup = $SG_ID"

LB=$(
    aws elbv2 describe-load-balancers \
        --output text \
        --query "LoadBalancers[?LoadBalancerName=='$FAMILY_PREFIX-LB'].LoadBalancerArn"
)
echo "LB Arn = $LB"

LISTENER_ARN=$(
    aws elbv2 describe-listeners \
        --load-balancer $LB \
        --output text \
        --query "Listeners[0].ListenerArn"
)
echo "Listener = $LISTENER_ARN"

VPC_LINK_ID=$(
    aws apigatewayv2 create-vpc-link \
        --name $FAMILY_PREFIX-VL \
        --subnet-ids $PRIVATE_SUBNET_ID1 $PRIVATE_SUBNET_ID2 \
        --security-group-ids $SG_ID \
        --output text \
        --query "VpcLinkId"
)
echo "VpcLinkId = $VPC_LINK_ID"

API_ID=$(
    aws apigatewayv2 create-api \
        --name $FAMILY_PREFIX-API \
        --protocol HTTP --query "ApiId" \
        --output text
)
echo "API ID = $API_ID"

INTEGRATION_ID=$(
    aws apigatewayv2 create-integration \
        --api-id $API_ID \
        --connection-type VPC_LINK \
        --connection-id $VPC_LINK_ID \
        --integration-type HTTP_PROXY \
        --integration-method ANY \
        --integration-uri $LISTENER_ARN \
        --payload-format-version 1.0 \
        --output text \
        --query "IntegrationId"
)
echo "Integration ID = $INTEGRATION_ID"

aws apigatewayv2 create-route \
    --api-id $API_ID \
    --target integrations/$INTEGRATION_ID \
    --route-key '$default'

aws apigatewayv2 create-stage \
    --api-id $API_ID \
    --auto-deploy \
    --stage-name '$default' 

ENDPOINT_URI=$(
    aws apigatewayv2 get-api \
        --api-id $API_ID \
        --query "ApiEndpoint" \
        --output text
)
echo "Endpoint URI = $ENDPOINT_URI"
