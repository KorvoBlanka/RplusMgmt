#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;

use JSON;

my $media = Rplus::Model::Media::Manager->get_objects(query => [type => 'export', code => 'present', delete_date => undef])->[0];
exit unless $media;

my $metadata = {
    params => {
        dict => {
            ap_schemes => {
                __field__ => 'ap_scheme_id',
                1 => 'стал.',
                2 => 'хрущ.',
                3 => 'улучш. план.',
                4 => 'нов. план.',
                5 => 'инд. план.',
                6 => 'общежитие',
            },

            balconies => {
                __field__ => 'balcony_id',
                1 => 'без балк.',
                2 => 'балк.',
                3 => 'лодж.',
                4 => 'балк. и лодж.',
                5 => 'б/з',
                6 => 'л/з',
                7 => '2 балк.',
                8 => '2 лодж.',
            },

            bathrooms => {
                __field__ => 'bathroom_id',
                1 => 'без удобств',
                3 => 'с/у разд.',
                4 => '2 смежн. с/у',
                5 => '2 разд. с/у',
                6 => 'душ + туалет',
                7 => 'туалет',
                8 => 'с/у совм.',
            },

            conditions => {
                __field__ => 'condition_id',
                1 => 'п/строит.',
                2 => 'соц. ремонт',
                3 => 'сделан ремонт',
                4 => 'евроремонт',
                5 => 'дизайнерский ремонт',
                6 => 'тр. ремонт',
                7 => 'т. к. р.',
                9 => 'удовл. сост.',
                10 => 'норм. сост.',
                11 => 'хор. сост.',
                12 => 'отл. сост.',
            },

            house_types => {
                __field__ => 'house_type_id',
                1 => 'кирп.',
                2 => 'монолит.',
                3 => 'пан.',
                4 => 'дерев.',
                5 => 'брус',
                6 => 'карк.-засыпн.',
                7 => 'монолит.-кирп.',
            },

            room_schemes => {
                __field__ => 'room_scheme_id',
                1 => 'студия',
                2 => 'кухня-гостиная',
                3 => 'комн. разд.',
                4 => 'комн. смежн.',
                5 => 'икарус',
                6 => 'комн. смежн.-разд.',
            },
        },

        offer_type_code => 'sale',
        add_description_words => 5,
        postfix => '%agent.phone_num%, 470-470',
    },

    landmark_types => {
        present => 'Презент',
    },
};

$media->metadata(encode_json $metadata);
$media->save;
