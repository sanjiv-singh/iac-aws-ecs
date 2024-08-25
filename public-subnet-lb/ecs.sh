#!/bin/bash
#
#

export AWS_PAGER=""

CLUSTER_NAME="test-cluster"
FAMILY_PREFIX="nginx-cont"

if [ -z "$1" ]; then
    echo "No cluster name provided, using default cluster name: $CLUSTER_NAME"
else
    CLUSTER_NAME=$1
fi

aws cloudformation deploy \
    --stack-name $FAMILY_PREFIX \
    --template-file vpc.yml

aws cloudformation wait stack-create-complete \
    --stack-name $FAMILY_PREFIX

aws ecs create-cluster  \
    	--cluster-name $CLUSTER_NAME

for taskDefnArn in $(aws ecs list-task-definitions --family-prefix $FAMILY_PREFIX --output text --query taskDefinitionArns[]); do
    	defn=$(echo $taskDefnArn | cut -d "/" -f 2)
    	echo "Deleting task definition $defn"
    	aws ecs deregister-task-definition  	\
            	--task-definition $defn
done

aws ecs register-task-definition    	\
    	--cli-input-json file://./multicontainer.json

VPC_ID=$(
    aws cloudformation describe-stacks \
        --output text \
        --query "Stacks[?StackName=='nginx-cont'][].Outputs[?OutputKey=='VpcId'].OutputValue" 
)
echo "VpcId = $VPC_ID"
PUBLIC_SUBNET_ID1=$(
    aws cloudformation describe-stacks \
        --output text \
        --query "Stacks[?StackName=='nginx-cont'][].Outputs[?OutputKey=='PublicSubnetId1'].OutputValue" 
)
echo "PublicSubnetId1 = $PUBLIC_SUBNET_ID1"
PUBLIC_SUBNET_ID2=$(
    aws cloudformation describe-stacks \
        --output text \
        --query "Stacks[?StackName=='nginx-cont'][].Outputs[?OutputKey=='PublicSubnetId2'].OutputValue" 
)
echo "PublicSubnetId2 = $PUBLIC_SUBNET_ID2"
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

SG_ID=$(aws ec2 create-security-group --group-name "$FAMILY_PREFIX-SG" --description "Security Group for $FAMILY_PREFIX-service" --vpc-id $VPC_ID --output text)
echo "Security Group ID = $SG_ID"

aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

TASK_DEF=$(aws ecs list-task-definitions --status ACTIVE --output text | grep $FAMILY_PREFIX | cut -d "/" -f 2)
REV=$(aws ecs describe-task-definition --task-definition $FAMILY_PREFIX --query "taskDefinition.revision")

aws ecs create-service \
    --service-name "$FAMILY_PREFIX-service"   	\
    --cluster $CLUSTER_NAME     	\
    --launch-type FARGATE  \
    --platform-version LATEST  	\
    --task-definition $FAMILY_PREFIX:$REV \
    --desired-count 3 \
    --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNET_ID1,$PRIVATE_SUBNET_ID2],securityGroups=[$SG_ID],assignPublicIp=DISABLED}"

# Wait till service is stable
echo "Waiting for ecs service to be stable..."
aws ecs wait services-stable --cluster $CLUSTER_NAME --services "$FAMILY_PREFIX-service"
