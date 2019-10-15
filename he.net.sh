#!/bin/bash

if [ -n "$HE_USER" ] && [ -n "$HE_PASS" ]; then
  HE_COOKIE=$( \
    curl -L --silent --show-error -I "https://dns.he.net/" \
      | grep '^Set-Cookie:' \
      | grep -Eo 'CGISESSID=[a-z0-9]*')
  # Attempt login
  curl -L --silent --show-error --cookie "$HE_COOKIE" \
    --form "email=${HE_USER}" \
    --form "pass=${HE_PASS}" \
    "https://dns.he.net/" \
    > /dev/null
elif [ -n "$HE_SESSID" ]; then
  HE_COOKIE="CGISESSID=${HE_SESSID}"
else
  echo
    'No auth details provided. Please provide either session id (' \
    'through the $HE_SESSID environment variable) or user credentials' \
    '(through $HE_USER and $HE_PASS environement variables).' \
    1>&2
  exit 1
fi

function find_zone() {
  MATCHES=$(
    curl -L --silent --show-error --cookie "$HE_COOKIE" \
    "https://dns.he.net/" \
    | grep -Eo "delete_dom.*name=\"[^\"]+\" value=\"[0-9]+"
  )

  ZONE_IDS=$(echo "$MATCHES" | cut -d '"' -f 5)
  ZONE_NAMES=$(echo "$MATCHES" | cut -d '"' -f 3)

  STRIP_COUNTER=1

  while true; do
    ATTEMPTED_ZONE=$(echo "$DOMAIN" | cut -d . -f${STRIP_COUNTER}-)

    if [ -z "$ATTEMPTED_ZONE" ]; then
      exit
    fi

    REGEX="^$(echo "$ATTEMPTED_ZONE" | sed 's/\./\\./g')$"
    LINE_NUM=$(echo "$ZONE_NAMES" \
      | grep -n "$REGEX" \
      | cut -d : -f 1
    )

    if [ -n "$LINE_NUM" ]; then
      HE_ZONEID=$(echo "$ZONE_IDS" | sed "${LINE_NUM}q;d")
      break
    fi

    STRIP_COUNTER=$(expr $STRIP_COUNTER + 1)

  done
}

function get_dns_recordid() {
  DNS_RECORDID=$(
    curl -L --silent --show-error --cookie "$HE_COOKIE" \
      --form "hosted_dns_zoneid=$HE_ZONEID" \
      --form "menu=edit_zone" \
      --form "hosted_dns_editzone=" \
      "https://dns.he.net/" \
      | grep -B7 "$TOKEN_VALUE" \
      | sed -nre 's/.*dns_tr.* id="([^"]*)".*/\1/p'
  )
}

deploy_challenge() {
  DOMAIN="${1}"
  TOKEN_VALUE=${2}
  RECORD_NAME="_acme-challenge.$DOMAIN"
  find_zone
    curl -L --silent --show-error --cookie "$HE_COOKIE" \
    --form "account=" \
    --form "menu=edit_zone" \
    --form "Type=TXT" \
    --form "hosted_dns_zoneid=$HE_ZONEID" \
    --form "hosted_dns_recordid=" \
    --form "hosted_dns_editzone=1" \
    --form "Priority=" \
    --form "Name=$RECORD_NAME" \
    --form "Content=$TOKEN_VALUE" \
    --form "TTL=300" \
    --form "hosted_dns_editrecord=Submit" \
    "https://dns.he.net/" \
    > /dev/null
}

clean_challenge() {
  DOMAIN="${1}"
  TOKEN_VALUE="${2}"
  RECORD_NAME="_acme-challenge.$DOMAIN"
  find_zone
  get_dns_recordid
  curl -L --silent --show-error --cookie "$HE_COOKIE" \
    --form "menu=edit_zone" \
    --form "hosted_dns_zoneid=$HE_ZONEID" \
    --form "hosted_dns_recordid=${DNS_RECORDID}" \
    --form "hosted_dns_editzone=1" \
    --form "hosted_dns_delrecord=1" \
    --form "hosted_dns_delconfirm=delete" \
    --form "hosted_dns_editzone=1" \
    "https://dns.he.net/" \
    | grep '<div id="dns_status" onClick="hideThis(this);">Successfully removed record.</div>' \
    > /dev/null
  DELETE_OK=$?
  if [ $DELETE_OK -ne 0 ]; then
    echo \
      "Could not clean (remove) up the record. Please go to HE" \
      "administration interface and clean it by hand." \
      1>&2
  fi
}

startup_hook() {
  :
}

exit_hook() {
  :
}

case $1 in
'deploy_challenge')
    deploy_challenge "$2" "$4"
    ;;
'clean_challenge')
    clean_challenge "$2" "$4"
    ;;
esac
