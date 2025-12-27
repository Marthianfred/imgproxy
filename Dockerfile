ARG BASE_IMAGE_VERSION="v3.14.0"

FROM ghcr.io/imgproxy/imgproxy-base:${BASE_IMAGE_VERSION} AS build

ENV CGO_ENABLED=1

COPY . .
RUN bash -c 'go build -v -ldflags "-s -w" -o /opt/imgproxy/bin/imgproxy'

# Remove unnecessary files
RUN rm -rf /opt/imgproxy/lib/pkgconfig /opt/imgproxy/lib/cmake

# ==================================================================================================
# AWS Lambda adapter

FROM public.ecr.aws/awsguru/aws-lambda-adapter:0.8.4 AS lambda-adapter

# ==================================================================================================
# Final image

FROM public.ecr.aws/ubuntu/ubuntu:noble
LABEL maintainer="Sergey Alexandrovich <darthsim@gmail.com>"

RUN apt-get update \
  && apt-get upgrade -y \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    libstdc++6 \
    fontconfig-config \
    fonts-dejavu-core \
    media-types \
    libjemalloc2 \
    libtcmalloc-minimal4 \
  && ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
  && ln -s /usr/lib/$(uname -m)-linux-gnu/libtcmalloc_minimal.so.4 /usr/local/lib/libtcmalloc_minimal.so \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /etc/fonts/conf.d/10-sub-pixel-rgb.conf /etc/fonts/conf.d/11-lcdfilter-default.conf

COPY --from=build /opt/imgproxy/bin/imgproxy /opt/imgproxy/bin/
COPY --from=build /opt/imgproxy/lib /opt/imgproxy/lib
RUN ln -s /opt/imgproxy/bin/imgproxy /usr/local/bin/imgproxy

COPY docker/entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY docker/imgproxy-build-package /usr/local/bin/

# AWS Lambda adapter
COPY --from=lambda-adapter /lambda-adapter /opt/extensions/lambda-adapter

COPY NOTICE /opt/imgproxy/share/doc/

ENV VIPS_WARNING=0
ENV MALLOC_ARENA_MAX=2
ENV FONTCONFIG_PATH="/etc/fonts"
ENV IMGPROXY_MALLOC="malloc"
ENV AWS_LWA_READINESS_CHECK_PATH="/health"
ENV AWS_LWA_INVOKE_MODE="response_stream"
ENV AWS_LWA_ASYNC_INIT="true"

ENV IMGPROXY_USE_S3=true
ENV IMGPROXY_S3_ENDPOINT=https://api-s3.neoestudio.net/
ENV IMGPROXY_S3_BUCKET=traigalo
ENV IMGPROXY_S3_REGION=us-east-1
ENV AWS_ACCESS_KEY_ID=Qcnv7kEO3h1rPNvAIu5x
ENV AWS_SECRET_ACCESS_KEY=nLIvjQDZtu05FigCkA5k1KL0ZcEBn9FuOQZTLkb3
ENV IMGPROXY_USE_S3_FORCE_PATH_STYLE=true
ENV IMGPROXY_ALLOW_UNSAFE_URLS=true
ENV IMGPROXY_QUALITY=75
ENV IMGPROXY_MAX_SRC_RESOLUTION=16.8
ENV IMGPROXY_STRIP_METADATA=true
ENV IMGPROXY_STRIP_COLOR_PROFILE=true

# Disable SVE on ARM64. SVE is slower than NEON on Amazon Graviton 3
ENV VIPS_VECTOR=167772160

RUN groupadd -r imgproxy \
  && useradd -r -u 999 -g imgproxy imgproxy \
  && mkdir -p /var/cache/fontconfig \
  && chmod 777 /var/cache/fontconfig
USER 999

RUN chmod +x /opt/imgproxy/bin/imgproxy

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
CMD ["imgproxy"]

EXPOSE 7070
