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
            color="$blue"
            ;;
        w|warn)
            color="$yellow"
            ;;
        e|error)
            color="$red"
            file=/dev/stderr
            ;;
        s|success)
            color="$green"
            ;;
        *)
            color="$normal"
            ;;
    esac
        
    echo -e "$color$2$normal" 1>&3
}

# params: res
handle_error() {
    res="$1"

    status=$(echo "$res" | jq -r ".status")
    
    shortmsg=$(echo "$res" | jq -r ".shortmessage")

    longmsg=$(echo "$res" | jq -r ".longmessage")
    if [[ "$longmsg" == "null" ]]; then
        longmsg=""
    fi

    if [[ "$status" != "success" ]]; then
        log e "$status: $shortmsg $longmsg"
        kill -s TERM $TOP_PID
    fi
}

login() {
    LOGIN_PAYLOAD=$(echo "{\
        \"action\": \"login\",\
        \"param\": {\
            \"customernumber\": \"${CUSTOMER_NUMBER}\",\
            \"apikey\": \"${API_KEY}\",\
            \"apipassword\": \"${API_PASSWORD}\"\
        }\
    }" | jq -c)

    res=$(curl -s --location --request DELETE 'https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON' \
        --header 'Content-Type: application/json' \
        --data "$LOGIN_PAYLOAD")
    
    handle_error "$res"
    
    echo "$res" | jq -r '.responsedata.apisessionid'
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
    }" | jq -c)

    res=$(curl -s --location --request DELETE 'https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON' \
        --header 'Content-Type: application/json' \
        --data "$INFO_PAYLOAD")
    
    handle_error "$res"

    echo "$res" | jq '.responsedata.dnsrecords'
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
    }" | jq -c)

    res=$(curl -s --location --request DELETE 'https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON' \
        --header 'Content-Type: application/json' \
        --data "$UPDATE_PAYLOAD")
    
    handle_error "$res"
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
    }" | jq -c)

    res=$(curl -s --location --request DELETE 'https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON' \
        --header 'Content-Type: application/json' \
        --data "$LOGOUT_PAYLOAD")
    
    handle_error "$res"
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
        length=$(echo "$records" | jq ". | length")
        log s "found $normal$length$blue records"

        change="false"

        for ((i=0; i<length; i++)); do
            log i "processing record $normal$i"

            type=$(echo "$records" | jq -r ".[$i].type")
            if [[ "$type" != "A" ]]; then
                log i "not an A record"
                continue
            fi

            hostname=$(echo "$records" | jq -r ".[$i].hostname")
            regex="(^|,)$hostname(,|$)"
            if [[ ! "$RECORDS" =~ $regex ]]; then
                log i "$normal$hostname$blue not in RECORDS"
                continue
            fi

            destination=$(echo "$records" | jq -r ".[$i].destination")
            if [[ "$destination" == "$ip" ]]; then
                log i "ip address unchanged"
                continue
            fi

            change="true"
            log i "changing destination of $normal$hostname$blue to $normal$ip"
            records=$(echo "$records" | jq -r ".[$i].destination|=\"$ip\"")
        done

        if [[ "$change" != "true" ]]; then
            log i "no changes were made on domain $normal$domain"
            continue
        fi

        log i "updating records for domain $normal$domain"
        set_records $sid $domain $(echo "$records" | jq -c)
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