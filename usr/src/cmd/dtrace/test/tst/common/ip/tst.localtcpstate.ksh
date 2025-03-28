#!/usr/bin/ksh
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#

#
# Copyright (c) 2010, Oracle and/or its affiliates. All rights reserved.
# Copyright 2025 Oxide computer Company
#

#
# Test tcp:::state-change and tcp:::{send,receive} by connecting to
# the local ssh service and sending a test message. This should result
# in a "Protocol mismatch" response and a close of the connection.
# A number of state transition events along with tcp fusion send and
# receive events for the message should result.
#
# This may fail due to:
#
# 1. A change to the ip stack breaking expected probe behavior,
#    which is the reason we are testing.
# 2. The lo0 interface missing or not up.
# 3. The local ssh service is not online.
# 4. An unlikely race causes the unlocked global send/receive
#    variables to be corrupted.
#
# This test performs a TCP connection to the ssh service (port 22) and
# checks that at least the following packet counts were traced:
#
# 3 x ip:::send (2 during the TCP handshake, then a FIN)
# 4 x tcp:::send (2 during the TCP handshake, 1 message then a FIN)
# 2 x ip:::receive (1 during the TCP handshake, then the FIN ACK)
# 3 x tcp:::receive (1 during the TCP handshake, 1 message then the FIN ACK)
#
# The actual ip count tested is 5 each way, since we are tracing both
# source and destination events.  The actual tcp count tested is 7
# each way, since the TCP fusion send/receive events will not reach IP.
#
# For this test to work, we are assuming that the TCP handshake and
# TCP close will enter the IP code path and not use tcp fusion.
#

if (( $# != 1 )); then
	print -u2 "expected one argument: <dtrace-path>"
	exit 2
fi

dtrace=$1
local=127.0.0.1
tcpport=12345

nc -l $local $tcpport >/dev/null &
child=$!

$dtrace -c "./msnc.exe $local $tcpport" -qs /dev/stdin <<EODTRACE
BEGIN
{
	ipsend = tcpsend = ipreceive = tcpreceive = 0;
	connreq = connest = connaccept = 0;
}

ip:::send
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local" &&
    args[4]->ipv4_protocol == IPPROTO_TCP/
{
	ipsend++;
}

tcp:::send
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local" &&
 (args[4]->tcp_sport == $tcpport || args[4]->tcp_dport == $tcpport)/
{
	tcpsend++;
}

ip:::receive
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local" &&
    args[4]->ipv4_protocol == IPPROTO_TCP/
{
	ipreceive++;
}

tcp:::receive
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local" &&
 (args[4]->tcp_sport == $tcpport || args[4]->tcp_dport == $tcpport)/
{
	tcpreceive++;
}

tcp:::state-change
{
	state_event[args[3]->tcps_state]++;
}

tcp:::connect-request
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local" &&
 args[4]->tcp_dport == $tcpport/
{
	connreq++;
}

tcp:::connect-established
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local" &&
 args[4]->tcp_sport == $tcpport/
{
	connest++;
}

tcp:::accept-established
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local" &&
 args[4]->tcp_dport == $tcpport/
{
	connaccept++;
}

END
{
	printf("Minimum TCP events seen\n\n");
	printf("ip:::send - %s\n", ipsend >= 5 ? "yes" : "no");
	printf("ip:::receive - %s\n", ipreceive >= 5 ? "yes" : "no");
	printf("tcp:::send - %s\n", tcpsend >= 7 ? "yes" : "no");
	printf("tcp:::receive - %s\n", tcpreceive >= 7 ? "yes" : "no");
	printf("tcp:::state-change to syn-sent - %s\n",
	    state_event[TCP_STATE_SYN_SENT] >=1 ? "yes" : "no");
	printf("tcp:::state-change to syn-received - %s\n",
	    state_event[TCP_STATE_SYN_RECEIVED] >=1 ? "yes" : "no");
	printf("tcp:::state-change to established - %s\n",
	    state_event[TCP_STATE_ESTABLISHED] >= 2 ? "yes" : "no");
	printf("tcp:::state-change to fin-wait-1 - %s\n",
	    state_event[TCP_STATE_FIN_WAIT_1] >= 1 ? "yes" : "no");
	printf("tcp:::state-change to close-wait - %s\n",
	    state_event[TCP_STATE_CLOSE_WAIT] >= 1 ? "yes" : "no");
	printf("tcp:::state-change to fin-wait-2 - %s\n",
	    state_event[TCP_STATE_FIN_WAIT_2] >= 1 ? "yes" : "no");
	printf("tcp:::state-change to last-ack - %s\n",
	    state_event[TCP_STATE_LAST_ACK] >= 1 ? "yes" : "no");
	printf("tcp:::state-change to time-wait - %s\n",
	    state_event[TCP_STATE_TIME_WAIT] >= 1 ? "yes" : "no");
	printf("tcp:::connect-request - %s\n",
	    connreq >=1 ? "yes" : "no");
	printf("tcp:::connect-established - %s\n",
	    connest >=1 ? "yes" : "no");
	printf("tcp:::accept-established - %s\n",
	    connaccept >=1 ? "yes" : "no");
}
EODTRACE

status=$?

exit $status
