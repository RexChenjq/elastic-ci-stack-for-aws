.PHONY: all clean build packer upload create-stack update-stack download-mappings toc

S3_BUCKET ?= buildkite-aws-stack
S3_BUCKET_PREFIX =? dev/$(shell git rev-parse --abbrev-ref HEAD)
AWS_REGION ?= us-east-1
VERSION ?= $(shell git describe --tags --candidates=1)

SHELL = /bin/bash -o pipefail
PACKER_FILES = $(exec find packer/)

# Build the packer AMI, create cloudformation templates and copy to s3
all: build

# Remove any built cloudformation templates and packer output
clean:
	-rm -f build/*
	-rm packer.output

# -----------------------------------------
# Template creation

# Build all the cloudformation templates
build: build/aws-stack.yml build/agent.yml build/metrics.yml build/vpc.yml

build/aws-stack.yml: templates/aws-stack/template.yml build/mapping.yml
	sed -e '/AMI Mappings go here/r./build/mapping.yml' templates/aws-stack/template.yml > build/aws-stack.yml

build/agent.yml: templates/agent/template.yml
	cp templates/agent/template.yml build/agent.yml

build/metrics.yml: templates/metrics/template.yml
	cp templates/metrics/template.yml build/metrics.yml

build/vpc.yml: templates/vpc/template.yml
	cp templates/vpc/template.yml build/vpc.yml

# -----------------------------------------
# AMI creation with Packer

# Use packer to create an AMI
packer: packer.output

# Use packer to create an AMI and write the output to packer.output
packer.output: $(PACKER_FILES)
	docker run \
		-e AWS_DEFAULT_REGION  \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e PACKER_LOG \
		-v ${HOME}/.aws:/root/.aws \
		-v "$(PWD):/src" \
		--rm \
		-w /src/packer \
		hashicorp/packer:1.0.4 build buildkite-ami.json | tee packer.output

# Create a mapping.yml file for the ami produced by packer
build/mapping.yml: packer.output
	mkdir -p build/
	printf "Mappings:\n  AWSRegion2AMI:\n    %s: { AMI: %s }\n" \
		"$(AWS_REGION)" $$(grep -Eo "$(AWS_REGION): (ami-.+)" packer.output | cut -d' ' -f2) > build/mapping.yml

# -----------------------------------------
# Upload to S3

# upload: build/aws-stack.yml
# 	aws s3 sync --acl public-read build s3://$(BUILDKITE_STACK_BUCKET)/

# create-stack: config.json build/aws-stack.yml
# 	aws cloudformation create-stack \
# 	--output text \
# 	--stack-name $(STACK_NAME) \
# 	--disable-rollback \
# 	--template-body "file://$(PWD)/build/aws-stack.yml" \
# 	--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
# 	--parameters "$$(cat config.json)"

# validate: build/aws-stack.yml
# 	aws cloudformation validate-template \
# 	--output table \
# 	--template-body "file://$(PWD)/build/aws-stack.yml"

# update-stack: config.json templates/mappings.yml build/aws-stack.yml
# 	aws cloudformation update-stack \
# 	--output text \
# 	--stack-name $(STACK_NAME) \
# 	--template-body "file://$(PWD)/build/aws-stack.yml" \
# 	--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
# 	--parameters "$$(cat config.json)"

# toc:
# 	docker run -it --rm -v "$(PWD):/app" node:slim bash \
# 		-c "npm install -g markdown-toc && cd /app && markdown-toc -i Readme.md"
