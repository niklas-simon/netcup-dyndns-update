#!/bin/bash

trap "exit 1" TERM
TOP_PID=$$
exec 3>&1

normal="\033[0m"
red="\033[0;91m"
green="\033[0;92m"
yellow="\033[0;93m"
blue="\033[0;96m"

# Gibt Logmeldungen aus
log() {
    # $1: (i|w|e|s) Log-Level (Farbe)
    # $2: Logmeldung

    file=/dev/stdout

    case $1 in
        i|info)
            if [[ $LOG_LEVEL -gt 1 ]]; then
                return 0
            fi
            color="$blue"
            ;;
        w|warn)
            if [[ $LOG_LEVEL -gt 2 ]]; then
                return 0
            fi
            color="$yellow"
            ;;
        e|error)
            if [[ $LOG_LEVEL -gt 3 ]]; then
                return 0
            fi
            color="$red"
            file=/dev/stderr
            ;;
        s|success)
            if [[ $LOG_LEVEL -gt 1 ]]; then
                return 0
            fi
            color="$green"
            ;;
        d|debug)
            if [[ $LOG_LEVEL -gt 0 ]]; then
                return 0
            fi
            color="$normal"
            ;;
        *)
            if [[ $LOG_LEVEL -gt 1 ]]; then
                return 0
            fi
            color="$normal"
            ;;
    esac
        
    echo -e "$color$2$normal" 1>&3
}

# jq wrapper with error handling
hjq() {
    res=$(jq "$@")

    if [[ $? -ne 0 ]]; then
        log e "error executing command ${normal}jq $*"
        kill -s TERM $TOP_PID
    fi

    echo "$res"
}

# params: res
handle_error() {
    res="$1"

    status=$(echo "$res" | hjq -r ".status")
    
    shortmsg=$(echo "$res" | hjq -r ".shortmessage")

    longmsg=$(echo "$res" | hjq -r ".longmessage")
    if [[ "$longmsg" == "null" ]]; then
        longmsg=""
    fi

    if [[ "$status" != "success" ]]; then
        log e "$status: $shortmsg $longmsg"
        kill -s TERM $TOP_PID
    fi
}

send_request() {
    data=$1
    dry=$2

    log d "sending request:\n$(echo "$data" | hjq)"

    if [[ $dry -eq 1 ]]; then
        return 0;
    fi

    res=$(curl -s --location --request DELETE 'https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON' \
        --header 'Content-Type: application/json' \
        --data "$data")

    log d "got response:\n$(echo "$res" | hjq)"
    
    handle_error "$res"

    echo "$res"
}

login() {
    LOGIN_PAYLOAD=$(echo "{\
        \"action\": \"login\",\
        \"param\": {\
            \"customernumber\": \"${CUSTOMER_NUMBER}\",\
            \"apikey\": \"${API_KEY}\",\
            \"apipassword\": \"${API_PASSWORD}\"\
        }\
    }" | hjq -c)

    res=$(send_request "$LOGIN_PAYLOAD")
    
    echo "$res" | hjq -r '.responsedata.apisessionid'
}

# params: sid domain
get_records() {
    sid=$1
    domain=$2

    INFO_PAYLOAD=$(echo "{\
        \"action\": \"infoDnsRecords\",\
        \"param\": {\
            \"customernumber\": \"${CUSTOMER_NUMBER}\",\
            \"apikey\": \"${API_KEY}\",\
            \"apisessionid\": \"${sid}\",\
            \"domainname\": \"${domain}\"\
        }\
    }" | hjq -c)

    res=$(send_request "$INFO_PAYLOAD")

    echo "$res" | hjq '.responsedata.dnsrecords'
}

# params: sid domain records
set_records() {
    sid=$1
    domain=$2
    records=$3

    UPDATE_PAYLOAD=$(echo "{\
        \"action\": \"updateDnsRecords\",\
        \"param\": {\
            \"customernumber\": \"${CUSTOMER_NUMBER}\",\
            \"apikey\": \"${API_KEY}\",\
            \"apisessionid\": \"${sid}\",\
            \"domainname\": \"${domain}\",\
            \"dnsrecordset\": {\
                \"dnsrecords\": ${records}\
            }\
        }\
    }" | hjq -c)

    res=$(send_request "$UPDATE_PAYLOAD" $DRY_RUN)
}

# params: sid
logout() {
    sid=$1

    LOGOUT_PAYLOAD=$(echo "{\
        \"action\": \"logout\",\
        \"param\": {\
            \"customernumber\": \"${CUSTOMER_NUMBER}\",\
            \"apikey\": \"${API_KEY}\",\
            \"apisessionid\": \"${sid}\"\
        }\
    }" | hjq -c)

    res=$(send_request "$LOGOUT_PAYLOAD")
}

run() {
    log i "starting"
    log i "logging in"
    sid=$(login)
    log s "sid: $normal$sid"

    log i "parsing domains"
    IFS=',' read -ra domains <<< "$DOMAINS"

    log i "getting public IP"
    ip=$(curl -s ipinfo.io/ip)
    log s "public IP: $normal$ip"

    for domain in "${domains[@]}"; do
        log i "processing domain $normal$domain"
        
        log i "getting dns records"
        records=$(get_records $sid $domain)
        length=$(echo "$records" | hjq ". | length")
        log s "found $normal$length$blue records"

        change="false"

        for ((i=0; i<length; i++)); do
            log i "processing record $normal$i"

            type=$(echo "$records" | hjq -r ".[$i].type")
            if [[ "$type" != "A" ]]; then
                log i "not an A record"
                continue
            fi

            hostname=$(echo "$records" | hjq -r ".[$i].hostname")
            regex="(^|,)$hostname(,|$)"
            if [[ ! "$RECORDS" =~ $regex ]]; then
                log i "$normal$hostname$blue not in RECORDS"
                continue
            fi

            destination=$(echo "$records" | hjq -r ".[$i].destination")
            if [[ "$destination" == "$ip" ]]; then
                log i "ip address unchanged"
                continue
            fi

            change="true"
            log i "changing destination of $normal$hostname$blue to $normal$ip"
            records=$(echo "$records" | hjq -r ".[$i].destination|=\"$ip\"")
        done

        if [[ $DRY_RUN -eq 1 && $change != "true" ]]; then
            log d "dry running, therefor simulating a change"
            change="true"
        fi

        if [[ "$change" != "true" ]]; then
            log i "no changes were made on domain $normal$domain"
            continue
        fi

        log i "updating records for domain $normal$domain"
        set_records $sid $domain "$(echo "$records" | hjq -c)"
    done

    log i "logging out"
    logout $sid

    log s "done"
}

if [[ -z "$API_KEY" ]]; then
    log e "environment variable API_KEY is required"
    kill -s TERM $TOP_PID
fi

if [[ -z "$API_PASSWORD" ]]; then
    log e "environment variable API_PASSWORD is required"
    kill -s TERM $TOP_PID
fi

if [[ -z "$CUSTOMER_NUMBER" ]]; then
    log e "environment variable CUSTOMER_NUMBER is required"
    kill -s TERM $TOP_PID
fi

if [[ -z "$DOMAINS" ]]; then
    log e "environment variable DOMAINS is required"
    kill -s TERM $TOP_PID
fi

while true; do
    run
    for ((i=0; i<INTERVAL; i++)); do
        sleep 1
    done
done