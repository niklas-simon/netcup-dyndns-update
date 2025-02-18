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
- `RECORDS` - hostname-entries for the records that should be updated, separated by `,`, e.g. `@,mail`
- `INTERVAL` - interval for the script to run, in seconds

## Requirements

### Docker

The script can be run in Docker using the provided Dockerfile.

### Bare-Metal

For the script to run bare-metal, the following dependencies must be met:
- `curl` (Debian: `apt install curl`)
- `jq` (Debian: `apt install jq`)