#! /usr/bin/perl -w
###################################################################
# Oreon is developped with GPL Licence 2.0 
#
# GPL License: http://www.gnu.org/licenses/gpl.txt
#
# Developped by : Julien Mathis - Romain Le Merlus 
#                 Christophe Coraboeuf
#
###################################################################
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
#    For information : contact@merethis.com
####################################################################
#
# Script init
#

use strict;
use Net::SNMP qw(:snmp);
use FindBin;
use lib "$FindBin::Bin";
use lib "/srv/nagios/libexec";
use utils qw($TIMEOUT %ERRORS &print_revision &support);
if (eval "require oreon" ) {
    use oreon qw(get_parameters);
    use vars qw(%oreon);
    %oreon=get_parameters();
} else {
	print "Unable to load oreon perl module\n";
    exit $ERRORS{'UNKNOWN'};
}
use vars qw($PROGNAME);
use Getopt::Long;
use vars qw($opt_V $opt_h $opt_v $opt_f $opt_C $opt_d $opt_n $opt_w $opt_c $opt_H $opt_s @test);

# Plugin var init

my ($hrStorageDescr, $hrStorageAllocationUnits, $hrStorageSize, $hrStorageUsed);
my ($AllocationUnits, $Size, $Used);
my ($tot, $used, $pourcent, $return_code);

$PROGNAME = "check_snmp_remote_storage";
sub print_help ();
sub print_usage ();

Getopt::Long::Configure('bundling');
GetOptions
    ("h"   => \$opt_h, "help"         => \$opt_h,
     "V"   => \$opt_V, "version"      => \$opt_V,
     "s"   => \$opt_s, "show"         => \$opt_s,
     "v=s" => \$opt_v, "snmp=s"       => \$opt_v,
     "C=s" => \$opt_C, "community=s"  => \$opt_C,
     "d=s" => \$opt_d, "disk=s"       => \$opt_d,
     "f"   => \$opt_f, "perfparse"         => \$opt_f,
     "n"   => \$opt_n, "name"         => \$opt_n,
     "w=s" => \$opt_w, "warning=s"    => \$opt_w,
     "c=s" => \$opt_c, "critical=s"   => \$opt_c,
     "H=s" => \$opt_H, "hostname=s"   => \$opt_H);


if ($opt_V) {
    print_revision($PROGNAME,'$Revision: 1.2 $');
    exit $ERRORS{'OK'};
}

if ($opt_h) {
	print_help();
	exit $ERRORS{'OK'};
}
if (!$opt_H) {
print_usage();
exit $ERRORS{'OK'};
}

if ($opt_n && !$opt_d) {
    print "Option -n (--name) need option -d (--disk)\n";
    exit $ERRORS{'UNKNOWN'};
}
my $snmp = "1";
if ($opt_v && $opt_v =~ /(\d)/) {
$snmp = $opt_v;
}

if (!$opt_C) {
$opt_C = "public";
}
if (!$opt_d) {
$opt_d = 2;
}
($opt_d) || ($opt_d = shift) || ($opt_d = 2);

my $partition = 0;
if ($opt_d =~ /([0-9]+)/ && !$opt_n){
    $partition = $1;
}
elsif (!$opt_n){
    print "Unknown -d number expected... or it doesn't exist, try another disk - number\n";
    exit $ERRORS{'UNKNOWN'};
}
my $critical = 95;
if ($opt_c && $opt_c =~ /^[0-9]+$/) {
    $critical = $opt_c;
}
my $warning = 90;
if ($opt_w && $opt_w =~ /^[0-9]+$/) {
    $warning = $opt_w;
}

if ($critical <= $warning){
    print "(--crit) must be superior to (--warn)";
    print_usage();
    exit $ERRORS{'OK'};
}


my $name = $0;
$name =~ s/\.pl.*//g;

# Plugin snmp requests

my $OID_hrStorageDescr =$oreon{MIB2}{HR_STORAGE_DESCR};
my $OID_hrStorageAllocationUnits =$oreon{MIB2}{HR_STORAGE_ALLOCATION_UNITS};
my $OID_hrStorageSize =$oreon{MIB2}{HR_STORAGE_SIZE};
my $OID_hrStorageUsed =$oreon{MIB2}{HR_STORAGE_USED};

# create a SNMP session
my ( $session, $error ) = Net::SNMP->session(-hostname  => $opt_H,-community => $opt_C, -version  => $snmp);
if ( !defined($session) ) {
    print("CRITICAL: SNMP Session : $error");
    exit $ERRORS{'CRITICAL'};
}

#getting partition using its name instead of its oid index
if ($opt_n) {
    my $result = $session->get_table(Baseoid => $OID_hrStorageDescr);
    if (!defined($result)) {
        printf("ERROR: hrStorageDescr Table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{'UNKNOWN'};
    }
    my $expr = "";
    if ($opt_d =~ m/^[A-Za-z]:/) {
		$opt_d =~ s/\\/\\\\/g;
		$expr = "^$opt_d";
    }elsif ($opt_d =~ m/^\//) {
		$expr = "$opt_d\$";
    }else {
		$expr = "$opt_d";
    }
    foreach my $key ( oid_lex_sort(keys %$result)) {
        if ($result->{$key} =~ m/$expr/) {
	   	 	my @oid_list = split (/\./,$key);
	   	 	$partition = pop (@oid_list) ;
		}
    }
}
if ($opt_s) {
    # Get description table
    my $result = $session->get_table(
        Baseoid => $OID_hrStorageDescr
    );

    if (!defined($result)) {
        printf("ERROR: hrStorageDescr Table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{'UNKNOWN'};
    }

    foreach my $key ( oid_lex_sort(keys %$result)) {
        my @oid_list = split (/\./,$key);
        my $index = pop (@oid_list) ;
        print "hrStorage $index :: $$result{$key}\n";
    }
	exit $ERRORS{'OK'};
}

my $result = $session->get_request(
                                   -varbindlist => [$OID_hrStorageDescr.".".$partition  ,
                                                    $OID_hrStorageAllocationUnits.".".$partition  ,
                                                    $OID_hrStorageSize.".".$partition,
                                                    $OID_hrStorageUsed.".".$partition
                                                    ]
                                   );
if (!defined($result)) {
    printf("ERROR:  %s", $session->error);
    if ($opt_n) { print(" - You must specify the disk name when option -n is used");}
    print ".\n";
    $session->close;
    exit $ERRORS{'UNKNOWN'};
}
$hrStorageDescr  =  $result->{$OID_hrStorageDescr.".".$partition };
$AllocationUnits  =  $result->{$OID_hrStorageAllocationUnits.".".$partition };
$Size  =  $result->{$OID_hrStorageSize.".".$partition };
$Used  =  $result->{$OID_hrStorageUsed.".".$partition };


# Plugins var treatment

if (!$Size){
    print "Disk CRITICAL - no output (-p number expected... it doesn't exist, try another disk - number\n";
    exit $ERRORS{'CRITICAL'};
}

if (($Size =~  /([0-9]+)/) && ($AllocationUnits =~ /([0-9]+)/)){
    if (!$Size){
        print "The number of the option -p is not a hard drive\n";
        exit $ERRORS{'CRITICAL'};
    }
    $tot = 1;
    $tot = $Size * $AllocationUnits;
    if (!$tot){$tot = 1;}
    $used = $Used * $AllocationUnits;
    $pourcent = ($used * 100) / $tot;

    if (length($pourcent) > 2){
        @test = split (/\./, $pourcent);
        $pourcent = $test[0];
    }
    my $lastTot = $tot;
    $tot = $tot / 1073741824;
    $Used = ($Used * $AllocationUnits) / 1073741824;
    
    # Plugin return code
    
    if ($pourcent >= $critical){
        print "Disk CRITICAL - ";
        $return_code = 2;
    } elsif ($pourcent >= $warning){
        print "Disk WARNING - ";
        $return_code = 1;
    } else {
        print "Disk OK - ";
        $return_code = 0;
    }

    if ($hrStorageDescr){
        print $hrStorageDescr . " TOTAL: ";
        printf("%.3f", $tot);
        print " Go USED: " . $pourcent . "% : ";
        printf("%.3f", $Used);
        print " Go";
        if ($opt_f){
        	my $size_o = $Used * 1073741824;
        	my $warn = $opt_w * $size_o;
        	my $crit = $opt_c * $size_o;
        	print "|size=".$lastTot."o used=".$size_o.";".$warn.";".$crit;
        }
        print "\n";
        exit $return_code;
    } else {
        print "TOTAL: ";
        printf("%.3f", $tot);
        print " Go USED: " . $pourcent . "% : ";
        printf("%.3f", $Used);
        print " Go\n";
        exit $return_code;
    }
} else {
    print "Disk CRITICAL - no output (-d number expected... it doesn't exist, try another disk - number\n";
    exit $ERRORS{'CRITICAL'};
}

sub print_usage () {
    print "\nUsage:\n";
    print "$PROGNAME\n";
    print "   -H (--hostname)   Hostname to query - (required)\n";
    print "   -C (--community)  SNMP read community (defaults to public,\n";
    print "                     used with SNMP v1 and v2c\n";
    print "   -v (--snmp_version)  1 for SNMP v1 (default)\n";
    print "                        2 for SNMP v2c\n";
    print "   -d (--disk)       Set the disk (number expected) ex: 1, 2,... (defaults to 2 )\n";
    print "   -n (--name)       Allows to use disk name with option -d instead of disk oid index\n";
    print "                     (ex: -d \"C:\" -n, -d \"E:\" -n, -d \"Swap Memory\" -n, -d \"Real Memory\" -n\n";
    print "                     (choose an unique expression for each disk)\n";
    print "   -s (--show)       Describes all disk (debug mode)\n";
    print "   -w (--warn)       Signal strength at which a warning message will be generated\n";
    print "                     (default 80)\n";
    print "   -c (--crit)       Signal strength at which a critical message will be generated\n";
    print "                     (default 95)\n";
    print "   -V (--version)    Plugin version\n";
    print "   -h (--help)       usage help\n";

}

sub print_help () {
    print "######################################################\n";
    print "#      Copyright (c) 2004-2007 Oreon-project         #\n";
	print "#      Bugs to http://www.oreon-project.org/         #\n";
	print "######################################################\n";
    print_usage();
    print "\n";
}
