package Rplus::Model::Variable;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'variables',

    columns => [
        id    => { type => 'serial', not_null => 1 },
        name  => { type => 'varchar', not_null => 1 },
        value => { type => 'varchar', not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],
);

1;

