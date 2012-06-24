#! /bin/sh -e

# Set up dummynet

## URLs
# http://info.iet.unipi.it/~luigi/ip_dummynet/original.html
# http://info.iet.unipi.it/~luigi/dummynet/


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


## default
DELAY=""
LOSS=""
DUPLICATE=""
CORRUPT=""
REORDENING=""
INTF="eth0"
BANDW=""
QUEUE=""
IPFW="ipfw -q"

# show usage
help(){
    show_usage '-b BANDWIDTH_kbit/s [ -d DELAY ] [ -l LOSS_float ] [ -q QUEUE ]'
    exit 253
}

# flush dummynet
flush(){
    # max mtu
    ifconfig $INTF mtu 1500 || true # ignore errors
    # remove dummynet rules and make new pipes
    $IPFW -f flush &&
    $IPFW add pipe 1 ip from any to any out &&
    $IPFW add pipe 2 ip from any to any in ||
        E_FATAL "unable to reset dummynet"
}

# show dummynet entries
show(){
    $IPFW list
    $IPFW pipe list
    $IPFW queue list
}

## get options
while getopts ":d:l:u:c:q:r:i:c:b:fhsn" option; do
    case $option in
        d)
	# Delay: delay NN ms
	# Sets the propagation delay of the pipe, in milliseconds. Note that the queueing delay
	# component is independent of the propagation delay. Also note that all delays are
	# approximated with a granularity of 1/HZ seconds (HZ is typically 100, but we
	# suggest using HZ=1000 and maybe even larger values). 
	if [ $OPTARG -gt 0 ] || [ $DELAY != "" ]; then DELAY="delay ${OPTARG}"; 
           else  E_ERR "select delay > 0"; exit; fi
        ;;
#        ds) ## possbile distribution: normal, pareto, paretonormal
#            if [ $OPTARG -gt 0 ] || [ $DELAY != "" ]; then DELAY="delay ${OPTARG}ms distribution normal";
#            else  E_ERR "select delay > 0"; exit; fi
#        ;;
        l)
	# Random Packet Loss: plr X
	# X is a floating point number between 0 and 1 which causes packets to be
	# dropped at random. This is done generally to simulate lossy links.
	# The default is 0, or no loss. 
        LOSS="plr ${OPTARG}";
        ;;
#        u) ## duplicate
#           if [ $OPTARG -gt 0 ]; then DUPLICATE="duplicate ${OPTARG}%";
#           else E_ERR "select duplicate > 0"; exit; fi
#        ;;
#        c) ## corrupt
#        if [ $OPTARG -gt 0  ]; then CORRUPT="corrupt {OPTARG}%";
#           else E_ERR "select corrupt > 0"; exit; fi
#        ;;
#        r) ## re-ordening
#           if [ $OPTARG -gt 0  ] && [ $DELAY !="" ]; then REORDENING="reorder ${OPTARG}% 50%";
#           else E_ERR "select re-ordening > 0 or define delay first"; exit; fi
#        ;;
        i) if [ -n "$OPTARG" ]; then INTF=${OPTARG};
           else E_ERR "select an interface"; exit; fi
        ;;
        f) ## flush
           flush
           exit 0
        ;;
        b) if [ $OPTARG -gt 0  ]; then BANDW="bw ${OPTARG}Kbit/s"
           else E_ERR "select bandwidth > 0 (kbps/s)"; exit; fi
        ;;
	q) if [ $OPTARG -gt 0  ]; then QUEUE="queue ${OPTARG}"
	   else E_ERR "select queue > 0"; exit; fi
	;;
        h) help
        ;;
        s) show
           exit 0
        ;;
        n) no_exec=X
        ;;
    esac
done
[ -n "$BANDW" ] ||
    E_FATAL 'bandwidth argument is mandatory!'

# NO EXEC flag
if [ -n "$no_exec" ]; then
    exit 0 # exit
fi

# delete all rules
E_INFOQ "flushing ipfw... "
flush

# configure
E_INFOQ "setting $BANDW $QUEUE $DELAY $LOSS... "
$IPFW pipe 1 config $BANDW $QUEUE $DELAY $LOSS &&
$IPFW pipe 2 config $BANDW $QUEUE $DELAY $LOSS ||
    E_FATAL "unable to configure dummynet (params: $BANDW $QUEUE $DELAY $LOSS)"
E_INFO 'done'

#E_INFO "tc qdisc add dev $INTF root netem $DELAY $LOSS $DUPLICATE $CORRUPT $REORDENING"
#tc qdisc add dev $INTF root handle 1: netem $DELAY $LOSS $DUPLICATE $CORRUPT $REORDENING
#if [ -n "$BANDW" ]; then
#        E_INFO "tc class add dev eth0 parent 10: classid 0:1 htb rate ${BANDW}kbit ceil ${BANDW}kbit"
#        tc qdisc add dev $INTF parent 1:1 handle 10: htb default 1 r2q 10 
#        tc class add dev $INTF parent 10: classid 0:1 htb rate ${BANDW}kbit ceil ${BANDW}kbit
        ## valid only for BANDW=10mbit
#        tc qdisc add dev $INTF parent 1:1 handle 10: htb rate ${BANDW}kbit burst 10kb latency 1.2ms minburst 1540
#	tc qdisc add dev eth0 root handle 1: htb default 1
#	tc class add dev eth0 parent 1: classid 1:1 htb rate ${BANDW}kbps ceil ${BANDW}kbps 
#fi
