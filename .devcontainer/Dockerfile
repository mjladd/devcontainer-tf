# Go Source
FROM golang:1.23-bookworm AS go-source

# Terraform Source
FROM hashicorp/terraform:1.10.0 AS terraform-source

# TFLint Source
FROM ghcr.io/terraform-linters/tflint:v0.60.0 AS tflint-source

# Hadolint Source
FROM ghcr.io/hadolint/hadolint:v2.14.0-debian AS hadolint-source

# golangci-lint Source
FROM golangci/golangci-lint:v1.62.2 AS golangci-lint-source

# Final Dev Container (Debian Slim)
FROM ghcr.io/astral-sh/uv:python3.13-trixie-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/workspace/.venv \
    VIRTUAL_ENV=/workspace/.venv \
    PATH="/workspace/.venv/bin:$PATH" \
    DEVCONTAINER=true \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    STARSHIP_CONFIG=/usr/local/etc/starship.toml

# Install system dependencies with cache mount
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        fontconfig \
        ca-certificates \
        curl \
        unzip \
        git \
        make \
        zsh \
        && rm -rf /var/lib/apt/lists/*

# Install Cascadia Code Nerd Font
RUN mkdir -p /usr/local/share/fonts/cascadiacode && \
    curl -fLo "/tmp/CascadiaCode.zip" "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/CascadiaCode.zip" && \
    unzip "/tmp/CascadiaCode.zip" -d /usr/local/share/fonts/cascadiacode && \
    rm "/tmp/CascadiaCode.zip" && \
    fc-cache -fv

# Copy Starship config
COPY .devcontainer/starship.toml /usr/local/etc/starship.toml

# Copy Go installation
COPY --from=go-source /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/root/go"
ENV PATH="${GOPATH}/bin:${PATH}"

# Copy the binaries
COPY --from=terraform-source /bin/terraform /usr/local/bin/terraform
COPY --from=tflint-source /usr/local/bin/tflint /usr/local/bin/tflint
COPY --from=hadolint-source /bin/hadolint /usr/local/bin/hadolint
COPY --from=golangci-lint-source /usr/bin/golangci-lint /usr/local/bin/golangci-lint

COPY .devcontainer/zshrc /root/.zshrc

# Install pre-commit
ENV PATH="/root/.local/bin:${PATH}"
RUN uv tool install pre-commit

# Install Starship and configure zsh
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y && \
    TARGET_USER="root" && \
    if id -u vscode >/dev/null 2>&1; then TARGET_USER="vscode"; fi && \
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)" && \
    # Clone zsh plugins
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "${TARGET_HOME}/.zsh/zsh-syntax-highlighting" && \
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "${TARGET_HOME}/.zsh/zsh-autosuggestions" && \
    # Ensure execute permissions on plugin files
    chmod +x "${TARGET_HOME}/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" && \
    chmod +x "${TARGET_HOME}/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" && \
    # Configure zsh to load plugins and starship
    echo 'source $HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> "$TARGET_HOME/.zshrc" && \
    echo 'source $HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh' >> "$TARGET_HOME/.zshrc" && \
    echo 'eval "$(starship init zsh)"' >> "$TARGET_HOME/.zshrc" && \
    # Fix ownership and set zsh as default shell
    chown -R "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/.zshrc" "$TARGET_HOME/.zsh" && \
    usermod -s /usr/bin/zsh "$TARGET_USER"

WORKDIR /workspace