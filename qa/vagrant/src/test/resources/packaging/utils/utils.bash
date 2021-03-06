#!/bin/bash

# This file contains some utilities to test the elasticsearch scripts,
# the .deb/.rpm packages and the SysV/Systemd scripts.

# WARNING: This testing file must be executed as root and can
# dramatically change your system. It should only be executed
# in a throw-away VM like those made by the Vagrantfile at
# the root of the Elasticsearch source code. This should
# cause the script to fail if it is executed any other way:
[ -f /etc/is_vagrant_vm ] || {
  >&2 echo "must be run on a vagrant VM"
  exit 1
}

# Licensed to Elasticsearch under one or more contributor
# license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright
# ownership. Elasticsearch licenses this file to you under
# the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Checks if necessary commands are available to run the tests

if [ ! -x /usr/bin/which ]; then
    echo "'which' command is mandatory to run the tests"
    exit 1
fi

if [ ! -x "`which wget 2>/dev/null`" ]; then
    echo "'wget' command is mandatory to run the tests"
    exit 1
fi

if [ ! -x "`which curl 2>/dev/null`" ]; then
    echo "'curl' command is mandatory to run the tests"
    exit 1
fi

if [ ! -x "`which pgrep 2>/dev/null`" ]; then
    echo "'pgrep' command is mandatory to run the tests"
    exit 1
fi

if [ ! -x "`which unzip 2>/dev/null`" ]; then
    echo "'unzip' command is mandatory to run the tests"
    exit 1
fi

if [ ! -x "`which tar 2>/dev/null`" ]; then
    echo "'tar' command is mandatory to run the tests"
    exit 1
fi

if [ ! -x "`which unzip 2>/dev/null`" ]; then
    echo "'unzip' command is mandatory to run the tests"
    exit 1
fi

if [ ! -x "`which java 2>/dev/null`" ]; then
    echo "'java' command is mandatory to run the tests"
    exit 1
fi

# Returns 0 if the 'dpkg' command is available
is_dpkg() {
    [ -x "`which dpkg 2>/dev/null`" ]
}

# Returns 0 if the 'rpm' command is available
is_rpm() {
    [ -x "`which rpm 2>/dev/null`" ]
}

# Skip test if the 'dpkg' command is not supported
skip_not_dpkg() {
    is_dpkg || skip "dpkg is not supported"
}

# Skip test if the 'rpm' command is not supported
skip_not_rpm() {
    is_rpm || skip "rpm is not supported"
}

skip_not_dpkg_or_rpm() {
    is_dpkg || is_rpm || skip "only dpkg or rpm systems are supported"
}

# Returns 0 if the system supports Systemd
is_systemd() {
    [ -x /bin/systemctl ]
}

# Skip test if Systemd is not supported
skip_not_systemd() {
    if [ ! -x /bin/systemctl ]; then
        skip "systemd is not supported"
    fi
}

# Returns 0 if the system supports SysV
is_sysvinit() {
    [ -x "`which service 2>/dev/null`" ]
}

# Skip test if SysV is not supported
skip_not_sysvinit() {
    if [ -x "`which service 2>/dev/null`" ] && is_systemd; then
        skip "sysvinit is supported, but systemd too"
    fi
    if [ ! -x "`which service 2>/dev/null`" ]; then
        skip "sysvinit is not supported"
    fi
}

# Skip if tar is not supported
skip_not_tar_gz() {
    if [ ! -x "`which tar 2>/dev/null`" ]; then
        skip "tar is not supported"
    fi
}

# Skip if unzip is not supported
skip_not_zip() {
    if [ ! -x "`which unzip 2>/dev/null`" ]; then
        skip "unzip is not supported"
    fi
}

assert_file_exist() {
    local file="$1"
    if [ ! -e "$file" ]; then
        echo "Should exist: ${file} but does not"
    fi
    local file=$(readlink -m "${file}")
    [ -e "$file" ]
}

assert_file_not_exist() {
    local file="$1"
    if [ -e "$file" ]; then
        echo "Should not exist: ${file} but does"
    fi
    local file=$(readlink -m "${file}")
    [ ! -e "$file" ]
}

assert_file() {
    local file="$1"
    local type=$2
    local user=$3
    local group=$4
    local privileges=$5

    assert_file_exist "$file"

    if [ "$type" = "d" ]; then
        if [ ! -d "$file" ]; then
            echo "[$file] should be a directory but is not"
        fi
        [ -d "$file" ]
    else
        if [ ! -f "$file" ]; then
            echo "[$file] should be a regular file but is not"
        fi
        [ -f "$file" ]
    fi

    if [ "x$user" != "x" ]; then
        realuser=$(find "$file" -maxdepth 0 -printf "%u")
        if [ "$realuser" != "$user" ]; then
            echo "Expected user: $user, found $realuser [$file]"
        fi
        [ "$realuser" = "$user" ]
    fi

    if [ "x$group" != "x" ]; then
        realgroup=$(find "$file" -maxdepth 0 -printf "%g")
        if [ "$realgroup" != "$group" ]; then
            echo "Expected group: $group, found $realgroup [$file]"
        fi
        [ "$realgroup" = "$group" ]
    fi

    if [ "x$privileges" != "x" ]; then
        realprivileges=$(find "$file" -maxdepth 0 -printf "%m")
        if [ "$realprivileges" != "$privileges" ]; then
            echo "Expected privileges: $privileges, found $realprivileges [$file]"
        fi
        [ "$realprivileges" = "$privileges" ]
    fi
}

assert_module_or_plugin_directory() {
    local directory=$1
    shift

    #owner group and permissions vary depending on how es was installed
    #just make sure that everything is the same as $CONFIG_DIR, which was properly set up during install
    config_user=$(find "$ESHOME" -maxdepth 0 -printf "%u")
    config_owner=$(find "$ESHOME" -maxdepth 0 -printf "%g")

    assert_file $directory d $config_user $config_owner 755
}

assert_module_or_plugin_file() {
    local file=$1
    shift

    assert_file_exist "$(readlink -m $file)"
    assert_file $file f $config_user $config_owner 644
}

assert_output() {
    echo "$output" | grep -E "$1"
}

assert_recursive_ownership() {
    local directory=$1
    local user=$2
    local group=$3

    realuser=$(find $directory -printf "%u\n" | sort | uniq)
    [ "$realuser" = "$user" ]
    realgroup=$(find $directory -printf "%g\n" | sort | uniq)
    [ "$realgroup" = "$group" ]
}

# Deletes everything before running a test file
clean_before_test() {

    # List of files to be deleted
    ELASTICSEARCH_TEST_FILES=("/usr/share/cassandra" \
                            "/etc/cassandra" \
                            "/var/lib/cassandra" \
                            "/var/log/cassandra" \
                            "/tmp/elassandra" \
                            "/etc/default/cassandra" \
                            "/etc/sysconfig/cassandra"  \
                            "/var/run/cassandra"  \
                            "/usr/share/doc/cassandra" \
                            "/usr/lib/systemd/system/cassandra.service" \
                            "/usr/lib/tmpfiles.d/cassandra.conf" \
                            "/usr/lib/sysctl.d/cassandra.conf" \
                            "/usr/lib/python2.7/site-packages/cqlshlib" \
                            "/usr/lib/python2.7/dist-packages/cqlshlib" \
                            "/usr/lib/python2.7/site-packages/cqlshlib" \
                            "/usr/lib/python2.7/dist-packages/cassandra*" \
                            "/usr/lib/python2.7/site-packages/cassandra*" )

    # Kills all processes of user elasticsearch
    if id cassandra > /dev/null 2>&1; then
        pkill -u cassandra 2>/dev/null || true
    fi

    # Kills all running Elasticsearch processes
    ps aux | grep -i "org.apache.cassandra.service" | awk {'print $2'} | xargs kill -9 > /dev/null 2>&1 || true

    purge_elasticsearch

    # Removes user & group
    userdel cassandra > /dev/null 2>&1 || true
    groupdel cassandra > /dev/null 2>&1 || true


    # Removes all files
    for d in "${ELASTICSEARCH_TEST_FILES[@]}"; do
        if [ -e "$d" ]; then
            rm -rf "$d"
        fi
    done
}

purge_elasticsearch() {
    # Removes RPM package
    if is_rpm; then
        rpm --quiet -e elassandra > /dev/null 2>&1 || true
    fi

    if [ -x "`which yum 2>/dev/null`" ]; then
        yum remove -y elassandra > /dev/null 2>&1 || true
    fi

    # Removes DEB package
    if is_dpkg; then
        dpkg --purge elassandra > /dev/null 2>&1 || true
    fi

    if [ -x "`which apt-get 2>/dev/null`" ]; then
        apt-get --quiet --yes purge elassandra > /dev/null 2>&1 || true
    fi
}

# Start elasticsearch and wait for it to come up with a status.
# $1 - expected status - defaults to green
start_elasticsearch_service() {
    local desiredStatus=${1:-green}
    local index=$2
    local commandLineArgs=$3

    run_elasticsearch_service 0 $commandLineArgs

    wait_for_elasticsearch_status $desiredStatus $index

    if [ -r "/tmp/elassandra/elasticsearch.pid" ]; then
        pid=$(cat /tmp/elassandra/elasticsearch.pid)
        [ "x$pid" != "x" ] && [ "$pid" -gt 0 ]
        echo "Looking for elasticsearch pid...."
        ps $pid
    elif is_systemd; then
        run systemctl is-active cassandra.service
        [ "$status" -eq 0 ]

        run systemctl status cassandra.service
        [ "$status" -eq 0 ]

    elif is_sysvinit; then
        run service cassandra status
        [ "$status" -eq 0 ]
    fi
}

# Start elasticsearch
# $1 expected status code
# $2 additional command line args
run_elasticsearch_service() {
    local expectedStatus=$1
    local commandLineArgs=$2
    # Set the CONF_DIR setting in case we start as a service
    if [ ! -z "$CONF_DIR" ] ; then
        if is_dpkg ; then
            echo "CASSANDRA_CONF=$CONF_DIR" >> /etc/default/cassandra;
            echo "JVM_OPTS=$ES_JAVA_OPTS" >> /etc/default/cassandra;
        elif is_rpm; then
            echo "CASSANDRA_CONF=$CONF_DIR" >> /etc/sysconfig/cassandra;
            echo "JVM_OPTS=$ES_JAVA_OPTS" >> /etc/sysconfig/cassandra
        fi
    fi

    if [ -f "/tmp/elassandra/bin/cassandra" ]; then
        if [ -z "$CONF_DIR" ]; then
            local CONF_DIR=""
            local ES_PATH_CONF=""
        else
            local ES_PATH_CONF="-Epath.conf=$CONF_DIR"
        fi
        # we must capture the exit code to compare so we don't want to start as background process in case we expect something other than 0
        local background="-f"
        local timeoutCommand=""
        if [ "$expectedStatus" = 0 ]; then
            background=""
        else
            timeoutCommand="timeout 60s "
        fi

        # su and the Elasticsearch init script work together to break bats.
        # sudo isolates bats enough from the init script so everything continues
        # to tick along
        run sudo -u cassandra bash <<BASH
# If jayatana is installed then we try to use it. Elasticsearch should ignore it even when we try.
# If it doesn't ignore it then Elasticsearch will fail to start because of security errors.
# This line is attempting to emulate the on login behavior of /usr/share/upstart/sessions/jayatana.conf
[ -f /usr/share/java/jayatanaag.jar ] && export JAVA_TOOL_OPTIONS="-javaagent:/usr/share/java/jayatanaag.jar"
# And now we can start Elasticsearch normally, in the background (-d) and with a pidfile (-p).
export JVM_OPTS=$ES_JAVA_OPTS
[ -n "$CONF_DIR" ] && export CASSANDRA_CONF="$CONF_DIR"
export CASSANDRA_HOME="$ESHOME"
$timeoutCommand/tmp/elassandra/bin/cassandra -e $background -p /tmp/elassandra/elasticsearch.pid $commandLineArgs
BASH
        [ "$status" -eq "$expectedStatus" ]
    elif is_systemd; then
        run systemctl daemon-reload
        [ "$status" -eq 0 ]

        run systemctl enable cassandra.service
        [ "$status" -eq 0 ]

        run systemctl is-enabled cassandra.service
        [ "$status" -eq 0 ]

        run systemctl start cassandra.service
        [ "$status" -eq "$expectedStatus" ]

    elif is_sysvinit; then
        run service cassandra start
        [ "$status" -eq "$expectedStatus" ]
    fi
}

stop_elasticsearch_service() {
    if [ -r "/tmp/elassandra/elasticsearch.pid" ]; then
        pid=$(cat /tmp/elassandra/elasticsearch.pid)
        [ "x$pid" != "x" ] && [ "$pid" -gt 0 ]

        kill -SIGTERM $pid

        run kill -SIGTERM $pid
        while [ "$status" -eq 0 ]; do
            run kill -SIGTERM $pid
        done

    elif is_systemd; then
        run systemctl stop cassandra.service
        [ "$status" -eq 0 ]

        run systemctl is-active cassandra.service
        [ "$status" -eq 3 ]

        echo "$output" | grep -E 'inactive|failed'

    elif is_sysvinit; then
        run service cassandra stop
        [ "$status" -eq 0 ]

        run service cassandra status
        [ "$status" -ne 0 ]
    fi
}

# Waits for Elasticsearch to reach some status.
# $1 - expected status - defaults to green
wait_for_elasticsearch_status() {
    local desiredStatus=${1:-green}
    local index=$2

    echo "Making sure elasticsearch is up..."
    wget -O - --retry-connrefused --waitretry=1 --timeout=60 --tries 60 http://localhost:9200/_cluster/health || {
          echo "Looks like elasticsearch never started. Here is its log:"
          if [ -e "$ESLOG/system.log" ]; then
              cat "$ESLOG/system.log"
          else
              echo "The elasticsearch log doesn't exist. Maybe /var/log/messages has something:"
              tail -n20 /var/log/messages
          fi
          false
    }

    if [ -z "index" ]; then
      echo "Tring to connect to elasticsearch and wait for expected status $desiredStatus..."
      curl -sS "http://localhost:9200/_cluster/health?wait_for_status=$desiredStatus&timeout=60s&pretty"
    else
      echo "Trying to connect to elasticsearch and wait for expected status $desiredStatus for index $index"
      curl -sS "http://localhost:9200/_cluster/health/$index?wait_for_status=$desiredStatus&timeout=60s&pretty"
    fi
    if [ $? -eq 0 ]; then
        echo "Connected"
    else
        echo "Unable to connect to Elasticsearch"
        false
    fi

    echo "Checking that the cluster health matches the waited for status..."
    run curl -sS -XGET 'http://localhost:9200/_cat/health?h=status&v=false'
    if [ "$status" -ne 0 ]; then
        echo "error when checking cluster health. code=$status output="
        echo $output
        false
    fi
    echo $output | grep $desiredStatus || {
        echo "unexpected status:  '$output' wanted '$desiredStatus'"
        false
    }
}

install_elasticsearch_test_scripts() {
    install_script is_guide.groovy
    install_script is_guide.mustache
}

# Executes some basic Elasticsearch tests
run_elasticsearch_tests() {
    # TODO this assertion is the same the one made when waiting for
    # elasticsearch to start
    run curl -XGET 'http://localhost:9200/_cat/health?h=status&v=false'
    [ "$status" -eq 0 ]
    echo "$output" | grep -w "green"

    curl -s -XPOST 'http://localhost:9200/library/book/1?refresh=true&pretty' -d '{
      "title": "Elasticsearch - The Definitive Guide"
    }'

    curl -s -XGET 'http://localhost:9200/_count?pretty'
    curl -s -XGET 'http://localhost:9200/_count?pretty' |
      grep \"count\"\ :\ 1

    curl -s -XPOST 'http://localhost:9200/library/book/_count?pretty' -d '{
      "query": {
        "script": {
          "script": {
            "file": "is_guide",
            "lang": "groovy"
          }
        }
      }
    }' | grep \"count\"\ :\ 1

    curl -s -XGET 'http://localhost:9200/library/book/_search/template?pretty' -d '{
      "file": "is_guide"
    }' | grep \"total\"\ :\ 1

    curl -s -XDELETE 'http://localhost:9200/_all'
}

# Move the config directory to another directory and properly chown it.
move_config() {
    local oldConfig="$ESCONFIG"
    export ESCONFIG="${1:-$(mktemp -d -t 'config.XXXX')}"
    export CASSANDRA_CONF="$ESCONFIG"
    echo "Moving configuration directory from $oldConfig to $ESCONFIG"

    # Move configuration files to the new configuration directory
    mv "$oldConfig"/* "$ESCONFIG"
    chown -R cassandra:cassandra "$ESCONFIG"
    assert_file_exist "$ESCONFIG/elasticsearch.yml"
    assert_file_exist "$ESCONFIG/jvm.options"
    assert_file_exist "$ESCONFIG/cassandra.yaml"
    assert_file_exist "$ESCONFIG/cassandra-env.sh"
    assert_file_exist "$ESCONFIG/logback-tools.xml"
}

# Copies a script into the Elasticsearch install.
install_script() {
    local name=$1
    mkdir -p $ESSCRIPTS
    local script="$BATS_TEST_DIRNAME/example/scripts/$name"
    echo "Installing $script to $ESSCRIPTS"
    cp $script $ESSCRIPTS
}

# permissions from the user umask with the executable bit set
executable_privileges_for_user_from_umask() {
    local user=$1
    shift

    echo $((0777 & ~$(sudo -E -u $user sh -c umask) | 0111))
}

# permissions from the user umask without the executable bit set
file_privileges_for_user_from_umask() {
    local user=$1
    shift

    echo $((0777 & ~$(sudo -E -u $user sh -c umask) & ~0111))
}
