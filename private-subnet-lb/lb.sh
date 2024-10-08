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

TASK_ARN=$(
    aws ecs list-tasks \
        --cluster $CLUSTER_NAME \
        --query "taskArns[*]" \
        --output text
)
echo $TASK_ARN

LB=$(
    aws elbv2 create-load-balancer \
        --name $FAMILY_PREFIX-LB  \
	--scheme internal \
        --subnets $PRIVATE_SUBNET_ID1 $PRIVATE_SUBNET_ID2 \
        --security-groups $SG_ID \
        --output text \
        --query "LoadBalancers[0].LoadBalancerArn"
)
echo $LB

TARGET_GROUP_ARN=$(
    aws elbv2 create-target-group \
        --name $FAMILY_PREFIX-TG \
        --target-type ip \
        --protocol HTTP \
        --port 80 \
        --vpc-id $VPC_ID \
        --output text \
        --query "TargetGroups[0].TargetGroupArn"
)
echo "Target Group = $TARGET_GROUP_ARN"

IP=$(
    aws ecs describe-tasks \
        --cluster $CLUSTER_NAME \
        --tasks $TASK_ARN \
        --output text \
        --query "tasks[*].containers[*].networkInterfaces[*].privateIpv4Address"
)
echo $IP

ID=""
for ip_address in $IP; do
    ID="$ID Id=$ip_address"
done

aws elbv2 register-targets \
    --target-group-arn $TARGET_GROUP_ARN  \
    --targets $ID

LISTENER_ARN=$(
    aws elbv2 create-listener \
        --load-balancer-arn $LB \
        --protocol HTTP --port 80  \
        --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
        --output text \
        --query "Listeners[0].ListenerArn"
)
echo "Listener = $LISTENER_ARN"

