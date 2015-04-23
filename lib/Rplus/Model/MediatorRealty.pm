package Rplus::Model::MediatorRealty;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'mediator_realty',

    columns => [
        id                  => { type => 'serial', not_null => 1 },
        realty_id           => { type => 'integer', not_null => 1 },
        mediator_company_id => { type => 'integer', not_null => 1 },
        account_id          => { type => 'integer' },
    ],

    primary_key_columns => [ 'id' ],

    foreign_keys => [
        mediator_company => {
            class       => 'Rplus::Model::MediatorCompany',
            key_columns => { mediator_company_id => 'id' },
        },

        realty => {
            class       => 'Rplus::Model::Realty',
            key_columns => { realty_id => 'id' },
        },
    ],
);

1;

