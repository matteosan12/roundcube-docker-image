# This Makefile automates possible operations of this project.
#
# Images and description on Docker Hub will be automatically rebuilt on
# pushes to `master` branch of this repo and on updates of parent images.
#
# Note! Docker Hub `post_push` hook must be always up-to-date with default
# values of current Makefile. To update it just use one of:
#	make post-push-hook-all
#	make src-all
#
# It's still possible to build, tag and push images manually. Just use:
#	make release-all


IMAGE_NAME := instrumentisto/roundcube
ALL_IMAGES := \
	1.3/apache:1.3.1-apache,1.3-apache,1-apache,apache,latest \
	1.3/fpm:1.3.1-fpm,1.3-fpm,1-fpm,fpm \
	1.2/apache:1.2.5-apache,1.2-apache \
	1.2/fpm:1.2.5-fpm,1.2-fpm
#	<Dockerfile>:<version>,<tag1>,<tag2>,...


# Default is first image from ALL_IMAGES list.
DOCKERFILE ?= $(word 1,$(subst :, ,$(word 1,$(ALL_IMAGES))))
VERSION ?=  $(word 1,$(subst $(comma), ,\
                     $(word 2,$(subst :, ,$(word 1,$(ALL_IMAGES))))))
TAGS ?= $(word 2,$(subst :, ,$(word 1,$(ALL_IMAGES))))

no-cache ?= no


comma := ,
empty :=
space := $(empty) $(empty)
eq = $(if $(or $(1),$(2)),$(and $(findstring $(1),$(2)),\
                                $(findstring $(2),$(1))),1)



# Build Docker image.
#
# Usage:
#	make image [no-cache=(yes|no)] [DOCKERFILE=] [VERSION=]

no-cache-arg = $(if $(call eq, $(no-cache), yes), --no-cache, $(empty))

image:
	docker build $(no-cache-arg) -t $(IMAGE_NAME):$(VERSION) $(DOCKERFILE)



# Tag Docker image with given tags.
#
# Usage:
#	make tags [VERSION=] [TAGS=t1,t2,...]

parsed-tags = $(subst $(comma), $(space), $(TAGS))

tags:
	(set -e ; $(foreach tag, $(parsed-tags), \
		docker tag $(IMAGE_NAME):$(VERSION) $(IMAGE_NAME):$(tag) ; \
	))



# Manually push Docker images to Docker Hub.
#
# Usage:
#	make push [TAGS=t1,t2,...]

push:
	(set -e ; $(foreach tag, $(parsed-tags), \
		docker push $(IMAGE_NAME):$(tag) ; \
	))



# Make manual release of Docker images to Docker Hub.
#
# Usage:
#	make release [no-cache=(yes|no)] [DOCKERFILE=] [VERSION=] [TAGS=t1,t2,...]

release: | image tags push



# Make manual release of all supported Docker images to Docker Hub.
#
# Usage:
#	make release-all [no-cache=(yes|no)]

release-all:
	(set -e ; $(foreach img,$(ALL_IMAGES), \
		make release no-cache=$(no-cache) \
			DOCKERFILE=$(word 1,$(subst :, ,$(img))) \
			VERSION=$(word 1,$(subst $(comma), ,\
			                 $(word 2,$(subst :, ,$(img))))) \
			TAGS=$(word 2,$(subst :, ,$(img))) ; \
	))



# Generate Docker image sources.
#
# Usage:
#	make src [DOCKERFILE=] [VERSION=] [TAGS=t1,t2,...]

src: dockerfile post-push-hook



# Generate sources for all supported Docker images.
#
# Usage:
#	make src-all

src-all:
	(set -e ; $(foreach img,$(ALL_IMAGES), \
		make src \
			DOCKERFILE=$(word 1,$(subst :, ,$(img))) \
			VERSION=$(word 1,$(subst $(comma), ,\
			                 $(word 2,$(subst :, ,$(img))))) \
			TAGS=$(word 2,$(subst :, ,$(img))) ; \
	))



# Generate Dockerfile from template.
#
# Usage:
#	make dockerfile [DOCKERFILE=] [VERSION=]

dockerfile:
	mkdir -p $(DOCKERFILE)
	docker run --rm -i -v $(PWD)/Dockerfile.tmpl.php:/Dockerfile.php:ro \
		php:alpine php -f /Dockerfile.php -- \
			--dockerfile='$(DOCKERFILE)' \
			--version='$(VERSION)' \
		> $(DOCKERFILE)/Dockerfile
	rm -rf $(DOCKERFILE)/rootfs
	cp -rf rootfs $(DOCKERFILE)/
	git add $(DOCKERFILE)/rootfs



# Generate Dockerfile from template for all supported Docker images.
#
# Usage:
#	make dockerfile-all

dockerfile-all:
	(set -e ; $(foreach img,$(ALL_IMAGES), \
		make dockerfile \
			DOCKERFILE=$(word 1,$(subst :, ,$(img))) \
			VERSION=$(word 1,$(subst $(comma), ,\
			                 $(word 2,$(subst :, ,$(img))))) ; \
	))



# Create `post_push` Docker Hub hook.
#
# When Docker Hub triggers automated build all the tags defined in `post_push`
# hook will be assigned to built image. It allows to link the same image with
# different tags, and not to build identical image for each tag separately.
# See details:
# http://windsock.io/automated-docker-image-builds-with-multiple-tags
#
# Usage:
#	make post-push-hook [DOCKERFILE=] [TAGS=t1,t2,...]

post-push-hook:
	mkdir -p $(DOCKERFILE)/hooks
	docker run --rm -i -v $(PWD)/post_push.tmpl.php:/post_push.php:ro \
		php:alpine php -f /post_push.php -- \
			--image_tags='$(TAGS)' \
		> $(DOCKERFILE)/hooks/post_push



# Create `post_push` Docker Hub hook for all supported Docker images.
#
# Usage:
#	make post-push-hook-all

post-push-hook-all:
	(set -e ; $(foreach img,$(ALL_IMAGES), \
		make post-push-hook \
			DOCKERFILE=$(word 1,$(subst :, ,$(img))) \
			TAGS=$(word 2,$(subst :, ,$(img))) ; \
	))



# Run tests for Docker image.
#
# Usage:
#	make test [DOCKERFILE=] [VERSION=]

test: deps.bats
	DOCKERFILE=$(DOCKERFILE) IMAGE=$(IMAGE_NAME):$(VERSION) \
		./test/bats/bats test/suite.bats



# Run tests for all supported Docker images.
#
# Usage:
#	make test-all [prepare-images=(no|yes)]

prepare-images ?= no

test-all:
ifeq ($(prepare-images),yes)
	(set -e ; $(foreach img,$(ALL_IMAGES), \
		make image no-cache=$(no-cache) \
			DOCKERFILE=$(word 1,$(subst :, ,$(img))) \
			VERSION=$(word 1,$(subst $(comma), ,\
			                 $(word 2,$(subst :, ,$(img))))) ; \
	))
endif
	(set -e ; $(foreach img,$(ALL_IMAGES), \
		make test \
			DOCKERFILE=$(word 1,$(subst :, ,$(img))) \
			VERSION=$(word 1,$(subst $(comma), ,\
			                 $(word 2,$(subst :, ,$(img))))) ; \
	))



# Resolve project dependencies for running tests.
#
# Usage:
#	make deps.bats [BATS_VER=]

BATS_VER ?= 0.4.0

deps.bats:
ifeq ($(wildcard $(PWD)/test/bats),)
	mkdir -p $(PWD)/test/bats/vendor
	curl -L -o $(PWD)/test/bats/vendor/bats.tar.gz \
		https://github.com/sstephenson/bats/archive/v$(BATS_VER).tar.gz
	tar -xzf $(PWD)/test/bats/vendor/bats.tar.gz \
		-C $(PWD)/test/bats/vendor
	rm -f $(PWD)/test/bats/vendor/bats.tar.gz
	ln -s $(PWD)/test/bats/vendor/bats-$(BATS_VER)/libexec/* \
		$(PWD)/test/bats/
endif



.PHONY: image tags push \
        release release-all \
        src src-all \
        dockerfile dockerfile-all \
        post-push-hook post-push-hook-all \
        test test-all deps.bats
