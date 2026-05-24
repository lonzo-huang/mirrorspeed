FROM debian:bookworm-slim

ARG WSTUNNEL_VERSION=v10.1.3

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iptables \
    iproute2 \
    python3 \
    python3-venv \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download and install wstunnel binary
RUN set -eux; \
    ARCH=$(uname -m); \
    case "${ARCH}" in \
        x86_64)  ARCH_TAG="amd64" ;; \
        aarch64) ARCH_TAG="arm64" ;; \
        *)       echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac; \
    VERSION_NO_V="${WSTUNNEL_VERSION#v}"; \
    DOWNLOAD_URL="https://github.com/erebe/wstunnel/releases/download/${WSTUNNEL_VERSION}/wstunnel_${VERSION_NO_V}_linux_${ARCH_TAG}.tar.gz"; \
    echo "Downloading wstunnel from: ${DOWNLOAD_URL}"; \
    curl -fsSL "${DOWNLOAD_URL}" -o /tmp/wstunnel.tar.gz; \
    tar -xzf /tmp/wstunnel.tar.gz -C /tmp; \
    install -m 755 /tmp/wstunnel /usr/local/bin/wstunnel; \
    rm -rf /tmp/wstunnel*; \
    wstunnel --version

# Set up Python virtual environment and install dependencies
COPY requirements.txt /app/requirements.txt
RUN python3 -m venv /app/venv && \
    /app/venv/bin/pip install --no-cache-dir -r /app/requirements.txt

# Copy application code
COPY main.py /app/main.py

# Copy and configure entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app

EXPOSE 2080 8443

ENTRYPOINT ["/entrypoint.sh"]
