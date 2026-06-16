FROM debian:bookworm-slim

ARG KUBECTL_VERSION=v1.31.4
ARG HELM_VERSION=v3.16.3
ARG KIND_VERSION=v0.26.0
ARG TARGETARCH

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    gnupg \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
  && echo "deb [arch=${TARGETARCH:-amd64} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" \
    > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends docker-ce-cli \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH:-amd64}/kubectl" \
    -o /usr/local/bin/kubectl \
  && chmod +x /usr/local/bin/kubectl

RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH:-amd64}.tar.gz" \
    | tar -xz -C /tmp \
  && mv "/tmp/linux-${TARGETARCH:-amd64}/helm" /usr/local/bin/helm \
  && rm -rf /tmp/linux-*

RUN curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${TARGETARCH:-amd64}" \
    -o /usr/local/bin/kind \
  && chmod +x /usr/local/bin/kind

WORKDIR /workspace

ENTRYPOINT ["/workspace/scripts/docker-entrypoint.sh"]
CMD ["shell"]
