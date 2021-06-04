FROM alpine:3.13.5
WORKDIR /

# iproute2 -> bridge
# bind-tools -> dig, bind
# dhclient -> get dynamic IP
# dnsmasq -> DNS & DHCP server
# coreutils -> need REAL chown and chmod for dhclient (it uses reference option not supported in busybox)
RUN apk add --no-cache coreutils dnsmasq iproute2 bind-tools dhclient

COPY config /default_config
COPY config /config
COPY bin /bin
CMD [ "/bin/entry.sh" ]

ARG IMAGE_SOURCE
#https://github.com/k8s-at-home/template-container-image
LABEL org.opencontainers.image.source $IMAGE_SOURCE 
