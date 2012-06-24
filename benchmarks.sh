#! /bin/sh -e

# This script is just a tutorial to try the benchmark


### constants

### mode (comment one of the following lines)
readonly INTERACTIVE_MODE=OFF # disable interactive mode
#readonly INTERACTIVE_MODE=ON # enable interactive mode


### variables for non-interactive mode (change only these variables)

## for connection and ssh connection

export IFACE='eth0'
export SERVER='192.168.1.1'
export CLIENT='192.168.1.2'
SSH_USER="$(id -u -n)" # user for the ssh connection to $SERVER
SSH_PATH="" # empty for the current directory

## other arguments

# single values
TIME=30 # duration of each test (in sec)
ITERATIONS=3 # for each configuration

# more values are allowed
BANDWIDTHS='10240' # in kbit/s
#DELAYS='0 0.001 0.01 0.05'
DELAYS='50' # ms
LOSSES='0 0.001 0.01 0.05'
#LOSSES=0
#QUEES='50 100 200 500 1000'
QUEUES='200'
ALGORITHMS='reno cubic'
#ALGORITHMS='cubic'


### main

# arguments
[ $# -eq 0 ] || E_FATAL 'No arguments required!'

# path
cd tcpevaluation || E_FATAL 'Script executed from the wrong path!'


### interactive mode

if [ "$INTERACTIVE_MODE" = 'ON' ]; then
    exec ./tcpeval.sh
    # unreachable
fi


### non-interactive mode

# use default path if $SSH_PATH is empty
SSH_PATH="${SSH_PATH:-$PWD/utility}"

# check
./tcpeval.sh -h "$SERVER" -u "$SSH_USER" -p "$SSH_PATH" -b 1 -n # no exec

# Example: use dummynet for bottleneck (bandwidth 10 Mbyte/s, delay 100 ms, loss 0.001, queue 200) and iterate 5 times
#./tcpeval.sh -h "$SERVER" -u "$SSH_USER" -p "$SSH_PATH" -D -b 10240 -d 100 -l 0.001 -q 200 -c 5 -F 'tcp_10M_100d_0.001l_200q' -X

# loops
for bandwidth in $BANDWIDTHS; do
  for delay in $DELAYS; do
    for loss in $LOSSES; do
      for queue in $QUEUES; do
        for algo in $ALGORITHMS; do
            echo "\n./tcpeval.sh -h $SERVER -u $SSH_USER -p ${SSH_PATH} -b $bandwidth -t $TIME -D -d $delay -l $loss -q $queue -Z $algo -c $ITERATIONS -F tcp-${algo}_${bandwidth}K_${delay}d_${loss}l_${queue}q"
            ./tcpeval.sh -h "$SERVER" -u "$SSH_USER" -p "$SSH_PATH" -b "$bandwidth" -t "$TIME" -D -d "$delay" -l "$loss" \
              -q "$queue" -Z "$algo" -c "$ITERATIONS" -F "tcp-${algo}_${bandwidth}K_${delay}d_${loss}l_${queue}q" -X
        done
      done
    done
  done
done
             

### end

echo '\nDone'
