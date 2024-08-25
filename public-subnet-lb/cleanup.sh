#!/bin/bash
#

export AWS_PAGER=""

CLUSTER_NAME="test-cluster"
FAMILY_PREFIX="nginx-cont"

if [ -z "$1" ]; then
    echo "No cluster name provided, using default cluster name: $CLUSTER_NAME"
else
    CLUSTER_NAME=$1
fi

# Delete API Gateway API
#API_ID=$(
#    aws apigatewayv2 get-apis \
#        --query "Items[?Name=='$FAMILY_PREFIX-API'].ApiId" \
#        --output text
#)
#aws apigatewayv2 delete-api --api-id $API_ID

# Delete VPC Link
#VPC_LINK_ID=$(
#    aws apigatewayv2 get-vpc-links \
#        --query "Items[?Name=='$FAMILY_PREFIX-VPC-Link'].VpcLinkId" \
#        --output text
#)
#aws apigatewayv2 delete-vpc-link --vpc-link-id $VPC_LINK_ID

# Delete Load Balancer
LOAD_BALANCER_ARN=$(
    aws elbv2 describe-load-balancers \
        --output text \
        --query "LoadBalancers[?contains(LoadBalancerName, '$FAMILY_PREFIX')].LoadBalancerArn"
)
aws elbv2 delete-load-balancer --load-balancer-arn $LOAD_BALANCER_ARN

#Wait for load balancer to be deleted
echo "Waiting for load balancer to be deleted..."
aws elbv2 wait load-balancers-deleted --load-balancer-arns $LOAD_BALANCER_ARN

# Delete Target Group
TARGET_GROUP_ARN=$(
    aws elbv2 describe-target-groups \
        --output text \
        --query "TargetGroups[?contains(TargetGroupName, '$FAMILY_PREFIX')].TargetGroupArn"
)
aws elbv2 delete-target-group --target-group-arn $TARGET_GROUP_ARN
#Wait till target group is deregistered
echo "Waiting for target groups to be deregistered..."
aws elbv2 wait target-deregistered --target-group-arn $TARGET_GROUP_ARN

for taskDefnArn in $(aws ecs list-task-definitions --family-prefix $FAMILY_PREFIX --output text --query "taskDefinitionArns[]"); do
    	defn=$(echo $taskDefnArn | cut -d "/" -f 2)
    	echo "Deleting task definition $defn"
    	aws ecs deregister-task-definition  	\
            	--task-definition $defn
done


aws ecs delete-service --service "$FAMILY_PREFIX-service" --cluster $CLUSTER_NAME --force
sleep 10

aws ecs delete-cluster --cluster $CLUSTER_NAME

sleep 30
SG_ID=$(aws ec2 describe-security-groups --query "SecurityGroups[?GroupName=='$FAMILY_PREFIX-SG'].GroupId" --output text)
echo "Deleting security group $SG_ID"
aws ec2 delete-security-group --group-id "$SG_ID"

aws cloudformation delete-stack --stack-name $FAMILY_PREFIX

