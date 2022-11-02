#!/bin/bash
set -e
cd $(dirname "${BASH_SOURCE[0]}")

# The name to give the Wireguard network interface
IFACE=wgmesh0
# Prefix for IP addresses. This should be the first 3 octets with no trailing dot.
IPPREFIX="10.9.5"
# Netmask length for the mesh network. Values other than 24 probably won't work.
NETMASKLEN="24"
# The UDP port where the Wireguard service will listen on all hosts
LISTENPORT=55800
# If START_MESH is 1 then the mesh network will be started/updated when this script runs
START_MESH=1

INVENTORY_FILE=$(pwd)/inventory
CFGDIR=$(pwd)/cfg

PRIVKEY=/etc/wireguard/$IFACE-privkey
PUBKEY=/etc/wireguard/$IFACE-pubkey
WGCONF=/etc/wireguard/$IFACE.conf

function hostVars() {
  local _HOST=$1
  local _IH
  local _H
  local _IP
  local _U

  for _IH in $INVENTORY
  do
    IFS=: read _H _IP _U < <(echo $_IH)
    if [ "$_H" = "$_HOST" ]
    then
      if [ "$_IP" = "" ]
      then
        _IP=$_H
      fi
      if [ "$_U" = "" ]
      then
        _U=root
      fi
      echo "$_H $_IP $_U"
      break
    fi
  done
}

function _ssh() {
  local _HOST=$1
  shift
  local _CMD="$@"
  local _H
  local _U
  local _SUDO

  read _H _X _U < <(hostVars $_HOST)

  if [ "$_U" != "root" ]
  then
    _SUDO="sudo -i"
  fi

  ssh -l $_U $_H $_SUDO bash -c "'$_CMD'"
}

function installWireguard() {
  local _HOST=$1
  _ssh $_HOST "which wg >/dev/null || apt -y install wireguard"
}

function genOrGetKeys() {
  local _HOST=$1
  _ssh $_HOST "(test -e $PRIVKEY && test -e $PUBKEY) && cat $PUBKEY || (wg genkey | tee $PRIVKEY | wg pubkey | tee $PUBKEY)"
}

function getIp() {
  local _HOST=$1
  local _IPFILE="$CFGDIR/ip.$_HOST"

  if [ -f "$_IPFILE" ]
  then
    # IP for this host has already been allocated
    cat "$_IPFILE"
    return
  fi

  if [ $(ls $CFGDIR/ip.* 2>/dev/null | wc -l) -lt 1 ]
  then
    # No IPs have been allocated. Take IP 1
    echo "$IPPREFIX.1" | tee "$_IPFILE"
    return
  fi

  # Allocate a new IP for this host
  NUM=2
  while true
  do
    IP="$IPPREFIX.$NUM"
    if ! grep -q -E "^$IP$" $CFGDIR/ip.*
    then
      # IP not in use
      echo $IP | tee "$_IPFILE"
      return
    fi
    (( NUM++ ))
  done
}

function genConfig() {
  local _HOST=$1
  local TMPCFG=/etc/wireguard/$IFACE.tmp

  # Add server section for this host
  _ssh $_HOST "cat >$TMPCFG" <<EOF
[Interface]
PrivateKey = ##privkey##
ListenPort = $LISTENPORT
Address = $(cat $CFGDIR/ip.$_HOST)/$NETMASKLEN
EOF

  _ssh $_HOST "sed -i \"s/##privkey##/\$(cat $PRIVKEY)/\" $TMPCFG"

  # Add peer entries for other hosts
  for H in $HOSTS
  do
    if [ "$H" = "$_HOST" ]
    then
      continue
    fi

    read _H _WANIP _U < <(hostVars $H)
    _ssh $_HOST "cat >>$TMPCFG" <<EOF

# $H
[Peer]
PublicKey = $(cat $CFGDIR/pubkey.$H)
AllowedIPs = $(cat $CFGDIR/ip.$H)/32
Endpoint = $_WANIP:$LISTENPORT
EOF
  done
  _ssh $_HOST "mv -f $TMPCFG $WGCONF"
}

function parseInventory() {
  INVENTORY=$(sed 's/#.*$//; s/^\s*//; s/\s*$//; /^\s*$/d' <$INVENTORY_FILE)
  HOSTS=$(echo "$INVENTORY" | sed -r 's/:[^ ]*( |$)/ /g' | xargs)
}

function main() {
  mkdir -p "$CFGDIR"

  parseInventory

  # Generate keys and allocate IPs for all hosts
  for H in $HOSTS
  do
    installWireguard $H
    getIp $H >/dev/null
    genOrGetKeys $H >"$CFGDIR/pubkey.$H"
  done

  for HOST in $HOSTS
  do
    echo "Generating config on $HOST"
    genConfig $HOST

    if [ $START_MESH -eq 1 ]
    then
      # Start or update the mesh interface
      echo "Configuring interface on $HOST"
      _ssh $HOST "ifconfig $IFACE 2>&1 >/dev/null && wg syncconf $IFACE <(wg-quick strip $IFACE) || wg-quick up $IFACE"
    fi
  done
}

main
