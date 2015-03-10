package Rplus::Model::AccountEvent;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'account_events',

    columns => [
        id      => { type => 'serial', not_null => 1 },
        date    => { type => 'timestamp with time zone', default => 'now()', not_null => 1 },
        account => { type => 'varchar', not_null => 1 },
        text    => { type => 'varchar', length => 255, not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,
);

1;

