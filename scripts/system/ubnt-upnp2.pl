#!/usr/bin/perl

use Getopt::Long;
use POSIX;
use File::Compare;

use lib '/opt/vyatta/share/perl5';
use Vyatta::Config;

use warnings;
use strict;


my $upnp_chain = 'MINIUPNPD';
my $config_file = '/opt/vyatta/etc/miniupnpd.conf';
my $pid_file = '/var/run/miniupnpd.pid';
my $uuid_file = '/config/user-data/uuid';
my $lease_file = '/var/log/upnp.leases';

sub flush_chains {
    system("sudo iptables -F $upnp_chain; sudo iptables -t nat -F $upnp_chain");
    system("sudo iptables -t nat -F $upnp_chain-POSTROUTING");
    system("sudo iptables -t mangle -F $upnp_chain");
}

sub restart_daemon {
    my $conf = shift;

    stop_daemon();
    my $cmd = "start-stop-daemon -q --start --exec \"/usr/sbin/miniupnpd\""
        . " -- -f $config_file -P $pid_file";
    system($cmd);
}

sub stop_daemon {
    my $cmd = "start-stop-daemon -q --stop --oknodo --pidfile $pid_file";
    system($cmd);
}

sub read_uuid {
    my $uuid;
    if (! -e $uuid_file) {
        system("sudo uuidgen -r > $uuid_file");
    }
    open(my $FILE, '<', $uuid_file) or die "Error: read $!";
    $uuid = <$FILE>;
    close($FILE);
    chomp $uuid;
    return $uuid;
}

sub change_iptables {
    my $wan = shift;

    my $cmd;
    $cmd = "sudo iptables -t mangle -R PREROUTING 1 -i $wan -j $upnp_chain";
    system($cmd);
    $cmd = "sudo iptables -t nat -R PREROUTING 1 -i $wan -j $upnp_chain";
    system($cmd);
    $cmd = "sudo iptables -t nat -R POSTROUTING 2 -o $wan "
        . "-j $upnp_chain-POSTROUTING";
    system($cmd);
    $cmd = "sudo iptables -t filter -R FORWARD 1 -i $wan ! -o $wan "
        . "-j $upnp_chain";
    system($cmd);
}

sub reset_iptables {
    my $cmd;
    $cmd = "sudo iptables -t mangle -R PREROUTING 1 -j $upnp_chain";
    system($cmd);
    $cmd = "sudo iptables -t nat -R PREROUTING 1 -j $upnp_chain";
    system($cmd);
    $cmd = "sudo iptables -t nat -R POSTROUTING 2 -j $upnp_chain-POSTROUTING";
    system($cmd);
    $cmd = "sudo iptables -t filter -R FORWARD 1 -j $upnp_chain";
    system($cmd);
}

sub validate_port {
    my ($rule, $ports) = @_;

    my ($start, $end) = (0, 65535);
    if ($ports =~ /(\d+)-(\d+)/) {
        my $start = $1;
        my $end = $2;
        if ($end < $start) {
            print "Error: port range start must be less than end for rule $rule\n";
            exit 1;
        }
    } elsif ($ports =~/(\d+)/) {
        $start = $1;
    }
    foreach my $i ($start, $end) {
        if ($i < 0 or $i > 65535) {
            print "Error: port range $i must be within 0-65535 for rule $rule\n";
            exit 1;
        }
    }
}

sub read_config {
    my $output .= "enable_upnp=yes\n";

    my $config = new Vyatta::Config;
    my $path = 'service upnp2';
    $config->setLevel($path);
    my $wan = $config->returnValue('wan');
    if (! defined $wan or $wan eq '') {
        print "Error: must define a WAN interface\n";
        exit 1;
    }
    my $owan = $config->returnOrigValue('wan');
    $owan = '' if ! defined $owan;
    if ($wan ne $owan) {
        change_iptables($wan);
    }

    my $natpmp = $config->returnValue('nat-pmp');
    if (!defined $natpmp or $natpmp eq '') {
        $natpmp = 'disable';
    }
    if ($natpmp eq 'disable') {
        $output .= "enable_natpmp=no\n";
    } else {
        $output .= "enable_natpmp=yes\n";
    }

    $output .= "ext_ifname=$wan\n";

    $config->setLevel("$path bit-rate");
    my $bitrate_up = $config->returnValue('up');
    $output .= "bitrate_up=$bitrate_up\n" if defined $bitrate_up;
    my $bitrate_down = $config->returnValue('down');
    $output .= "bitrate_down=$bitrate_down\n" if defined $bitrate_down;
    $config->setLevel($path);

    my @lans = $config->returnValues('listen-on');
    if (scalar(@lans) < 1) {
        print "Error: must define at least one listen-on interface\n";
        exit 1;
    }
    foreach my $lan (@lans) {
        $output .= "listening_ip=$lan\n";
    }
    my $port = $config->returnValue('port');
    if (defined $port) {
        $output .= "port=$port\n";
    }

    my $secure = $config->returnValue('secure-mode');
    if (!defined $secure or $secure eq '') {
        $secure = 'disable';
    }
    if ($secure eq 'disable') {
        $output .= "secure_mode=no\n";
    } else {
        $output .= "secure_mode=yes\n";
    }

    my $uuid = read_uuid();
    $output .= "uuid=$uuid\n";

    $output .= "manufacturer_name=Ubiquiti Networks, Inc.\n";
    $output .= "manufacturer_url=http=http://www.ubnt.com\n";

    my $plat = `/usr/sbin/ubnt-hal getBoardShortName`;
    $output .= "friendly_name=$plat\n";

    my $model = `/usr/sbin/ubnt-hal getBoardId`;
    $output .= "model_number=$model\n";

    my $serial = `/usr/sbin/ubnt-hal getBoardSerial`;
    $output .= "serial=$serial\n";

    $output .= "lease_file=$lease_file\n";

    $path .= " acl rule";
    $config->setLevel($path);
    my @rules = $config->listNodes();
    foreach my $rule (@rules) {
        $config->setLevel("$path $rule");
        my $action = $config->returnValue('action');
        if (!defined $action) {
            print "Error: must define an action for acl rule $rule\n";
            exit 1;
        }
        my $subnet = $config->returnValue('subnet');
        if (!defined $subnet) {
            print "Error: must define an subnet for acl rule $rule\n";
            exit 1;
        }
        my $eport = $config->returnValue('external-port');
        if (!defined $eport) {
            $eport = '1024-65535';
        }
        validate_port($rule, $eport);

        my $lport = $config->returnValue('local-port');
        if (!defined $lport) {
            $lport = '0-65535';
        }
        validate_port($rule, $lport);
        $output .= "$action $eport $subnet $lport\n";
    }

    return $output;
}

sub is_same_as_file {
    my ($file, $value) = @_;

    return if ! -e $file;

    my $mem_file = '';
    open my $MF, '+<', \$mem_file or die "couldn't open memfile $!\n";
    print $MF $value;
    seek($MF, 0, 0);

    my $rc = compare($file, $MF);
    return 1 if $rc == 0;
    return;
}

sub write_file {
    my ($file, $config) = @_;

    # Avoid unnecessary writes.  At boot the file will be the
    # regenerated with the same content.
    return if is_same_as_file($file, $config);

    open(my $fh, '>', $file) || die "Couldn't open $file - $!";
    print $fh $config;
    close $fh;
    return 1;
}

my ($update, $stop);

GetOptions(
    "update!"   => \$update,
    "stop!"     => \$stop,
);

if ($update) {
    flush_chains();
    my $output = read_config();
    write_file($config_file, $output);
	restart_daemon($config_file);
	exit 0;
}

if ($stop) {
    flush_chains();
    reset_iptables();
	stop_daemon();
    unlink $config_file;
	exit 0;
}

exit 1;

# end of file
