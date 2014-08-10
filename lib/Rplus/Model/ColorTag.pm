package Rplus::Model::ColorTag;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'color_tags',

    columns => [
        id           => { type => 'serial', not_null => 1 },
        realty_id    => { type => 'integer', not_null => 1 },
        user_id      => { type => 'integer', not_null => 1 },
        color_tag_id => { type => 'integer' },
    ],

    primary_key_columns => [ 'id' ],

    foreign_keys => [
        realty => {
            class       => 'Rplus::Model::Realty',
            key_columns => { realty_id => 'id' },
        },
    ],
);

1;

