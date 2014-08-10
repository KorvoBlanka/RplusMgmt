package Rplus::Model::RealtyCategory;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'realty_categories',

    columns => [
        id       => { type => 'integer', not_null => 1 },
        name     => { type => 'varchar', length => 32, not_null => 1, remarks => 'Название' },
        code     => { type => 'varchar', length => 16, not_null => 1, remarks => 'Уникальный код' },
        keywords => { type => 'varchar', length => 128 },
        metadata => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
    ],

    primary_key_columns => [ 'id' ],

    unique_keys => [
        [ 'code' ],
        [ 'name' ],
    ],

    relationships => [
        realty_types => {
            class      => 'Rplus::Model::RealtyType',
            column_map => { code => 'category_code' },
            type       => 'one to many',
        },
    ],
);

1;

