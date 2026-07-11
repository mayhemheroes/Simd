# syntax=docker/dockerfile:1.7
#
# Simd commit-image (small form): FROM the org C/C++ base, builds the Simd
# library + fuzzing harness(es) + test oracle via mayhem/build.sh.
#
# Build (from repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       -t simd-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG — an empty value breaks clang; do NOT promote to ENV.
ARG SOURCE_DATE_EPOCH

# Sanitizer override (default = base ASan+UBSan halting): --build-arg SANITIZER_FLAGS="..."
ARG SANITIZER_FLAGS
# Build parallelism: --build-arg MAYHEM_JOBS=8
ARG MAYHEM_JOBS=

# Install cmake + make (needed to build the Simd library; pinned to the epoch
# when SOURCE_DATE_EPOCH is set so the image stays reproducible).
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
        cmake \
        make \
    && rm -rf /var/lib/apt/lists/*
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
