#!/bin/sh


## URLs
# http://www.linuxfoundation.org/collaborate/workgroups/networking/netem
# http://netgroup.uniroma2.it/twiki/bin/view.cgi/Main/NetemCLG
# http://lists.linux-foundation.org/pipermail/netem/2007-September/001156.html
# http://linuxgazette.net/135/pfeiffer.html


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

help(){
    E_INFO "------- help -------"
    E_INFO "$0 -d 100 ..."
    exit 0
}

flush(){
    tc qdisc del dev $INTF root
}

show(){
    tc qdisc show
}

network(){
    E_INFO "set network parameters"
    #ifconfig $INTF 192.168.88.200/24
    ifconfig $INTF mtu 1500
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo 0 > /proc/sys/net/ipv4/conf/default/send_redirects
    echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
    echo 1 > /proc/sys/net/ipv4/ip_no_pmtu_disc
    echo 0 > /proc/sys/net/ipv4/conf/${INTF}/send_redirects
}

## get options
while getopts ":d:l:u:c:r:i:b:fhsn" option; do
    case $option in
        d) if [ $OPTARG -gt 0 ] || [ $DELAY != "" ]; then DELAY="delay ${OPTARG}ms"; 
           else  E_ERR "select delay > 0"; exit; fi
        ;;
        ds) ## possbile distribution: normal, pareto, paretonormal
            if [ $OPTARG -gt 0 ] || [ $DELAY != "" ]; then DELAY="delay ${OPTARG}ms distribution normal";
            else  E_ERR "select delay > 0"; exit; fi
        ;;
        l) ## loss
           # When loss is used locally (not on a bridge or router), the loss
           # is reported to the upper level protocols. This may cause TCP to resend
           # and behave as if there was no loss. When testing protocol reponse to
           # loss it is best to use a netem on a bridge or router 
           ## created from crandom() from 
           #  http://lists.linux-foundation.org/pipermail/netem/2007-September/001156.html
           # Y=my_random [0,1]
           # If Y<=p
           #   Then X = true
           # Else X = false
           ## ^^^ don't run well with correlation
           # http://netgroup.uniroma2.it/twiki/bin/view.cgi/Main/NetemCLG
           if [ $OPTARG -gt 0 ]; then LOSS="loss ${OPTARG}%";
           else E_ERR "select loss > 0"; exit; fi
        ;;
        u) ## duplicate
           if [ $OPTARG -gt 0 ]; then DUPLICATE="duplicate ${OPTARG}%";
           else E_ERR "select duplicate > 0"; exit; fi
        ;;
        c) ## corrupt
           if [ $OPTARG -gt 0  ]; then CORRUPT="corrupt {OPTARG}%";
           else E_ERR "select corrupt > 0"; exit; fi
        ;;
        r) ## re-ordening
           if [ $OPTARG -gt 0  ] && [ $DELAY !="" ]; then REORDENING="reorder ${OPTARG}% 50%";
           else E_ERR "select re-ordening > 0 or define delay first"; exit; fi
        ;;
        i) if [ -n "$OPTARG" ]; then INTF=${OPTARG};
           else E_ERR "select an interface"; exit; fi
        ;;
        f) ## flush
           flush
           exit 0
        ;;
        b) if [ $OPTARG -gt 0  ]; then BANDW=${OPTARG}
           else E_ERR "select bandwidth > 0 (kbps/s)"; exit; fi
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


if [ "$DELAY" != "" ] && [ "$LOSS" != "" ] && [ "$DUPLICATE" != "" ] && \
   [ "$CORRUPT" != "" ] && [ "$REORDENING" != "" ] && [ "$BANDW" != "" ]; then
        help
fi

# NO EXEC flag
if [ -n "$no_exec" ]; then
    exit 0 # exit
fi

## delete all rules
flush
network

E_INFO "tc qdisc add dev $INTF root netem $DELAY $LOSS $DUPLICATE $CORRUPT $REORDENING"
#tc qdisc add dev $INTF root handle 1: netem $DELAY $LOSS $DUPLICATE $CORRUPT $REORDENING
if [ -n "$BANDW" ]; then
        E_INFO "tc class add dev eth0 parent 10: classid 0:1 htb rate ${BANDW}kbit ceil ${BANDW}kbit"
#        tc qdisc add dev $INTF parent 1:1 handle 10: htb default 1 r2q 10 
#        tc class add dev $INTF parent 10: classid 0:1 htb rate ${BANDW}kbit ceil ${BANDW}kbit
        ## valid only for BANDW=10mbit
#        tc qdisc add dev $INTF parent 1:1 handle 10: htb rate ${BANDW}kbit burst 10kb latency 1.2ms minburst 1540
	tc qdisc add dev eth0 root handle 1: htb default 1
	tc class add dev eth0 parent 1: classid 1:1 htb rate ${BANDW}kbps ceil ${BANDW}kbps 
fi
