#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../../lib";

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;

use JSON;

my $media = Rplus::Model::Media::Manager->get_objects(query => [type => 'export', code => 'farpost', delete_date => undef])->[0];
exit unless $media;

my $metadata = {
    params => {
        phones => '%agent.phone_num%',
    },

    landmark_types => {
        farpost => 'Farpost',
    },

    export_codes => {
        farpost => 'Farpost',
    },
};

$media->metadata(encode_json $metadata);
$media->save;
