awg-arm8:

build-arm8: awg-arm8
	DOCKER_BUILDKIT=1  docker buildx build --no-cache --platform linux/arm64/v8 --output=type=docker --tag docker-awg:latest .

export-arm8: build-arm7
	docker save docker-awg:latest > docker-awg-arm8.tar
