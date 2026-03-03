# ZeptoClaw Dockerfile
# Multi-stage build for minimal image size
#
# Build: docker build -t zeptoclaw .
# Run:   docker run -v zeptoclaw-data:/data zeptoclaw

# =============================================================================
# Stage 1: Build
# =============================================================================
FROM rustlang/rust:nightly-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Increase rustc stack size for QEMU compatibility on ARM64 hosts
ENV RUST_MIN_STACK=16777216
# Disable LTO and single-CGU to avoid QEMU codegen crashes during cross-compilation
ENV CARGO_PROFILE_RELEASE_LTO=false
ENV CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
# Disable AVX/AVX2/AVX512 in glibc so realloc/memcpy use safe paths under QEMU emulation
ENV GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX512F,-AVX2,-AVX

# Copy manifests first for dependency caching
COPY Cargo.toml Cargo.lock* ./

# Create dummy src to build dependencies
RUN mkdir -p src/bin benches && \
    echo "fn main() {}" > src/main.rs && \
    echo "fn main() {}" > src/bin/benchmark.rs && \
    echo "pub fn lib() {}" > src/lib.rs && \
    echo "fn main() {}" > benches/message_bus.rs

# Build dependencies (cached layer)
RUN cargo build --release && rm -rf src benches

# Copy actual source and benches
COPY src ./src
COPY benches ./benches

# Touch files to ensure rebuild
RUN touch src/main.rs src/lib.rs

# Build release binary
RUN cargo build --release --bin zeptoclaw

# =============================================================================
# Stage 2: Runtime (minimal)
# =============================================================================
FROM debian:bookworm-slim AS runtime

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    git \
    gosu \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -s /bin/false -d /data zeptoclaw

# Copy binary from builder
COPY --from=builder /app/target/release/zeptoclaw /usr/local/bin/

# Copy entrypoint
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set environment
ENV RUST_LOG=zeptoclaw=info

# Expose gateway port and health check port
EXPOSE 8080 9090

# Data volume
VOLUME /data

# Entrypoint handles permissions
ENTRYPOINT ["docker-entrypoint.sh"]

# Default command - show help
CMD ["zeptoclaw", "--help"]
