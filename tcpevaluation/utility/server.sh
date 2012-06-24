#! /bin/sh -e

# Tune TCP parameters, start iperf server and set up dummynet/netem


### init

# check
[ -f ./commons -a -f ./tcp.sh -a -f ./dummynet.sh -a -f ./tc.sh ] || {
    echo "$0 is executed from the wrong path or a script is missing!" >&2
    exit 255
}

# import
. ./commons


### constants

# ipfw module
readonly IPFW_MODULE='ipfw_mod'
readonly IPFW_FILE="${IPFW_MODULE}${MODULE_SUFFIX}"
# iperf server
readonly IPERF_CMD='iperf'
readonly IPERF_ARGS='-s -p' # followed by the port


### functions

# show usage
help () {
    show_usage '{ dummynet | netem }  -b BANDWIDTH_kbit/s [ -d DELAY_ms ] [ -l LOSS_probability ] [ -q QUEUE ]'
    exit 253
}

# return true iff iperf is running
iperf_is_running () {
    pidof "$IPERF_CMD" > /dev/null
}

# start iperf server in background
start_iperf () {
    local counter=0
    # check binary
    which "$IPERF_CMD" > /dev/null ||
        E_FATAL "$IPERF_CMD command not found!"
    # start iperf server
    nohup "$IPERF_CMD" $IPERF_ARGS "$IPERF_PORT" > /dev/null 2>&1 &
    # wait
    while ! iperf_is_running; do
        if [ $((++counter)) -ge 10 ]; then
            E_FATAL "Unable to start $IPERF_CMD!"
        fi
        sleep 0.5
    done
}


### main

# tune TCP parameters
sudo ./tcp.sh init > /dev/null || E_FATAL "TCP tuning FAILED with exit status ${?}!"

# start iperf server in background
if ! iperf_is_running; then
    E_WARNQ "Starting ${IPERF_CMD}... "
    start_iperf
    E_WARN 'done'
fi

# set up dummynet / netem
if [ "$1" = 'dummynet' ]; then
    # load ipfw module
    if ! is_loaded "$IPFW_MODULE"; then
        E_WARNQ "Loading ${IPFW_MODULE}... "
        load_module "$IPFW_FILE"
        E_WARN 'done'
    fi
    # set up dummynet
    shift
    sudo ./dummynet.sh "$@"
elif [ "$1" = 'netem' ]; then
    # set up netem
    shift
    sudo ./tc.sh "$@"
else
    # error
    help
fi
