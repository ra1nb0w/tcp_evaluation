#! /bin/sh -e

# Tune TCP parameters, start iperf client and capture TCP stack status


### init

# check
[ -f ./commons -a -f ./tcp.sh ] || {
    echo "$0 is executed from the wrong path or a script is missing!" >&2
    exit 255
}

# import
. ./commons


### constants

# iperf client
readonly IPERF_CMD='iperf'
readonly IPERF_ARGS='-f k -p' # followed by the port
# temporary output
readonly TMPDIR="/tmp/.${0##*/}_$$"
readonly IPERF_LOG_FILENAME="$IPERF_CMD"
readonly IPERF_LOG="$TMPDIR/$IPERF_LOG_FILENAME"
readonly IPERF_TMPFILE="$TMPDIR/.${IPERF_CMD}.tmp"
readonly TCP_LOG_FILENAME='tcp_probe.out'
readonly TCP_LOG="$TMPDIR/$TCP_LOG_FILENAME"
# output
readonly REPORTDIR="${REPORTDIR:-output}"
readonly GALLERYDIR="$REPORTDIR/gallery"


### variables (with default values)

folder='test'
time=30
interval=1
parallel=1
window=""
congestion=""
# with options (-w, -Z)
window_opt=""
congestion_opt=""


### functions

# show usage
help () {
    show_usage '-h HOST [ -t TIME ] [ -i INTERVAL ] [ -w WINDOW ] [ -Z CONGESTION_ALGORITHM ] [ -P PARALLEL ]'
    exit 253
}

# start capture of TCP stack status running a process in background
start_capture () {
    local module_log
    # load TCP module 
    module_log="$(sudo ./tcp.sh start)" || exit $? # errors printed by tcp.sh
    # start capture TCP stack status in background
    cat "$module_log" > "$TCP_LOG" &
}

# stop background process and unload TCP module
stop_capture () {
    local process="$1"
    # stop background process
    kill_pid "$process"
    # unload TCP module
    sudo ./tcp.sh stop || exit $? # errors printed by tcp.sh
}

# start iperf client and capture TCP stack status
run_iperf () {
    local pid
    # load tcp module and start capture
    start_capture
    # pid of the background process
    pid=$!
    # check binary
    which "$IPERF_CMD" > /dev/null ||
        E_FATAL "$IPERF_CMD command not found!"
    # run iperf client
    E_INFO "$IPERF_CMD $IPERF_ARGS $IPERF_PORT -c $host -t $time -i $interval $congestion_opt -P $parallel $window_opt"
    echo "$IPERF_CMD $IPERF_ARGS $IPERF_PORT -c $host -t $time -i $interval $congestion_opt -P $parallel $window_opt" > "$IPERF_LOG"
    $IPERF_CMD $IPERF_ARGS "$IPERF_PORT" -c "$host" -t "$time" -i "$interval" $congestion_opt -P "$parallel" $window_opt >> "$IPERF_LOG"
    # stop capture (killing $pid) and unload tcp module
    stop_capture "$pid"
}

# write to file the congestion window and slow start treshold graph
cwndGraph () {
    local input="$1"
    local output="$2"
    local meanw
    local meant
    # get mean values
    meanw="$(awk '{
                    sum+=$7; 
                    ++n; 
                  } 

                  END {
                    CONVFMT = "%2.0f";
                    print sum/n ""
                  }
        ' "$input")" &&
    meanw="$(print_numeric "$meanw")" &&
    meant="$(awk '{
                    sum+=($8>=2147483647 ? 0 : $8);
                    ($8>=2147483647 ? n : ++n);
                  }
                  
                  END {
                    CONVFMT = "%2.0f";
                    print sum/n ""
                  }
        ' "$input")" &&
    meant="$(print_numeric "$meant")" &&
    # plot the graph
    gnuplot -persist <<-_EOF > /dev/null || true # ignore errors
        set style data lines
        set title "$input"
        set xlabel "time (seconds)"
        set ylabel "Segments (cwnd, ssthresh)"
        set terminal png xffffff x000000 size 1024x768
        set output "$output"
        set label "Mean cwnd = ". $meanw at graph 0.70,0.97
        set label "Mean ssthresh = ". $meant at graph 0.53,0.97
        plot "$input" using 1:7 title "snd_cwnd", \\
        "$input" using 1:(\$8>=2147483647 ? 0 : \$8) title "snd_ssthresh"
_EOF
}

# write to file the speed graph
speedGraph () {
    local input="$1"
    local output="$2"
    local mean
    local max
    local min
    # make temporary file
    awk 'FNR>7' < "$input" | awk -F 'KBytes' '{ print $2 }' | awk '{ print $1 }' > "$IPERF_TMPFILE" &&
    # get values
    mean="$(awk '{ sum+=$1; ++n; } END { CONVFMT = "%2.0f"; print sum/n "" }' "$IPERF_TMPFILE")" &&
    mean="$(print_numeric "$mean")" &&
    min="$(sort -n -- "$IPERF_TMPFILE" | head -1)" &&
    min="$(print_numeric "$min")" &&
    max="$(sort -rn -- "$IPERF_TMPFILE" | head -1)" &&
    max="$(print_numeric "$max")" &&
    # plot the graph
    gnuplot -persist <<-_EOF > /dev/null || true # ignore errors
        set style data lines
        set title "$input"
        set xlabel "time (seconds)"
        set ylabel "speed (kbits/sec)"
        set terminal png xffffff x000000 size 1024x768
        set output "$output"
        set label "Mean = ". $mean at graph 0.88,0.82
        set label "Max = ". $max at graph 0.88,0.86
        set label "Min = ". $min at graph 0.88,0.90
        plot "$IPERF_TMPFILE" using 1 title "speed"
_EOF
    # remove temporary file
    rm -- "$IPERF_TMPFILE" 2> /dev/null || true # exit status is always true
}


### menu

# get options
sack=1
dsack=1
while getopts ':h:t:i:w:Z:P:F:sSznX' option; do
    case "$option" in
        F)  if [ "$OPTARG" ]; then
                folder="$OPTARG"
            else
                E_FATAL 'the folder name can not be empty!'
            fi
            ;;
        h)  if is_IPv4 "$OPTARG"; then
                host="$OPTARG"
            else
                E_FATAL 'check the IPv4 correctness for the host!'
            fi
            ;;
        t)  if is_int_gt0 "$OPTARG"; then
                time="$OPTARG"
            else
                E_FATAL 'select time > 0!'
            fi
            ;;
        i)  if is_int_gt0 "$OPTARG"; then
                interval="$OPTARG"
            else
                E_FATAL 'select interval > 0!'
            fi
            ;;
        w)  if is_int_gt0 "${OPTARG%K}" || is_int_gt0 "${OPTARG%M}"; then
                window="$OPTARG"
                window_opt="-w $window";
            else
                E_FATAL 'select a correct value for the window (VALUE[KM])!'
            fi
            ;;
        Z)  if is_congestion_algorithm_supported "$OPTARG"; then
                congestion="$OPTARG"
                congestion_opt="-Z $congestion"
            else
                E_FATAL 'select an available or loadable TCP congestion algorithm!'
            fi
            ;;
        s)  sack=1
            dsack=0
            ;;
        S)  sack=1
            dsack=1
            ;;
        z)  sack=0
            dsack=0
            ;;
        P)  if is_int_gt0 "$OPTARG"; then
                parallel="$OPTARG"
            else
                E_FATAL 'select a parallel value > 0!'
            fi
            ;;
        
        n)  no_exec=X
	    skip_check=
            ;;
        X)  no_exec=
	    skip_check=X
	    ;;
        *)  # error
            help
    esac
done
shift $((OPTIND - 1))

# check arguments
[ -n "$host" ] ||
    E_FATAL 'host argument is required!'
[ $((time % interval)) -eq 0 ] ||
    E_FATAL 'the time must be a multiple of the interval!'

if [ -z "$skip_check" ]; then
    # load TCP congestion algorithm, if needed
    if [ -n "$congestion" ]; then
        sudo ./tcp.sh tcp_algo "$congestion" || exit $?
    fi
    # tune TCP parameters
    sudo ./tcp.sh init "$sack" "$dsack" || exit $?
fi

# NO EXEC flag
if [ -n "$no_exec" ]; then
    exit 0 # exit
fi


### main

# make directories (if they do not exist)
make_dir "$TMPDIR"
make_dir "$REPORTDIR"
make_dir "$GALLERYDIR"
folder="$(print_available_file "$REPORTDIR/$folder")" # find an available filename
make_dir "$folder"

# run the test
run_iperf

# move files to destination
mv -- "$TCP_LOG" "$IPERF_LOG" "$folder"

# plot graphs
E_INFOQ "cwnd graph... "
cwndGraph "$folder/$TCP_LOG_FILENAME" "$folder/cwnd.png"
E_INFOQ "speed graph... "
speedGraph "$folder/$IPERF_LOG_FILENAME" "$folder/speed.png"

# clean
rmdir -- "$TMPDIR" || true # ignore errors

# copy graphs in the gallery
foldername="${folder##*/}"
cp -- "$folder/cwnd.png" "$GALLERYDIR/cwnd_${foldername}.png" &&
cp -- "$folder/speed.png" "$GALLERYDIR/speed_${foldername}.png" || {
    E_ERR "hard link to graphs in the gallery failed with exit status ${?}!"
    true # ignore errors
}

# end
E_INFO "output written in $foldername"
