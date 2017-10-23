FROM gitlab/gitlab-runner:alpine
LABEL maintainer="Dave Conroy (dave at tiredofit dot ca)"

### Set Defaults/Arguments
    ARG S6_OVERLAY_VERSION=v1.21.1.1 
    ARG MAJOR_VERSION=3.4
    ARG ZBX_VERSION=${MAJOR_VERSION}.1
    ARG ZBX_SOURCES=svn://svn.zabbix.com/tags/${ZBX_VERSION}/

### Set Defaults
    ENV DEBUG_MODE=FALSE \
        ENABLE_CRON=TRUE \
        ENABLE_SMTP=FALSE \
        ENABLE_ZABBIX=TRUE

### Zabbix Pre Installation steps
    RUN addgroup zabbix && \
        adduser -S \
                -D -G zabbix \
                -h /var/lib/zabbix/ \
            zabbix && \
        mkdir -p /etc/zabbix && \
        mkdir -p /etc/zabbix/zabbix_agentd.d && \
        mkdir -p /var/lib/zabbix && \
        mkdir -p /var/lib/zabbix/enc && \
        mkdir -p /var/lib/zabbix/modules && \
        chown --quiet -R zabbix:root /var/lib/zabbix && \
        apk update && \
        apk add \
                iputils \
                bash \
                coreutils \
                pcre \
                libssl1.0 && \

### Zabbix Compilation
      apk add ${APK_FLAGS_DEV} --virtual zabbix-build-dependencies \
              alpine-sdk \
              automake \
              autoconf \
              openssl-dev \
              pcre-dev \
              subversion && \
      cd /tmp/ && \
      svn --quiet export ${ZBX_SOURCES} zabbix-${ZBX_VERSION} 1>/dev/null && \
      cd /tmp/zabbix-${ZBX_VERSION} && \
      zabbix_revision=`svn info ${ZBX_SOURCES} |grep "Last Changed Rev"|awk '{print $4;}'` && \
      sed -i "s/{ZABBIX_REVISION}/$zabbix_revision/g" include/version.h && \
      ./bootstrap.sh 1>/dev/null && \
      export CFLAGS="-fPIC -pie -Wl,-z,relro -Wl,-z,now" && \
      ./configure \
              --prefix=/usr \
              --silent \
              --sysconfdir=/etc/zabbix \
              --libdir=/usr/lib/zabbix \
              --datadir=/usr/lib \
              --enable-agent \
              --enable-ipv6 \
              --with-openssl && \
      make -j"$(nproc)" -s 1>/dev/null && \
      cp src/zabbix_agent/zabbix_agentd /usr/sbin/zabbix_agentd && \
      cp src/zabbix_sender/zabbix_sender /usr/sbin/zabbix_sender && \
      cp conf/zabbix_agentd.conf /etc/zabbix && \
      mkdir -p /etc/zabbix/zabbix_agentd.conf.d && \
      mkdir -p /var/log/zabbix && \
      chown -R zabbix:root /var/log/zabbix && \
      chown --quiet -R zabbix:root /etc/zabbix && \
      cd /tmp/ && \
      rm -rf /tmp/zabbix-${ZBX_VERSION}/ && \
      apk del --purge \
              coreutils \
              zabbix-build-dependencies && \


### Install MailHog
      apk --no-cache add --virtual mailhog-build-dependencies \
                go \
                git \
                musl-dev \
                && \
       mkdir -p /usr/src/gocode && \
       export GOPATH=/usr/src/gocode && \
       go get github.com/mailhog/MailHog && \
       go get github.com/mailhog/mhsendmail && \
       mv /usr/src/gocode/bin/MailHog /usr/local/bin && \
       mv /usr/src/gocode/bin/mhsendmail /usr/local/bin && \
       rm -rf /usr/src/gocode && \
       apk del --purge mailhog-build-dependencies && \
       adduser -D -u 1025 mailhog && \

### Add Core Utils
       apk --no-cache upgrade && \
       apk --no-cache add \
            bash \
            curl \
            less \
            logrotate \
            msmtp \
            nano \
            sudo \
            tzdata \
            vim \
            zabbix-agent \
            && \
       rm -rf /var/cache/apk/* && \
       rm -rf /etc/logrotate.d/acpid && \
       cp -R /usr/share/zoneinfo/America/Vancouver /etc/localtime && \
       echo 'America/Vancouver' > /etc/timezone && \

### S6 Installation
       curl -sSL https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-amd64.tar.gz | tar xfz - -C / && \
   
### Add Folders
       mkdir -p /assets/cron

   ADD /install /

### Networking Configuration
   EXPOSE 1025 8025 10050/TCP 

### Entrypoint Configuration
   ENTRYPOINT ["/init"]
