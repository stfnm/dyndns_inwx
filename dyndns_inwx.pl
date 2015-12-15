#!/usr/bin/perl

#
# Copyright (C) 2015  stfn <stfnmd@gmail.com>
# https://github.com/stfnm/dyndns_inwx
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;
use CGI;
use MIME::Base64;
use Data::Dumper;
use DomRobot::Lite;

################################################################################

my $API_URL = 'https://api.domrobot.com/xmlrpc/';
my $TOKEN = 'use some token';
my $CLIENT;

main();

################################################################################

sub inwx_login($$)
{
	my ($user, $pass) = @_;

	# Create XML RPC client
	$CLIENT = DomRobot::Lite->proxy($API_URL, cookie_jar => HTTP::Cookies->new(ignore_discard => 1));

	# Authenticate and get a session cookie
	my $response = $CLIENT->login($user, $pass);

	# Check if login was successful
	if ($response->result->{code} == 1000) {
		return 1;
	}

	return 0;
}

sub inwx_logout
{
	# End session
	$CLIENT->logout;
}

sub inwx_nameserverInfo($$$)
{
	my ($domain, $domain2, $domain_type) = @_;

	# Query nameserver info
	my $response = $CLIENT->call('nameserver.info', { domain => $domain2 });

	# Check if query was successful
	if ($response->result->{code} == 1000) {
		# Look for matching record
		for (my $i = 0; $response->result->{resData}->{record}->[$i]; ++$i) {
			my $name = $response->result->{resData}->{record}->[$i]->{name};
			my $id = $response->result->{resData}->{record}->[$i]->{id};
			my $type = $response->result->{resData}->{record}->[$i]->{type};

			if ($name eq $domain && $type eq $domain_type) {
				return $id;
			}
		}
	}

	return 0;
}

sub inwx_nameserverUpdateRecord($$)
{
	my ($id, $ip) = @_;

	# Update nameserver record
	my $response = $CLIENT->call('nameserver.updateRecord', { id => $id, content => $ip });

	# Check if update was successful
	if ($response->result->{code} == 1000) {
		return 1;
	}

	return 0;
}

sub main
{
	my $query = new CGI;
	print $query->header(-charset => 'UTF-8');

	# Get token URL parameter
	my $token = $query->param('token');

	# Check token and exit immediately if it doesn't match
	if ($TOKEN ne $token) {
		exit 0;
	}

	# Get the rest of the URL parameters
	my $domain = $query->param('domain'); # fqdn to update record
	my $domain2 = $query->param('domain2'); # second-level domain name
	my $username = $query->param('username'); # inwx user
	my $username64 = $query->param('username64'); # inwx user (base64 encoded)
	my $pass = $query->param('pass'); # inwx password
	my $pass64 = $query->param('pass64'); # inwx password (base64 encoded)
	my $ip = $query->param('ipaddr');
	my $ip6 = $query->param('ip6addr');

	# Decode base64 parameters
	if (!$username && $username64) {
		$username = decode_base64($username64);
	}
	if (!$pass && $pass64) {
		$pass = decode_base64($pass64);
	}

	# Login and update records
	if ($domain && $domain2 && $username && $pass && inwx_login($username, $pass)) {
		my ($id, $id6);

		# IPv4
		if ($ip) {
			$id = inwx_nameserverInfo($domain, $domain2, 'A');
			if ($id) {
				inwx_nameserverUpdateRecord($id, $ip);
				print "v4";
			}
		}

		# IPv6
		if ($ip6) {
			$id6 = inwx_nameserverInfo($domain, $domain2, 'AAAA');
			if ($id6) {
				inwx_nameserverUpdateRecord($id6, $ip6);
				print "v6";
			}
		}

		# We're done so we finally logout
		inwx_logout();
	}

	exit 0;
}
