#! /bin/sh -e

# This script is just a stub to configure the network quickly (client and server side)


### variables

IFACE="${IFACE:-eth0}"
SERVER="${SERVER:-192.168.1.1}"
CLIENT="${CLIENT:-192.168.1.2}"
SSH_USER="$(id -u -n)"


### init

# check
cd tcpevaluation &&
[ -f ./utility/commons -a -f ./tcpeval.sh ] || {
    echo "$0 is executed from the wrong path or a script is missing!" >&2
    exit 255
}

# import
. ./utility/commons


### functions

# kill a running daemon
stop_daemon () {
    local deamon="/etc/init.d/$1"
    if [ -f "$daemon" ]; then
        sudo "$daemon" stop || true # ignore errors
    fi
}


### main

# arguments
[ $# -eq 0 ] || E_FATAL 'No argument required!'

# stop network daemons
stop_daemon network-manager
stop_daemon wicd

# reset
E_INFO "Reset $IFACE..."
sudo ifconfig "$IFACE" 1.1.1.1 &&
sudo ifconfig "$IFACE" down &&
sleep 1 || true # ignore errors

# set up
if confirm 'Server (only for the first host)'; then
    # server
    E_INFOQ "Setting up $IFACE... "
    sudo ifconfig "$IFACE" "$SERVER" up &&
    is_connected "$SERVER" ||
        E_FATAL "unable to turn up the interface $IFACE!"
    E_INFO 'done'
    # ssh daemon
    sudo which sshd > /dev/null ||
        E_FATAL 'ssh daemon not found!'
    pidof sshd > /dev/null ||
        E_FATAL 'ssh daemon must be in execution!'
else
    # client
    E_INFOQ "Setting up $IFACE... "
    sudo ifconfig "$IFACE" "$CLIENT" up &&
    is_connected "$CLIENT" ||
        E_FATAL "unable to turn up the interface $IFACE!"
    E_INFO 'done'
    # connection
    confirm 'Is the server running' ||
        E_FATAL 'try again when the server is running (execute ./config.sh on the server)!'
    E_INFOQ 'Checking connection... '
    is_connected "$SERVER" ||
        E_FATAL "unable to connect to $SERVER!"
    E_INFO 'done'
    # ssh client
    which ssh > /dev/null ||
        E_FATAL 'ssh client not found!'
    # RSA key
    if [ ! -f ~/.ssh/id_rsa ]; then
        if confirm 'Generate a RSA (v2) key for ssh connection'; then
            ssh-keygen -t rsa -b 2048 -N "" -f ~/.ssh/id_rsa -q ||
                E_FATAL "creation failed with exit status $?"
            E_INFOQ "RSA key generated successfully. Install the key to $SERVER... "
            ssh-copy-id "${SSH_USER}@${SERVER}" > /dev/null ||
                E_FATAL "Installing failed! Copy *manually* the public key ~/.ssh/id_rsa.pub into the file ~/.ssh/authorized_keys on $SERVER!"
            E_INFO 'done'
        fi
    fi
    # ssh connection
    E_INFOQ 'Checking ssh connection... '
    ssh "${SSH_USER}@${SERVER}" true ||
        E_FATAL "ssh connection to $SERVER with user $SSH_USER failed!"
    E_INFO 'done'
fi


### end

E_INFO 'Done'
