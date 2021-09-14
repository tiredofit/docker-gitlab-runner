FROM gitlab/gitlab-runner:alpine
LABEL maintainer="Dave Conroy (github.com/tiredofit)"

ARG ZABBIX_VERSION
ARG FLUENTBIT_VERSION
#ARG PROMTAIL_VERSION
ARG S6_OVERLAY_VERSION

### Set defaults
ENV FLUENTBIT_VERSION=${FLUENTBIT_VERSION:-"1.8.6"} \
    #PROMTAIL_VERSION=${PROMTAIL_VERSION:-"v2.3.0"} \
    S6_OVERLAY_VERSION=${S6_OVERLAY_VERSION:-"v2.2.0.3"} \
    ZABBIX_VERSION=${ZABBIX_VERSION:-"5.4.4"} \
    DEBUG_MODE=FALSE \
    TIMEZONE=Etc/GMT \
    CONTAINER_ENABLE_SCHEDULING=TRUE \
    CONTAINER_SCHEDULING_BACKEND=cron \
    CONTAINER_ENABLE_MESSAGING=TRUE \
    CONTAINER_MESSAGING_BACKEND=msmtp \
    CONTAINER_ENABLE_MONITORING=TRUE \
    CONTAINER_MONITORING_BACKEND=zabbix \
    CONTAINER_ENABLE_LOGSHIPPING=FALSE

## Mono Repo workarounds
RUN case "$(cat /etc/os-release | grep VERSION_ID | cut -d = -f 2 | cut -d . -f 1,2)" in \
        3.5|3.6) no_upx=true ;; \
        *) busybox_extras="busybox-extras" ;; \
    esac ; \
    \
    case "$(cat /etc/os-release | grep VERSION_ID | cut -d = -f 2 | cut -d . -f 1,2)" in \
        3.11|3.12|3.13|3.14|3.15) zabbix_args=" --enable-agent2 " ; zabbix_agent2=true ; fluentbit_make=true ;; \
        *) : ;; \
    esac ; \
    \
    apkArch="$(apk --print-arch)" ; \
    case "$apkArch" in \
        x86_64) upx=upx ;; \
        *) : ;; \
    esac; \
    \
    case "$(cat /etc/os-release | grep VERSION_ID | cut -d = -f 2 | cut -d . -f 1,2)" in \
        3.5|3.6) upx="" ;; \
    esac ; \
    \
##
    set -ex && \
    apk update && \
    apk upgrade && \
    ### Add core utils
    apk add -t .base-rundeps \
                bash \
                ${busybox_extras} \
                curl \
                fts \
                grep \
                iputils \
                less \
                libgcc \
                $(apk search libssl1* -q) \
                libressl \
                logrotate \
                msmtp \
                nano \
                pcre \
                s6 \
                sudo \
                tzdata \
                vim \
                && \
    \
    apk add -t .zabbix-build-deps \
                alpine-sdk \
                autoconf \
                automake \
                binutils \
                coreutils \
                go \
                g++ \
                openssl-dev \
                make \
                pcre-dev \
                zlib-dev \
                ${additional_packages}\
                ${upx} \
                && \
    \
    apk add -t .fluentbit-build-deps \
                bison \
                cmake \
                flex \
                fts-dev \
                && \
    \
    cp -R /usr/share/zoneinfo/${TIMEZONE} /etc/localtime && \
    echo "${TIMEZONE}" > /etc/timezone && \
    \
    ## Quiet down sudo
    echo "Set disable_coredump false" > /etc/sudo.conf && \
    \
### Zabbix installation
    addgroup -g 10050 zabbix && \
    adduser -S -D -H -h /dev/null -s /sbin/nologin -G zabbix -u 10050 zabbix && \
    mkdir -p /etc/zabbix && \
    mkdir -p /etc/zabbix/zabbix_agentd.conf.d && \
    mkdir -p /var/lib/zabbix && \
    mkdir -p /var/lib/zabbix/enc && \
    mkdir -p /var/lib/zabbix/modules && \
    mkdir -p /var/log/zabbix && \
    chown --quiet -R zabbix:root /etc/zabbix && \
    chown --quiet -R zabbix:root /var/lib/zabbix && \
    chown --quiet -R zabbix:root /var/log/zabbix && \
    \
### Zabbix compilation
    mkdir -p /usr/src/zabbix && \
    curl -sSL https://github.com/zabbix/zabbix/archive/${ZABBIX_VERSION}.tar.gz | tar xfz - --strip 1 -C /usr/src/zabbix && \
    cd /usr/src/zabbix && \
    ./bootstrap.sh 1>/dev/null && \
    export CFLAGS="-fPIC -pie -Wl,-z,relro -Wl,-z,now" && \
    ./configure \
            --prefix=/usr \
            --silent \
            --sysconfdir=/etc/zabbix \
            --libdir=/usr/lib/zabbix \
            --datadir=/usr/lib \
            --enable-agent ${zabbix_args} \
            --enable-ipv6 \
            --with-openssl \
            && \
    make -j"$(nproc)" -s 1>/dev/null && \
    cp src/zabbix_agent/zabbix_agentd /usr/sbin/zabbix_agentd && \
    cp src/zabbix_sender/zabbix_sender /usr/sbin/zabbix_sender && \
    if [ "$zabbix_agent2" = "true" ] ; then cp src/go/bin/zabbix_agent2 /usr/sbin/zabbix_agent2 ; fi ; \
    strip /usr/sbin/zabbix_agentd && \
    strip /usr/sbin/zabbix_sender && \
    if [ "$zabbix_agent2" = true ] ; then strip /usr/sbin/zabbix_agent2 ; fi ; \
    if [ "$apkArch" = "x86_64" ] && [ "$no_upx" != "true" ]; then upx /usr/sbin/zabbix_agentd ; fi ; \
    if [ "$apkArch" = "x86_64" ] && [ "$no_upx" != "true" ]; then upx /usr/sbin/zabbix_sender ; fi ; \
    if [ "$apkArch" = "x86_64" ] && [ "$zabbix_agent2" = "true" ] && [ "$no_upx" != "true" ]; then upx /usr/sbin/zabbix_agent2 ; fi ; \
    rm -rf /usr/src/zabbix && \
    \
### Fluentbit compilation
    mkdir -p /usr/src/fluentbit && \
    curl -sSL https://github.com/fluent/fluent-bit/archive/v${FLUENTBIT_VERSION}.tar.gz | tar xfz - --strip 1 -C /usr/src/fluentbit && \
    cd /usr/src/fluentbit && \
    curl -sSL https://git.alpinelinux.org/aports/plain/testing/fluent-bit/chunkio-static-lib-fts.patch | patch -p1 && \
    curl -sSL https://git.alpinelinux.org/aports/plain/testing/fluent-bit/10-def-core-stack-size.patch | patch -p1 && \
    cmake \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=None \
        -DFLB_AWS=No \
        -DFLB_BACKTRACE=No \
        -DFLB_CORO_STACK_SIZE=24576\
        -DFLB_DEBUG=No \
        -DFLB_EXAMPLES=No \
        -DFLB_FILTER_AWS=No \
        -DFLB_FILTER_KUBERNETES=No \
        -DFLB_HTTP_SERVER=Yes \
        -DFLB_IN_COLLECTD=No \
        -DFLB_IN_CPU=No \
        -DFLB_IN_DOCKER=No \
        -DFLB_IN_DOCKER_EVENTS=No \
        -DFLB_IN_KMSG=No \
        -DFLB_IN_MEM=No \
        -DFLB_IN_MQTT=No \
        -DFLB_IN_NETIF=No \
        -DFLB_IN_SERIAL=No \
        -DFLB_IN_SYSTEMD=No \
        -DFLB_IN_TCP=No \
        -DFLB_IN_THERMAL=No \
        -DFLB_IN_WINLOG=No \
        -DFLB_IN_WINSTAT=No \
        -DFLB_JEMALLOC=Yes \
        -DFLB_LUAJIT=No \
        -DFLB_OUT_AZURE=No \
        -DFLB_OUT_AZURE_BLOB=No \
        -DFLB_OUT_BIGQUERY=No \
        -DFLB_OUT_CALYPTIA=No \
        -DFLB_OUT_CLOUDWATCH_LOGS=No \
        -DFLB_OUT_COUNTER=No \
        -DFLB_OUT_DATADOG=No \
        -DFLB_OUT_GELF=No \
        -DFLB_OUT_INFLUXDB=No \
        -DFLB_OUT_KAFKA=No \
        -DFLB_OUT_KAFKA_REST=No \
        -DFLB_OUT_KINESIS_FIREHOSE=No \
        -DFLB_OUT_KINESIS_STREAMS=No \
        -DFLB_OUT_LOGDNA=No \
        -DFLB_OUT_NATS=No \
        -DFLB_OUT_NRLOGS=No \
        -DFLB_OUT_PGSQL=No \
        -DFLB_OUT_S3=No \
        -DFLB_OUT_SLACK=No \
        -DFLB_OUT_SPLUNK=No \
        -DFLB_OUT_STACKDRIVER=No \
        -DFLB_OUT_TCP=No \
        -DFLB_OUT_TD=No \
        -DFLB_RELEASE=Yes \
        -DFLB_SHARED_LIB=No \
        -DFLB_SIGNV4=No \
        -DFLB_SMALL=No \
        . && \
    if [ "$fluentbit_make" = "true" ] ; then if [ "$apkArch" = "x86_64" ] ; then make -j"$(nproc)" ; make install ; mv /usr/etc/fluent-bit /etc/fluent-bit ; mkdir -p /etc/fluent-bit/parsers.d; mkdir -p /etc/fluent-bit/conf.d ; strip /usr/bin/fluent-bit ; if [ "$apkArch" = "x86_64" ] && [ "$no_upx" != "true" ]; then upx /usr/bin/fluent-bit ; fi ; fi ; fi ;\
    \
    ### Promtail (Disabled)
    #git clone https://github.com/grafana/loki.git /usr/src/loki && \
    #cd /usr/src/loki && \
    #git checkout "${PROMTAIL_VERSION}" && \
    #CGO_ENABLED=0 GOOS=linux GO111MODULE=on \
    #go build -v -ldflags '-s -w' -o promtail ./clients/cmd/promtail && \
    #mv promtail /usr/sbin && \
    \
    ### Clean up
    mkdir -p /etc/logrotate.d && \
    apk del --purge \
            .zabbix-build-deps \
            .fluentbit-build-deps \
            && \
    rm -rf /etc/logrotate.d/* && \
    rm -rf /root/.cache && \
    rm -rf /root/go && \
    rm -rf /tmp/* && \
    rm -rf /usr/src/* && \
    rm -rf /var/cache/apk/* && \
    \
    ### S6 overlay installation
    case "$apkArch" in \
        x86_64) s6Arch='amd64' ;; \
        armv7) s6Arch='arm' ;; \
        armhf) s6Arch='armhf' ;; \
        aarch64) s6Arch='aarch64' ;; \
        ppc64le) s6Arch='ppc64le' ;; \
        *) echo >&2 "Error: unsupported architecture ($apkArch)"; exit 1 ;; \
    esac; \
    curl -sSL https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-${s6Arch}.tar.gz | tar xfz - -C /

### Networking configuration
EXPOSE 2020/TCP 10050/TCP

### Entrypoint configuration
ENTRYPOINT ["/init"]

### Add folders
ADD install/ /
