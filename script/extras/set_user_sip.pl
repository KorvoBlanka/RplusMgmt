#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../../lib";

use Rplus::Model::User;
use Rplus::Model::User::Manager;

use JSON;

my $user = Rplus::Model::User->new(id => 4)->load;
my $metadata = decode_json($user->metadata);

$metadata->{'sip'} = {
    realm => '212.19.22.218',
    impi => '1006',
    impu => 'sip:1006@212.19.22.218',
    password => 'pass1006',
    display_name => '1006',
    websocket_proxy_url => 'ws://212.19.22.218:8088/asterisk/ws',
};

$user->metadata(encode_json($metadata));
$user->save;
