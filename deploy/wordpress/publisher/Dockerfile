FROM node:20-alpine

# git + rsync for the publish step, bash for the scripts.
RUN apk add --no-cache git rsync bash curl ca-certificates tzdata

# wrangler is pinned rather than installed per-run: the publisher must not
# depend on npm reachability at publish time, and an unpinned version could
# change deploy behaviour without a commit.
RUN npm install -g wrangler@4 && wrangler --version

WORKDIR /work
ENTRYPOINT ["/bin/bash"]
