package Rplus::Model::ClientColorTag;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'client_color_tags',

    columns => [
        id           => { type => 'integer', not_null => 1, sequence => 'color_tags_id_seq' },
        client_id    => { type => 'integer', not_null => 1 },
        user_id      => { type => 'integer', not_null => 1 },
        color_tag_id => { type => 'integer' },
    ],

    primary_key_columns => [ 'id' ],

    foreign_keys => [
        client => {
            class       => 'Rplus::Model::Client',
            key_columns => { client_id => 'id' },
        },
    ],
);

1;

