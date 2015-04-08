package Rplus::Model::ChatMessage;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'chat_messages',

    columns => [
        id         => { type => 'serial', not_null => 1 },
        from       => { type => 'integer', not_null => 1 },
        message    => { type => 'varchar', length => 2044, not_null => 1 },
        add_date   => { type => 'timestamp with time zone', default => 'now()', not_null => 1 },
        to         => { type => 'integer' },
        read       => { type => 'integer', default => '0', not_null => 1 },
        attachment => { type => 'varchar', length => 2044 },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        user => {
            class       => 'Rplus::Model::User',
            key_columns => { from => 'id' },
        },
    ],
);

1;

