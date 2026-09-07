# The official WordPress image ships no WP-CLI, but every setup, content, and
# export task in this project drives WordPress through it. Installing it with
# `docker exec` does not survive an image pull, so it is baked in here.
FROM wordpress:6-php8.3-apache

RUN set -eux; \
    curl -fsSL -o /usr/local/bin/wp \
      https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; \
    chmod +x /usr/local/bin/wp; \
    # wp-cli.phar is architecture-independent PHP, so this works on arm64.
    su -s /bin/sh www-data -c 'wp --info' >/dev/null
