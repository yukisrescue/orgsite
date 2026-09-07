FROM node:20-alpine

# git + rsync for the publish step, bash for the scripts.
# findutils is essential, not cosmetic: BusyBox find has no -printf, and the
# watcher's change detection depends on it. Without this the loop silently
# skips every tick and nothing is ever published.
RUN apk add --no-cache git rsync bash curl ca-certificates tzdata findutils

# wrangler is pinned rather than installed per-run: the publisher must not
# depend on npm reachability at publish time, and an unpinned version could
# change deploy behaviour without a commit.
RUN npm install -g wrangler@4 && wrangler --version

# The repo is bind-mounted from the host and owned by an unprivileged host
# user, while this container runs as root. Git refuses to operate on a repo
# owned by another user ("dubious ownership"), which previously made publish.sh
# see empty status output and conclude there was nothing to publish.
RUN git config --global --add safe.directory /repo \
 && git config --global user.email "wordpress@yukisrescue.org" \
 && git config --global user.name "Yuki's Rescue WordPress" \
 && git config --global credential.helper "store --file=/root/.git-credentials"

WORKDIR /work
ENTRYPOINT ["/bin/bash"]
