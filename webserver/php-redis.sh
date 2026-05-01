#!/bin/bash

set -e -x

test -n "$PHP"

# PHP 5 extension from PECL
if [ "$(dpkg-query --showformat='${Status}' --show php5-cli 2>/dev/null)" == "install ok installed" ]; then
    pecl install redis
    printf '; priority=20\nextension=redis.so\n' >/etc/php5/mods-available/redis.ini
    php5enmod redis
fi

if [ "$(dpkg-query --showformat='${Status}' --show "php${PHP}-cli" 2>/dev/null)" == "install ok installed" ]; then
    # Is php-redis available?
    if [ -n "$(aptitude --disable-columns --display-format "%p" search "?exact-name(php${PHP}-redis)")" ]; then
        # PHP extension
        apt-get install -y "php${PHP}-redis"
    elif [ -n "$(aptitude --disable-columns --display-format "%p" search "?exact-name(php-redis)")" ]; then
        # PHP extension
        apt-get install -y php-redis
    else
        # PHP extension from source
        apt-get install -y re2c php-dev
        git clone "https://github.com/phpredis/phpredis.git"
        (
            cd phpredis/
            git checkout master
            phpize
            # igbinary disables inc() and dec()
            #./configure --enable-redis-igbinary
            ./configure
            make
            make install
        )
        chmod -x "$(php-config --extension-dir)/redis.so"
        printf '; priority=20\nextension=redis.so\n' >"/etc/php/${PHP}/mods-available/redis.ini"
        phpenmod -v "$PHP" -s ALL redis

        # Run test
        php phpredis/tests/TestRedis.php --class Redis
    fi
fi

# Check extension
php --ri redis
