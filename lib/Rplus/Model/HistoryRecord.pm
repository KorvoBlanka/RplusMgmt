package Rplus::Model::HistoryRecord;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'history_records',

    columns => [
        id          => { type => 'serial', not_null => 1 },
        date        => { type => 'timestamp with time zone', default => 'now()', not_null => 1 },
        type        => { type => 'varchar', not_null => 1 },
        object_type => { type => 'varchar' },
        object_id   => { type => 'integer' },
        record      => { type => 'varchar' },
        user_id     => { type => 'integer' },
        metadata    => { type => 'scalar', default => '{}', not_null => 1 },
        account_id  => { type => 'integer' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,
);

1;

