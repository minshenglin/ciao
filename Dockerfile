ARG RUNC_VERSION=9f9c96235cc97674e935002fc3d78361b696a69e

FROM golang:1.10-alpine3.7 AS build-env

RUN apk add --no-cache \
    zeromq-dev=4.2.5-r0 \
    zeromq=4.2.5-r0 \
    gcc \
    musl-dev

ADD . /go/src/github.com/caicloud/ciao
WORKDIR /go/src/github.com/caicloud/ciao
RUN go build github.com/caicloud/ciao/cmd/kubeflow-kernel \
    && mv kubeflow-kernel /usr/bin/kubeflow-kernel

# The images are copied from https://github.com/genuinetools/img/blob/master/Dockerfile.
FROM golang:1.10-alpine AS gobuild-base

RUN apk add --no-cache \
    bash \
    build-base \
    gcc \
    git \
    libseccomp-dev \
    linux-headers \
    make

FROM gobuild-base AS runc
ARG RUNC_VERSION
RUN git clone https://github.com/opencontainers/runc.git "$GOPATH/src/github.com/opencontainers/runc" \
    && cd "$GOPATH/src/github.com/opencontainers/runc" \
    && make static BUILDTAGS="seccomp" EXTRA_FLAGS="-buildmode pie" EXTRA_LDFLAGS="-extldflags \\\"-fno-PIC -static\\\"" \
    && mv runc /usr/bin/runc

FROM gobuild-base AS img
RUN git clone https://github.com/genuinetools/img.git "$GOPATH/src/github.com/genuinetools/img" \
    && go get -u github.com/jteeuwen/go-bindata/... \
    && cd "$GOPATH/src/github.com/genuinetools/img" \
    && make static && mv img /usr/bin/img

FROM alpine:3.7
MAINTAINER Ce Gao <gaoce@caicloud.io>

RUN apk add --no-cache \
    bash \
    git \
    shadow \
    shadow-uidmap \
    strace \
    zeromq=4.2.5-r0 \
    libzmq=4.2.5-r0 \
    zeromq-dev=4.2.5-r0 \
    gcc \
    linux-headers \
    g++ \
    python \
    python-dev \
    py-pip \
    musl-dev

# install the kernel gateway
RUN pip install --no-cache-dir jupyter_kernel_gateway

COPY --from=img /usr/bin/img /usr/bin/img
COPY --from=runc /usr/bin/runc /usr/bin/runc
COPY --from=build-env /usr/bin/kubeflow-kernel /usr/bin/kubeflow-kernel

COPY ./hack/k8s.config.yaml /etc/ciao/config.yaml
COPY ./artifacts /usr/share/jupyter/kernels/kubeflow

# run kernel gateway on container start, not notebook server
EXPOSE 8889
ENTRYPOINT [ "jupyter", "kernelgateway" ]
CMD ["--KernelGatewayApp.ip=0.0.0.0", "--KernelGatewayApp.port=8889", "--JupyterWebsocketPersonality.list_kernels=True", "--log-level=DEBUG", "--KernelGatewayApp.env_process_whitelist=['KUBERNETES_SERVICE_HOST','KUBERNETES_SERVICE_PORT']"]
