package Rplus::Model::Task;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'tasks',

    columns => [
        id                => { type => 'serial', not_null => 1 },
        task_type_id      => { type => 'integer', not_null => 1 },
        creator_user_id   => { type => 'integer', not_null => 1 },
        assigned_user_id  => { type => 'integer' },
        add_date          => { type => 'timestamp with time zone', default => 'now()', not_null => 1 },
        remind_date       => { type => 'timestamp with time zone' },
        start_date        => { type => 'timestamp with time zone', not_null => 1 },
        description       => { type => 'varchar' },
        metadata          => { type => 'scalar', default => '{}', not_null => 1 },
        delete_date       => { type => 'timestamp with time zone' },
        status            => { type => 'varchar', default => 'new', not_null => 1 },
        change_date       => { type => 'timestamp with time zone', default => 'now()', not_null => 1 },
        chaged_by_user_id => { type => 'integer' },
        client_id         => { type => 'integer' },
        realty_id         => { type => 'integer' },
        google_id         => { type => 'varchar' },
        end_date          => { type => 'timestamp with time zone' },
        summary           => { type => 'varchar' },
        completion_date   => { type => 'timestamp with time zone' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        assigned_user => {
            class       => 'Rplus::Model::User',
            key_columns => { assigned_user_id => 'id' },
        },

        creator_user => {
            class       => 'Rplus::Model::User',
            key_columns => { creator_user_id => 'id' },
        },

        task_type => {
            class       => 'Rplus::Model::DictTaskType',
            key_columns => { task_type_id => 'id' },
        },
    ],
);

1;

