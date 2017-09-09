package Rplus::Model::Mediator;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'mediators',

    columns => [
        id             => { type => 'serial', not_null => 1 },
        company_id     => { type => 'integer', not_null => 1, remarks => 'Компания' },
        name           => { type => 'varchar', length => 64, remarks => 'Кому принадлежит номер (Агент/Офис/и т.д.)' },
        phone_num      => { type => 'varchar', length => 32, not_null => 1, remarks => 'Номер телефона' },
        add_date       => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        delete_date    => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
        added_by       => { type => 'varchar', remarks => 'кто добавил посредника, (buffer - добавлено из буфера)' },
        last_seen_date => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'дата, когда последний раз был получена недвижимость с телефоном этого посредника' },
        hidden_for_aid => { type => 'array', default => '{}', not_null => 1 },
        account_id     => { type => 'integer' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    foreign_keys => [
        company => {
            class       => 'Rplus::Model::MediatorCompany',
            key_columns => { company_id => 'id' },
        },
    ],
);

1;

