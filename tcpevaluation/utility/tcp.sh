#! /bin/sh -e

# Tune TCP parameters, and load/unload tcp_probe module


### init

# check
[ -f ./commons ] || {
    echo "$0 is executed from the wrong path or a script is missing!" >&2
    exit 255
}

# import
. ./commons

# check root privileges
assert_root


### constants

# TCP probe module
readonly TCPPROBE_MODULE='tcp_probe'
readonly TCPPROBE_FILE="${TCPPROBE_MODULE}${MODULE_SUFFIX}"
readonly TCPPROBE_ARGS='full=1 bufsize=512'
readonly TCPPROBE_LOG='/proc/net/tcpprobe'


### functions

# show usage
help () {
    show_usage '{  init [ sack [ dsack ] ]  |  tcp_algo CONGESTION_ALGORITHM  |  start  |  stop  }'
    exit 253
}

# tune TCP parameters
tcp_tuning () {
    local sack="$1" # 0 or 1 (default: 1)
    local dsack="$2" # 0 or 1 (default: 1)
    # prevent wrong assignments, replacing them with default values
    [ "$sack" = 0 ] || sack=1
    [ "$dsack" = 0 ] || dsack=1

    # turn off the route metrics for repeated connections
    # disable slow start threshold (ssthresh)
    sysctl -q -w 'net.ipv4.tcp_no_metrics_save=1' ||
        E_FATAL "unable to turn off the route metrics save (exit status $?)!"

    # enable sack/dsack functionality
    sysctl -q -w "net.ipv4.tcp_sack=$sack" &&
    sysctl -q -w "net.ipv4.tcp_dsack=$dsack" ||
        E_FATAL "unable to set up sack/dsack (exit status $?)!"

    # end of the function
    return 0


    ##### NOT USED #####


    # If set (1) TCP automatically adjusts the size of the socket receive window based on the amount of space used in the receive queue. Enabled by default.
    # IETF RFC 1323
    ##E_INFO $(sysctl net.ipv4.tcp_moderate_rcvbuf)
    ##sysctl -w net.ipv4.tcp_moderate_rcvbuf=1

    # set max net memory
    #E_INFO $(sysctl net.core.rmem_max)
    #sysctl -w net.core.rmem_max=16777216
    #E_INFO $(sysctl net.core.wmem_max)
    #sysctl -w net.core.wmem_max=16777216

    # set tcp scaling
    ##E_INFO $(sysctl net.ipv4.tcp_window_scaling)
    ##sysctl -w net.ipv4.tcp_window_scaling=1

    # At a minimum increase tcp_rmem[2] for receiver and tcp_wmem[2] for sender to twice the BDP (Bandwidth Delay Product)
    # see Documentation/networking/ip-sysctl.txt
    # default values (vector of 3 INTEGERs: min, default, max)
    # net.ipv4.tcp_rmem = 4096        87380   4194304
    # net.ipv4.tcp_wmem = 4096        16384   4194304
    #E_INFO $(sysctl net.ipv4.tcp_rmem)
    #sysctl -w net.ipv4.tcp_rmem="8192 174760 8388608"
    #E_INFO $(sysctl net.ipv4.tcp_wmem)
    #sysctl -w net.ipv4.tcp_wmem="8192 32768 8388608"

    # tcp_abc - Controls Appropriate Byte Count (ABC) defined in RFC3465. ABC is a way of increasing congestion window (cwnd) more slowly in response to partial acknowledgments.
    #sysctl -w net.ipv4.tcp_abc=0

    # tcp_ecn - Enable Explicit Congestion Notification in TCP. INTEGER
    #sysctl -w net.ipv4.tcp_ecn=2

    # tcp_fack - Enable FACK congestion avoidance and fast retransmission. BOOLEAN
    #sysctl -w net.ipv4.tcp_fack=

    # tcp_max_ssthresh - Limited Slow-Start for TCP with large congestion windows (cwnd) defined in RFC3742. INTEGER
    #sysctl -w net.ipv4.tcp_max_ssthresh=0

    # tcp_tso_win_divisor -  This allows control over what percentage of the congestion window can be consumed by a single TSO frame. INTEGER
    #sysctl -w net.ipv4.tcp_tso_win_divisor=3
}

# load tcp_probe module and print the log filename to standard output
load_tcpprobe () {
    is_loaded "$TCPPROBE_MODULE" ||
        load_module "$TCPPROBE_FILE" $TCPPROBE_ARGS "port=$IPERF_PORT"
    [ -f "$TCPPROBE_LOG" ] || E_FATAL 'Unable to read the TCP flow!'
    chmod 444 -- "$TCPPROBE_LOG"
    echo "$TCPPROBE_LOG"
}

# unload tcp_probe module
unload_tcpprobe () {
    ! is_loaded "$TCPPROBE_MODULE" || rmmod -- "$TCPPROBE_MODULE" ||
        E_ERR "Unable to unload the $TCPPROBE_MODULE module!"
}

# load and enable a given TCP congestion algorithm
load_congestion_algorithm () {
    local algo="$1"
    # load TCP congestion algorithm
    if ! is_congestion_algorithm_available "$algo"; then
	E_WARNQ "loading $algo... "
        load_tcp_module "${algo}"
	sleep 1
    fi
    # enable TCP congestion algorithm
    if ! is_congestion_algorithm_ready "$algo"; then
	E_WARNQ "enabling $algo... "
        cat "$TCP_ALGO_AVAILABLE" > "$TCP_ALGO_ALLOWED" &&
        is_congestion_algorithm_ready "$algo" ||
    	    E_FATAL "enabling of $algo failed!"
    fi
    E_WARN 'done'
}


### main

if [ "$1" = 'init' -a $# -le 3 ]; then
    #"$@" tune TCP parameters
    shift
    tcp_tuning "$@"   
elif [ "$1" = 'tcp_algo' -a $# -eq 2 ]; then
    # load and enable TCP congestion algorithm
    tcp_algo="$2"
    if ! is_congestion_algorithm_ready "$tcp_algo"; then
        load_congestion_algorithm "$tcp_algo"
    fi
elif [ "$*" = 'start' ]; then
    # load tcp_probe module
    load_tcpprobe
elif [ "$*" = 'stop' ]; then
    # unload the module
    unload_tcpprobe
else
    # error
    help
fi
