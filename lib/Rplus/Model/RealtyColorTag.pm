package Rplus::Model::RealtyColorTag;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'realty_color_tags',

    columns => [
        realty_color_tag_id => { type => 'serial', not_null => 1 },
        tag1                => { type => 'array', default => '{}', not_null => 1 },
        tag2                => { type => 'array', default => '{}', not_null => 1 },
        tag3                => { type => 'array', default => '{}', not_null => 1 },
        tag4                => { type => 'array', default => '{}', not_null => 1 },
        tag5                => { type => 'array', default => '{}', not_null => 1 },
        tag6                => { type => 'array', default => '{}', not_null => 1 },
        realty_id           => { type => 'integer', not_null => 1 },
        tag0                => { type => 'array', default => '{}', not_null => 1 },
        tag7                => { type => 'array', default => '{}', not_null => 1 },
    ],

    primary_key_columns => [ 'realty_color_tag_id' ],

    unique_key => [ 'realty_id' ],

    foreign_keys => [
        realty => {
            class       => 'Rplus::Model::Realty',
            key_columns => { realty_id => 'id' },
            rel_type    => 'one to one',
        },
    ],
);

1;

