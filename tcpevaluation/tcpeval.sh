#! /bin/sh -e

# Set up client and server, and start the benchmark of the TCP flow between them, monitoring the TCP stack status

# Tools required:
# - both sides: this framework (in ~/tcp_stack), iperf and sudo, configured to allow commands execution without asking anything
# - client side: tcp_probe module (compiled from source, in case of errors), ssh client and gnuplot
# - server side: ipfw (for dummynet) or netem, and ssh daemon, configured to accept connections without asking anything


### init

# check
cd utility &&
[ -f ./commons -a -f ../gui -a -f ./client.sh ] || {
    echo "$0 is executed from the wrong path or a script is missing!" >&2
    exit 255
}

# import
. ./commons


### constants

readonly SSH='ssh'
readonly SSH_ARGS=""
readonly SSH_PATH_SUFFIX='tcpevaluation/utility'


### variables

export REPORTDIR='../output'
#host - IP of the other host (server)
#user - user used on server side for the ssh connection
#path - path of framework directory on server side for the ssh connection


### functions

# show usage
help () {
    show_usage '(without arguments for interactive mode)\n'
    show_usage '-h HOST -b BANDWIDTH_kbit/s  (with mandatory arguments only)\n'
    show_usage '[ -c ITERATIONS ]  -h HOST  [ -u SSH_USER ]  [ -p PATH ]  [ -D | -N ]  CLIENT_OPTIONS  SERVER_OPTIONS\nwhere:\n HOST is the IPv4 of the server\n SSH_USER is the user for the ssh connection to HOST (default: current user)\n PATH is the location of framework directory on server side (default: local path)\n -D stays for dummynet (default) and -N for netem\n CLIENT_OPTIONS := [ -t TIME ] [ -i INTERVAL ] [ -w WINDOW ] [ -Z CONGESTION_ALGORITHM ] [ -P PARALLEL_CONNECTION ] [ -S | -s | -z ]\n  -S -> sack=1,dsack=1 (default)\n  -s -> sack=1,dsack=0\n  -z -> sack=0,dsack=0\n SERVER_OPTIONS := -b BANDWIDTH_kbit/s [ -d DELAY_ms ] [ -l LOSS_probability ] [ -q QUEUE ]'
    exit 253
}

# check ssh connection
check_ssh () {
    # check connection
    E_INFOQ 'Checking connection... '
    is_connected "$host" ||
        E_FATAL "ping to $host failed!"
    # check ssh connection
    E_INFOQ 'ssh connection... '
    $SSH $SSH_ARGS "$user@$host" -- cd \~ \&\& cd "$path" ||
        E_FATAL "ssh connection to $host with user \"$user\" and path \"$path\" failed!"
    # done
    E_INFO 'done'
}

# prepare benchmark tools (server side)
server () {
    # (Note: $path can be absolute or incomplete, starting from a directory in the home of $user on $host)
    $SSH $SSH_ARGS "$user@$host" -- cd \~ \&\& cd "$path" \&\& \
        ./server.sh $net_emu $delay_opt $bandwidth_opt $loss_opt $queue_opt "$@" \
    || exit $?
}

# run benchmark tools (client side)
client () {
    ./client.sh $host_opt $time_opt $interval_opt $window_opt $congestion_opt $parallel_opt $client_opts "$@" ||
        exit $?
}

# add arguments to options
complete_options () {
    folder_opt="${folder:+-F $folder}"
    host_opt="${host:+-h $host}"
    user_opt="${user:+-u $user}"
    # remove the home directory of the current user in $path (if present) and add $SSH_PATH_SUFFIX
    path="${path#$HOME/}"
    path="${path%$SSH_PATH_SUFFIX}"
    if [ -n "$path" ]; then
        path="${path%/}/"
    fi
    path="${path}${SSH_PATH_SUFFIX}"
    path_opt="${path:+-p $path}"
    iterations_opt="${iterations:+-c $iterations}"
    time_opt="${time:+-t $time}"
    interval_opt="${interval:+-i $interval}"
    window_opt="${window:+-w $window}"
    congestion_opt="${congestion:+-Z $congestion}"
    parallel_opt="${parallel:+-P $parallel}"
    delay_opt="${delay:+-d $delay}"
    bandwidth_opt="${bandwidth:+-b $bandwidth}"
    loss_opt="${loss:+-l $loss}"
    queue_opt="${queue:+-q $queue}"
}


### main

# check ssh command
which "$SSH" > /dev/null ||
    E_FATAL "$SSH command not found!"

# interactive mode
if [ $# -eq 0 ]; then
    . ../gui # end
    # unreachable
    exit 127
fi

# get options
iterations=1
net_emu='dummynet'
client_opts=''
path="$PWD" # default: current path
current_user="$(id -u -n)"
user="$current_user" # default: current user
while getopts ':F:h:u:p:c:t:i:w:Z:P:DNd:b:l:q:sSznX' option; do
    case "$option" in
        F)  folder="$OPTARG"
            ;;
        h)  host="$OPTARG"
            ;;
        u)  user="$OPTARG"
            ;;
        p)  path="$OPTARG"
            ;;
        c)  iterations="$OPTARG"
            ;;
        t)  time="$OPTARG"
            ;;
        i)  interval="$OPTARG"
            ;;
        w)  window="$OPTARG"
            ;;
        Z)  congestion="$OPTARG"
            ;;
        P)  parallel="$OPTARG"
            ;;
        D)  net_emu='dummynet'
            ;;
        N)  net_emu='netem'
            ;;
        d)  delay="$OPTARG"
            ;;
        b)  bandwidth="$OPTARG"
            ;;
        l)  loss="$OPTARG"
            ;;
        q)  queue="$OPTARG"
            ;;
        s)  client_opts='-s'
            ;;
        S)  client_opts='-S'
            ;;
        z)  client_opts='-z'
            ;;
        n)  no_exec=X
	    skip_check=
            ;;
        X)  skip_check=X
            no_exec=
            ;;
        *)  # errors
            help
    esac
done
shift $((OPTIND - 1))
is_int_gt0 "$iterations" ||
    E_FATAL "iterations argument must be > 0!"
# complete client and server options
complete_options
# check client options (do *not* skip this check!)
client $folder_opt -n # no exec


### check

if [ -z "$skip_check" ]; then
    # check ssh connection
    check_ssh
    # check server options
    E_INFOQ 'Checking server options... '
    server -n # no exec
    E_INFO 'done'
fi

# NO EXEC flag
if [ -n "$no_exec" ]; then
    exit 0 # exit
fi


### begin

# set up server side
E_WARN 'Setting up server...'
server

# start tests
E_WARN 'Start iterations...'
for i in $(seq "$iterations"); do
    E_WARNQ "$i/$iterations "
    # benchmark
    client ${folder_opt}.${i} -X
done
