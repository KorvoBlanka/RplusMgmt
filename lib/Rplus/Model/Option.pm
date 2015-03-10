package Rplus::Model::Option;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'options',

    columns => [
        id         => { type => 'serial', not_null => 1 },
        options    => { type => 'scalar', default => '{}', not_null => 1 },
        account_id => { type => 'integer', not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],

    unique_key => [ 'account_id' ],

    foreign_keys => [
        account => {
            class       => 'Rplus::Model::Account',
            key_columns => { account_id => 'id' },
            rel_type    => 'one to one',
        },
    ],
);

1;

