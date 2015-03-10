package Rplus::Model::Account;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'accounts',

    columns => [
        id          => { type => 'serial', not_null => 1 },
        email       => { type => 'varchar', length => 64, not_null => 1 },
        password    => { type => 'varchar', default => '', length => 64, not_null => 1 },
        balance     => { type => 'integer', default => '0', not_null => 1 },
        user_count  => { type => 'integer', default => 1, not_null => 1 },
        mode        => { type => 'varchar', default => 'all', length => 8, not_null => 1 },
        reg_code    => { type => 'varchar', length => 64 },
        reg_date    => { type => 'timestamp with time zone', default => 'now()', not_null => 1 },
        del_date    => { type => 'timestamp with time zone' },
        name        => { type => 'varchar', length => 16, not_null => 1 },
        location_id => { type => 'integer', default => 1, not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],

    unique_keys => [
        [ 'name' ],
        [ 'email' ],
    ],

    allow_inline_column_values => 1,

    foreign_keys => [
        location => {
            class       => 'Rplus::Model::Location',
            key_columns => { location_id => 'id' },
        },
    ],

    relationships => [
        option => {
            class                => 'Rplus::Model::Option',
            column_map           => { id => 'account_id' },
            type                 => 'one to one',
            with_column_triggers => '0',
        },

        users => {
            class      => 'Rplus::Model::User',
            column_map => { id => 'account_id' },
            type       => 'one to many',
        },
    ],
);

1;

