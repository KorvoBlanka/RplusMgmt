package Rplus::Model::RuntimeParam;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => '_runtime_params',

    columns => [
        key   => { type => 'varchar', not_null => 1, remarks => 'Имя параметра (ключ)' },
        value => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Значение' },
        ts    => { type => 'timestamp with time zone', remarks => 'Некоторое значение времени' },
    ],

    primary_key_columns => [ 'key' ],
);

1;

