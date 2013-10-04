#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../../lib";

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;

use JSON;

my $media = Rplus::Model::Media::Manager->get_objects(query => [type => 'export', code => 'vnh', delete_date => undef])->[0];
exit unless $media;

my $metadata = {
    params => {
        dict => {
            ap_schemes => {
                1 => 'стал.',
                2 => 'хрущ.',
                3 => 'улучш.',
                4 => 'нов.',
                5 => 'индив.',
                6 => 'общеж.',
            },

            balconies => {
                1 => '-',
                2 => 'б',
                3 => 'л',
                4 => 'л/б',
                5 => 'б',
                6 => 'л',
                7 => '2б',
                8 => '2л',
            },

            bathrooms => {
                1 => 'б/уд',
                3 => 'р.',
                4 => 'с.',
                5 => 'р.',
                6 => 'душ,т.',
                7 => 'т.',
                8 => 'с.',
            },

            conditions => {
                1 => 'п/стр.',
                2 => 'хор.',
                3 => 'хор.',
                4 => 'евро',
                5 => 'дизайн',
                6 => 'т.р.',
                7 => 'т.к.р.',
                9 => 'уд.',
                10 => 'хор.',
                11 => 'хор.',
                12 => 'отл.',
            },

            house_types => {
                1 => 'К',
                2 => 'К',
                3 => 'П',
                4 => 'Д',
                5 => 'Б',
                7 => 'К',
            },

            room_schemes => {
                3 => 'разд.',
                4 => 'смеж.',
                5 => 'икар.',
            },
        },

        realty_categories => {
            room => 'КОМ',
            apartment => 'КВ',
        },

        offer_type_code => 'sale',
        phones => '%agent.phone_num%',
        company => 'My Company',
    },

    landmark_types => {
        vnh_area => 'ВНХ Район',
        vnh_subarea => 'ВНХ Подрайон',
    },

    export_codes => {
        vnh_online => 'ВНХ Online',
        vnh => 'ВНХ',
    },
};

$media->metadata(encode_json $metadata);
$media->save;
