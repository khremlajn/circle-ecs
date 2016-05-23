#!/usr/bin/env bash

set -e
set -u
set -o pipefail

# more bash-friendly output for jq
JQ="jq --raw-output --exit-status"

deploy_image() {
	
    #docker login -u $DOCKER_USERNAME -p $DOCKER_PASS -e $DOCKER_EMAIL
    #docker push arkadiuszzaluski/circle-ecs:$CIRCLE_SHA1 | cat # workaround progress weirdness
    #aws ecr get-login --region us-west-2
    docker build -t circle-ecs-repository .
    autorization_token=$(aws ecr get-authorization-token --registry-ids 792082350620 --output text --query authorizationData[].authorizationToken | base64 --decode | cut -d: -f2)
    docker login -u AWS -p $autorization_token -e none https://792082350620.dkr.ecr.us-west-2.amazonaws.com
    docker tag circle-ecs-repository:latest 792082350620.dkr.ecr.us-west-2.amazonaws.com/circle-ecs-repository:$CIRCLE_SHA1
    docker push 792082350620.dkr.ecr.us-west-2.amazonaws.com/circle-ecs-repository:$CIRCLE_SHA1
}

# reads $CIRCLE_SHA1, $host_port
# sets $task_def
make_task_def() {

    task_template='[
	{
	    "name": "circle-ecs-instance",
	    "image": "792082350620.dkr.ecr.us-west-2.amazonaws.com/circle-ecs-repository:%s",
	    "portMappings": [
		{
		    "containerPort": 8000,
		    "hostPort": %s
		}
	    ],
	    "cpu": 10,
	    "memory": 200,
	    "essential": true
	}
    ]'

    task_def=$(printf "$task_template" $CIRCLE_SHA1 $host_port)

}

# reads $family
# sets $revision
register_definition() {
    if revision=$(aws ecs register-task-definition --container-definitions "$task_def" --family ecs-demo | $JQ '.taskDefinition.taskDefinitionArn'); then
        echo "Revision: $revision"
    else
        echo "Failed to register task definition"
        return 1
    fi

}

deploy_cluster() {

    host_port=80
    family="circle-ecs"

    make_task_def
    register_definition
    #aws ecs create-service --service-name ecs-simple-service --task-definition ecs-demo --desired-count 10
    aws ecs create-service --cluster circle-ecs --service-name circle-ecs-service --task-definition ecs-demo --desired-count 5
    return 0
}

deploy_image
deploy_cluster
