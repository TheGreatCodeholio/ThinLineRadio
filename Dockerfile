# syntax=docker/dockerfile:1.7

# ThinLine Radio - Multi-stage Docker Build
# This Dockerfile builds both the Angular client and Go server in separate stages
# and creates a minimal production image with only the necessary runtime dependencies
# Compatible with arm64 and amd64

# =============================================================================
# Stage 1: Build Angular Client
# =============================================================================
FROM --platform=$BUILDPLATFORM node:20-alpine AS client-builder

WORKDIR /build

# Copy package files first for better caching
COPY client/package*.json ./client/

# Install dependencies
WORKDIR /build/client
RUN npm install --legacy-peer-deps

# Copy client source code
COPY client/ ./

# Build production bundle
RUN npm run build

# Optional verification
RUN echo "Client build completed"

# =============================================================================
# Stage 2: Build Go Server
# =============================================================================
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS server-builder

WORKDIR /build/server

# Docker buildx automatically sets these
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# Install build dependencies
RUN apk add --no-cache git

# Copy go mod files first for better caching
COPY server/go.mod server/go.sum ./
RUN go mod download

# Copy server source code
COPY server/ ./

# Copy built Angular webapp from previous stage
# Adjust the source path below if your Angular build outputs elsewhere
COPY --from=client-builder /build/server/webapp ./webapp/

# Build static binary for the target platform
ENV CGO_ENABLED=0

RUN echo "Building for ${TARGETOS}/${TARGETARCH}${TARGETVARIANT}" && \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /build/thinline-radio .

# Verify binary was created
RUN ls -lh /build/thinline-radio

# =============================================================================
# Stage 3: Production Runtime Image
# =============================================================================
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    ffmpeg \
    ca-certificates \
    tzdata \
    wget \
    && rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1000 thinline && \
    adduser -D -u 1000 -G thinline thinline

# Create application directories
RUN mkdir -p /app/data /app/config /app/logs && \
    chown -R thinline:thinline /app

WORKDIR /app

# Copy binary from builder stage
COPY --from=server-builder /build/thinline-radio /app/thinline-radio

# Copy Docker entrypoint script
COPY docker-entrypoint.sh /app/
RUN chmod +x /app/docker-entrypoint.sh /app/thinline-radio && \
    chown thinline:thinline /app/thinline-radio /app/docker-entrypoint.sh

# Copy documentation
COPY LICENSE README.md /app/

# Switch to non-root user
USER thinline

# Expose ports
EXPOSE 3000 3443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/ || exit 1

# Environment variables
ENV DB_TYPE=postgresql \
    DB_HOST=localhost \
    DB_PORT=5432 \
    DB_NAME=thinline_radio \
    DB_USER="" \
    DB_PASS="" \
    LISTEN=0.0.0.0:3000

# Default entrypoint
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD []

# Labels
LABEL maintainer="Thinline Dynamic Solutions" \
      description="ThinLine Radio - Comprehensive radio scanner platform" \
      version="7.0.0" \
      org.opencontainers.image.source="https://github.com/Thinline-Dynamic-Solutions/ThinLineRadio" \
      org.opencontainers.image.licenses="GPL-3.0"

