# Copyright 2020 The DataWorkbench Authors. All rights reserved.
# Use of this source code is governed by a Apache license
# that can be found in the LICENSE file.

TARG.Name:=dataworkbench
TRAG.Gopkg:=DataWorkbench
#TRAG.Version:=$(TRAG.Gopkg)/pkg/version

DOCKER_TAGS=latest
BUILDER_IMAGE=dataworkbench/builder:latest
BUILDER_IMAGE_ZEPPELIN=dataworkbench/zeppelin-builder:latest

LOCAL_CACHE:=`go env GOCACHE`
LOCAL_MODCACHE:=`go env GOPATH`/pkg
WORKDIR_IN_DOCKER=/$(TRAG.Gopkg)
RUN_IN_DOCKER:=docker run -it --rm -v `pwd`/..:$(WORKDIR_IN_DOCKER) -v ${LOCAL_CACHE}:/go/cache -v $(LOCAL_MODCACHE):/go/pkg -w $(WORKDIR_IN_DOCKER) $(BUILDER_IMAGE)

comma:= ,
empty:=
space:= $(empty) $(empty)
# the service that need to format/compile/build.., default all.
service=apiglobal,apiserver,spacemanager,flowmanager,jobmanager,jobdeveloper,jobwatcher,notifier,scheduler,sourcemanager,udfmanager,zeppelinscale,observer,enginemanager
COMPOSE_SERVICE=$(subst ${comma},${space},$(service))
COMPOSE_DB_CTRL=dataworkbench-db-ctrl

.PHONY: help
help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_%-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: update-builder
update-builder: ## Pull dataworkbench-builder image
	docker pull $(BUILDER_IMAGE)
	docker pull $(BUILDER_IMAGE_ZEPPELIN)
	@echo "update-builder done"

.PHONY: compile
compile:
	$(RUN_IN_DOCKER) bash -c "time ./deploy/build/scripts/compile.sh -s $(service) -o $(WORKDIR_IN_DOCKER)/deploy/tmp/bin -c $(WORKDIR_IN_DOCKER)/deploy/tmp/conf";

.PHONY: build-flyway
build-flyway: ## Build flyway image for database migration
	cd .. && docker build -t $(TARG.Name)/flyway:${DOCKER_TAGS} -f ./deploy/build/db/Dockerfile .

.PHONY: build-zeppelin
build-zeppelin: ## zeppelin, set perNote to isolate perUser to '', download lib from QingStor
	cd ./build/zeppelin && docker build -t $(TARG.Name)/zeppelin:${DOCKER_TAGS} . && cd ../..

.PHONY: build-flink-utile
build-flink-utile:
	cd ./build/flink_utile/ && docker build -t $(TARG.Name)/flinkutile:${DOCKER_TAGS} . && cd ../..

.PHONY: build-dev
build-dev: compile  ## Build dataworkbench image
	@cd .. && docker build -t $(TARG.Name)/$(TARG.Name) -f ./deploy/Dockerfile.dev .
	docker image prune -f 1>/dev/null 2>&1
	@echo "build done"

.PHONY: build-all  ## Build all images
build-all: build-flyway build-dev build-zeppelin build-flink-utile

.PHONY: pull-images
pull-images: ## Pull images for docker-compose
	docker-compose pull --ignore-pull-failures
	@echo "pull-images done"

.PHONY: compose-migrate-db
compose-migrate-db: ## Migrate db in docker compose
	until docker-compose exec dataworkbench-db bash -c "echo 'SELECT VERSION();' | mysql -uroot -ppassword"; do echo "waiting for mysql"; sleep 2; done;
	docker-compose up $(COMPOSE_DB_CTRL)

.PHONY: compose-up
compose-up: ## Launch dataworkbench in docker compose
	docker-compose up -d dataworkbench-db
	make compose-migrate-db
	docker-compose up --remove-orphans -d
	@echo "compose-up done"

.PHONY: compose-down
compose-down: ## Shutdown service in docker compose
	docker-compose down
	@echo "compose-down done"

.PHONY: compose-logs-f
compose-logs-f: ## Follow service log in docker compose
	docker-compose logs --tail 10 -f $(COMPOSE_SERVICE)

update: build-dev ## Update some service
	docker-compose up --no-deps -d $(COMPOSE_SERVICE)
	@echo "update service $(service) done"

.PHONY: clean
clean:
	rm -r ./tmp

.PHONY: test
test: ## Launch dataworkbench in docker compose
	@bash ./tests/run.sh
