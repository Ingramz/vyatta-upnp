#
# Module: Vyatta::Upnp.pm
# 
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Managed I.T.
# Portions created by Managed I.T. are Copyright (C) 2010 Managed I.T.
# All Rights Reserved.
# 
# Author: Kiall Mac Innes
# Date: May 2010
# Description: Common UPNP definitions/funcitions
# 
# **** End License ****
#
package Vyatta::Upnp;
use strict;
use warnings;

our @EXPORT = qw(
    start_daemon
    restart_daemon
    stop_daemon
    is_running
);
use base qw(Exporter);
use File::Basename;
use POSIX;

use Vyatta::Config;

my $daemon = '/usr/sbin/upnpd';
my $start_stop_daemon = '/sbin/start-stop-daemon';

sub is_running {
    my ($pid_file) = @_;

    if (-f $pid_file) {
        my $pid = `cat $pid_file`;
        $pid =~ s/\s+$//;  # chomp doesn't remove nl
        my $ps = `ps -p $pid -o comm=`;
        if (defined($ps) && $ps ne "") {
            return $pid;
        } 
    }
    return 0;
}

sub start_daemon {
    my ($inbound_intf, $outbound_intf) = @_;

    print "Starting upnpd instance for $inbound_intf ($outbound_intf)\n";
    my ($cmd, $rc);
    $cmd  = "$start_stop_daemon -b -m -p /var/run/upnpd-$inbound_intf.pid";
    $cmd .= " --start --quiet --exec $daemon -- ";
    $cmd .= " -f \"$outbound_intf\" \"$inbound_intf\"";
    $rc = system($cmd);
}

sub stop_daemon {
    my ($inbound_intf) = @_;
    my $pid_file = "/var/run/upnpd-$inbound_intf.pid";
    my $pid      = is_running($pid_file);
    if ($pid != 0) {
        print "Stopping upnpd instance for $inbound_intf\n";
        system("kill -INT $pid");
    }
}

sub restart_daemon {
    my ($inbound_intf, $outbound_intf) = @_;
    my $pid_file = "/var/run/upnpd-$inbound_intf.pid";
    my $pid      = is_running($pid_file);
    if ($pid != 0) {
        system("kill -INT $pid");
        print "Stopping upnpd instance for $inbound_intf ($outbound_intf)\n";
        sleep 5; # give the daemon a chance to properly shutdown
    } 
    start_daemon($inbound_intf, $outbound_intf);    
}

1;

