package Rplus::Model::DictTaskType;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'dict_task_types',

    columns => [
        id          => { type => 'serial', not_null => 1 },
        name        => { type => 'varchar', not_null => 1 },
        add_date    => { type => 'timestamp with time zone', default => 'now()', not_null => 1 },
        delete_date => { type => 'timestamp with time zone' },
        category    => { type => 'varchar', default => 'both', not_null => 1, remarks => 'seller|buyer|both' },
        color       => { type => 'varchar' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    relationships => [
        tasks => {
            class      => 'Rplus::Model::Task',
            column_map => { id => 'task_type_id' },
            type       => 'one to many',
        },
    ],
);

1;

