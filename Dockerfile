FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/container \
    TRANSMISSION_HOME=/home/container/.config/transmission-daemon \
    TR_SAVE_VERSION_FORMAT=4

# Empêche les services Debian de démarrer pendant la construction de l'image.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        transmission-daemon \
        ca-certificates \
        python3 \
        bash \
        openssh-client \
        rsync \
        curl \
        jq \
        lftp \
    && rm -f /usr/sbin/policy-rc.d \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 container \
    && useradd \
        --uid 1000 \
        --gid 1000 \
        --home-dir /home/container \
        --create-home \
        --shell /usr/sbin/nologin \
        container \
    && mkdir -p \
        /home/container/.config/transmission-daemon \
        /home/container/downloads/incomplete \
        /home/container/scripts \
        /home/container/logs \
    && chown -R container:container /home/container

COPY transmission-entrypoint /usr/local/bin/transmission-entrypoint
COPY transmission-torrent-done /usr/local/bin/transmission-torrent-done

RUN chmod 0755 \
    /usr/local/bin/transmission-entrypoint \
    /usr/local/bin/transmission-torrent-done

WORKDIR /home/container

USER container

CMD ["/usr/local/bin/transmission-entrypoint"]
