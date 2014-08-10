package Rplus::Model::RealtyOfferType;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'realty_offer_types',

    columns => [
        id       => { type => 'integer', not_null => 1 },
        name     => { type => 'varchar', length => 32, not_null => 1, remarks => 'Название' },
        code     => { type => 'varchar', length => 16, not_null => 1, remarks => 'Код' },
        keywords => { type => 'varchar', length => 128, remarks => 'Ключевые слова' },
        metadata => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
    ],

    primary_key_columns => [ 'id' ],

    unique_keys => [
        [ 'code' ],
        [ 'name' ],
    ],

    relationships => [
        realty => {
            class      => 'Rplus::Model::Realty',
            column_map => { code => 'offer_type_code' },
            type       => 'one to many',
        },

        subscriptions => {
            class      => 'Rplus::Model::Subscription',
            column_map => { code => 'offer_type_code' },
            type       => 'one to many',
        },
    ],
);

1;

