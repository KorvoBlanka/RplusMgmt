package Rplus::Model::MediatorCompany;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'mediator_companies',

    columns => [
        id             => { type => 'serial', not_null => 1 },
        name           => { type => 'varchar', length => 64, not_null => 1, remarks => 'Название' },
        add_date       => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        delete_date    => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
        account_id     => { type => 'integer' },
        hidden_for_aid => { type => 'array', default => '{}', not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    relationships => [
        mediator_realty => {
            class      => 'Rplus::Model::MediatorRealty',
            column_map => { id => 'mediator_company_id' },
            type       => 'one to many',
        },

        mediators => {
            class      => 'Rplus::Model::Mediator',
            column_map => { id => 'company_id' },
            type       => 'one to many',
        },

        realty => {
            class      => 'Rplus::Model::Realty',
            column_map => { id => 'mediator_company_id' },
            type       => 'one to many',
        },
    ],
);

1;

