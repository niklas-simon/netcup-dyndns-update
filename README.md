# Netcup DynDNS Update Script

This is a script that periodically updates your Netcup DNS A Records if your public IP has changed.  
The public IP is fetched by `curl ipinfo.io/ip`.  
This script uses Netcup's JSON-API, which is awful, but what can you do...

## Configuration

The script can be configured through the following environment variables:
- `API_KEY` - your Netcup API key
- `API_PASSWORD` - your Netcup API password
- `CUSTOMER_NUMBER` - your Netcup customer number
- `DOMAINS` - your Netcup domains that should be updated, separated by `,`
- `RECORDS` - hostname-entries for the records that should be updated, separated by `,` [default: `@,mail`]
- `INTERVAL` - interval for the script to run, in seconds [default: `120`]
- `LOG_LEVEL` - how much should be logged [default: `1`]
    - `0` - debugging information and above
    - `1` - informative logging and above
    - `2` - warnings and above
    - `3` - errors only
    - `4` - silent
- `DRY_RUN` - if `1`, don't actually update records. Only really useful with `LOG_LEVEL=0` [default: `0`]

## Requirements

### Docker

Image on Docker Hub: [gewuerznud3l/netcup-dyndns-update](https://hub.docker.com/repository/docker/gewuerznud3l/netcup-dyndns-update/general)
The image can be built using the provided Dockerfile.

### Bare-Metal

For the script to run bare-metal, the following dependencies must be met:
- `curl` (Debian: `apt install curl`)
- `jq` (Debian: `apt install jq`)