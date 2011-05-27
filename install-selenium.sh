#!/bin/bash

set -e

# if you change this, search and replace throgh this file as well.
SELENIUM_RC_VER="1.0.1"

# install dependencies (not including browser)
apt-get install \
  sun-java6-jre \
  sun-java6-fonts \
  sun-java6-javadb \
  xvfb

# create selenium user acct.
adduser --quiet --system --disabled-login --group \
  --gecos="Selenium-RC Server User Account" \
  --home="/var/lib/selenium" selenium
mkdir -p /var/lib/selenium
chown -R selenium:selenium /var/lib/selenium


# download, unpack & install under /opt
if [ ! -d "/opt/selenium-server-$SELENIUM_RC_VER" ]; then
    # TODO: download & unpack into a safe tempdir, and clean up after.

    [ -e "selenium-remote-control-$SELENIUM_RC_VER-dist.zip" ] ||
        wget "http://release.seleniumhq.org/selenium-remote-control/$SELENIUM_RC_VER/selenium-remote-control-$SELENIUM_RC_VER-dist.zip"

    # selenium 1.0.3, is located on a different host, and is broken.
    #wget "http://selenium.googlecode.com/files/selenium-remote-control-$SELENIUM_RC_VER.zip"

    unzip "selenium-remote-control-$SELENIUM_RC_VER-dist.zip"
    rm -rf "/opt/selenium-server-$SELENIUM_RC_VER"
    mv "selenium-remote-control-$SELENIUM_RC_VER/selenium-server-$SELENIUM_RC_VER" "/opt/selenium-server-$SELENIUM_RC_VER"
    chown -R root:root "/opt/selenium-server-$SELENIUM_RC_VER"
else
    echo
    echo "Selenium seems to already be installed under /opt/selenium-server-$SELENIUM_RC_VER"
    echo
fi

# create /etc/default/selenium
cat <<'END_TXT' | tee /etc/default/selenium > /dev/null
# sourced by /etc/init.d/selenium

### where to find java and the selenium-server.jar file
SELENIUM_JAVA_BIN=/usr/bin/java
SELENIUM_JAR=/opt/selenium-server-1.0.1/selenium-server.jar

### selenium requires xvfb to run as a "headless daemon"
SELENIUM_XVFB_BIN=/usr/bin/xvfb-run

### tcp port for selenium to listen on
### NOTE: must be greater than 1024
SELENIUM_PORT=4444

### user/group to run selenium server as
SELENIUM_USER=selenium
SELENIUM_GROUP=selenium

### additional options to pass to selenium-server.jar on the command line
SELENIUM_OPT=""

### turn on logging
SELENIUM_LOGGING=0

### if logging is on, log browser interactions
SELENIUM_LOG_BROWSER=0

END_TXT


# create init script...
cat <<'END_TXT' | tee /etc/init.d/selenium > /dev/null
#! /bin/bash
### BEGIN INIT INFO
# Provides:          selenium
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Should-Start:      $named
# Should-Stop:       $named
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: selenium website testing server, installed under /opt
# Description:       selenium 1.x website integration testing server,
#                    installed under /opt
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin

NAME=selenium


### default settings. users can override
### these in the /etc/default config files

SELENIUM_JAVA_BIN=/usr/bin/java
SELENIUM_XVFB_BIN=/usr/bin/xvfb-run
SELENIUM_JAR=/opt/selenium-server-1.0.1/selenium-server.jar
SELENIUM_PORT=4444
SELENIUM_USER=selenium
SELENIUM_GROUP=selenium
SELENIUM_OPT=""
SELENIUM_LOGGING=0
SELENIUM_LOG_BROWSER=0


### load user settings
[ -r /etc/default/selenium ] && . /etc/default/selenium


### just shorter var names for convenience in this script:

JAVA_BIN=$SELENIUM_JAVA_BIN
XVFB_BIN=$SELENIUM_XVFB_BIN
PORT=$SELENIUM_PORT
USER=$SELENIUM_USER
GROUP=$SELENIUM_GROUP

### hard-coded vars & vars derived from other vars
USER_HOME=`getent passwd $USER | cut -d':' -f6`
PROFILE_DIR=$USER_HOME/firefox-profiles
PROFILE_NAME=SeleniumUser
PID_FILE=/var/run/selenium.pid
LOG_DIR=$USER_HOME/logs
LOG_LINK=/var/log/selenium
LOG_FILE_DEBUG=$LOG_DIR/selenium-server.log
LOG_FILE_XVFB=$LOG_DIR/xvfb.log



### LSB-compliant init script functions
. /lib/lsb/init-functions



### make sure all the necessary dirs and files 
### are present and set up correctly.
function init_selenium() {

	### make sure the Selenium profile dir exists and is set up properly.
	if [ ! -d "$PROFILE_DIR/$PROFILE_NAME" ]; then
		if ! mkdir -p "$PROFILE_DIR/$PROFILE_NAME"; then
		log_failure_msg "could not create $PROFILE_DIR/$PROFILE_NAME"
		exit 1
		fi
	fi
	if ! chown -R "$USER":"$GROUP" "$PROFILE_DIR"; then
		log_failure_msg "could not set ownership on $PROFILE_DIR"
		exit 1
	fi


	### set up a mozilla profile dir for the user
	# create temp file with default profile.ini
	if ! TMP_PROF=$(tempfile); then 
		log_failure_msg "could not create a mozilla profile"
		exit 1
	fi
	# I hate shell.
	trap "rm -f -- '$TMP_PROF'" EXIT

	cat <<-END_PROFILE > "$TMP_PROF"
	[General]
	StartWithLastProfile=1

	[Profile0]
	Name=$PROFILE_NAME
	IsRelative=0
	Path=$PROFILE_DIR/$PROFILE_NAME
	Default=1

	END_PROFILE

	# put the mozilla profile folder into place
	MOZILLA_FOLDER="$USER_HOME/.mozilla/firefox"
	# make sure the dir exists
	if ! mkdir -p "$MOZILLA_FOLDER"; then
		log_failure_msg "could not create $MOZILLA_FOLDER"
		exit 1
	fi
	if [ -e "$MOZILLA_FOLDER/profiles.ini" ]; then
		if ! diff "$TMP_PROF" "$MOZILLA_FOLDER/profiles.ini" >/dev/null; then
		log_warning_msg "existing $MOZILLA_FOLDER/profiles.ini differs from default"
		fi
	else
		if ! mv "$TMP_PROF" "$MOZILLA_FOLDER/profiles.ini"; then
			log_error_msg "failed to set up $MOZILLA_FOLDER/profiles.ini"
			exit 1
		fi
	fi
	rm -f -- "$TMP_PROF"
	trap - EXIT

	# NOTE: bad hack. should target just .mozilla and .gnome2 dirs.
	if ! chown -R "$USER":"$GROUP" "$USER_HOME"; then
		log_failure_msg "could not set ownership on $USER_HOME"
		exit 1
	fi

	### make sure xvfb-run is available
	if [ ! -x "$XVFB_BIN" ]; then
		log_failure_msg "can not execute $XVFB_BIN"
		exit 1
	fi

	### make sure java and the selenium jar are available
	if [ ! -x "$JAVA_BIN" ]; then
		log_failure_msg "can not execute $JAVA_BIN"
		exit 1
	fi
	if [ ! -e "$SELENIUM_JAR" ]; then
		log_failure_msg "can not find $SELENIUM_JAR"
		exit 1
	fi

	### make sure we can write log files
	if [ ! -d "$LOG_DIR" ]; then
		if ! mkdir -p "$LOG_DIR"; then
			log_failure_msg "could not create $LOG_DIR"
			exit 1;
		fi
		if ! chown "$USER":"$GROUP" "$LOG_DIR"; then
			log_failure_msg "could not set ownership on $LOG_DIR"
			exit 1
		fi
	fi
	if ! ln -sf $LOG_DIR $LOG_LINK; then
		log_failure_msg "could not link $LOG_LINK to $LOG_DIR"
		exit 1
	fi


	### make sure we can manage our pid file
	PID_DIR=`dirname $PID_FILE`
	if [ ! -d "$PID_DIR" ]; then
		if ! mkdir -p $PID_DIR; then
			log_failure_msg "could not create $PID_DIR"
			exit 1;
		fi
	fi
}



### does what you think it does :)
function start_selenium() {

    init_selenium || return $?

    if [ $SELENIUM_LOGGING ]; then
        sel_log_opts="-log $LOG_FILE_DEBUG"
        [ $SELENIUM_LOG_BROWSER ] && sel_log_opts="$sel_log_opts -browserSideLog"
    fi

    # is selenium already running?
    pidofproc -p $PID_FILE $JAVA_BIN >/dev/null
    if [ $? -eq 0 ]; then
        PID=$( cat $PID_FILE )
        log_warning_msg "already running (pid $PID)"
        exit 0
    fi

    start-stop-daemon \
        --start \
        --background \
        --pidfile $PID_FILE \
        --make-pidfile \
        --chuid "$USER":"$GROUP" \
        --startas $XVFB_BIN -- \
            --wait=2 \
            --auto-servernum \
            --error-file="$LOG_FILE_XVFB" \
            --server-args="-screen 0 1024x768x24" \
                $JAVA_BIN -jar $SELENIUM_JAR \
                    -timeout 180 \
                    -singlewindow \
                    -port $PORT \
                    $sel_log_opts \
                    -firefoxProfileTemplate "$PROFILE_DIR/$PROFILE_NAME" \
                    $SELENIUM_OPT \
        >/dev/null

    # what a PITA just to get the pid of the java process and verify it's running.
    [ $? -eq 0 ] || return 1
    DPID=$( cat $PID_FILE )
    [ -n "$DPID" ] || return 1
    # xvfb-run introduces a 2-sec delay, and 
    # java proably needs another 3 to start
    sleep 5
    JAVA_PID=$( ps h --ppid $DPID -o pid,cmd | grep $JAVA_BIN | awk '{print $1}' );
    [ -n "$JAVA_PID" ] || return 1
    kill -0 $JAVA_PID || return 1
    echo $JAVA_PID > $PID_FILE
}



###########################################################
### do the init

RETVAL=0

case "$1" in
  start)
	log_daemon_msg "Starting $NAME"
	start_selenium
	RETVAL=$?
	;;
  stop)
	pidofproc -p $PID_FILE $JAVA_BIN >/dev/null
	status=$?
	if [ $status -eq 0 ]; then
		PID=$( cat $PID_FILE )
		log_daemon_msg "Stopping $NAME (pid $PID)"
		killproc -p $PID_FILE $JAVA_BIN && rm -f $PID_FILE
	else
		log_warning_msg "$NAME is not currently running"
		exit 0
	fi
	RETVAL=$?
	;;
  restart|force-reload)
	pidofproc -p $PID_FILE $JAVA_BIN >/dev/null
	if [ $? -eq 0 ]; then
		PID=$( cat $PID_FILE )
		log_daemon_msg "Restarting $NAME (pid $PID)"
		killproc -p $PID_FILE $JAVA_BIN && rm -f $PID_FILE
		if [ $? -eq 0 ]; then
			start_selenium
		fi
	else
		log_daemon_msg "Starting $NAME"
		start_selenium
	fi
	RETVAL=$?
	;;
  status)
	pidofproc -p $PID_FILE $JAVA_BIN >/dev/null
	status=$?
	if [ $status -eq 0 ]; then
		PID=$( cat $PID_FILE )
		log_success_msg "$NAME is running (pid $PID)"
	else
		log_success_msg "$NAME is not running"
	fi
	exit $status
	;;
  *)
	echo "Usage: $0 {start|stop|restart|force-reload|status}"
	exit 1
	;;
esac

### report sucess or failure
if [ $RETVAL -eq 0 ]; then
	log_success_msg "SUCCESS"
else
	log_failure_msg "FAIL"
fi

exit $RETVAL

END_TXT

chmod +x /etc/init.d/selenium

# done!
cat <<END_TXT

You should now be able to launch the Selenium server as a daemon
with the following command:

 /etc/init.d/selenium start

Or manually like so:

 xvfb-run --auto-servernum java -jar /opt/selenium-server-1.0.1/selenium-server.jar

If you do not have a browser like firefox or iceweasel installed,
do that first. Selenium should select the browser automatically.

There are lots of options that can be twiddled in this file:

 /etc/default/selenium

Enjoy, and please, send bug reports, feature requests, and patches via github:

 http://github.com/Hercynium/debian-selenium-installer

  -- stephen@scaffidi.net

END_TXT

