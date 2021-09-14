# How to manually setup Gitlab Runner for Docker

## Create Docker Private Network for Builds
docker network create gitlab-runner

## Run Docker in Docker
docker run -d --name gitlab-dind --privileged --restart always --network gitlab-runner -v /var/lib/docker tiredofit/docker-dind:latest

## Run GitLab Runner
docker run -d --name gitlab-runner --restart always --network gitlab-runner -v 
/config:/etc/gitlab-runner -e DOCKER_HOST=tcp://gitlab-dind:2375 tiredofit/gitlab-runner:latest

- You can also use the docker-compose.yml for the above commands

## Configure Gitlab Runner
docker run -it --rm -v /var/local/docker/gitlab-runner/config:/etc/glab-runner tiredofit/gitlab-runner \
   register \
    --executor docker \
    --docker-image docker:git \
    --docker-volumes /var/run/docker.sock:/var/run/docker.sock

There are also additional environment variables.. TBC
