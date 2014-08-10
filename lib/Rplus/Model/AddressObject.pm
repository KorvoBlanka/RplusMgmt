package Rplus::Model::AddressObject;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'address_objects',

    columns => [
        id            => { type => 'serial', not_null => 1 },
        guid          => { type => 'varchar', length => 36, not_null => 1, remarks => 'Глобальный уникальный идентификатор адресного объекта' },
        aoid          => { type => 'varchar', length => 36, not_null => 1, remarks => 'Уникальный идентификатор записи (ФИАС)' },
        region_code   => { type => 'varchar', length => 2, not_null => 1, remarks => 'Код региона' },
        postal_code   => { type => 'varchar', length => 6, remarks => 'Почтовый индекс' },
        name          => { type => 'varchar', length => 120, not_null => 1, remarks => 'Формализованное наименование' },
        official_name => { type => 'varchar', length => 120, not_null => 1, remarks => 'Официальное наименование' },
        short_type    => { type => 'varchar', length => 10, not_null => 1, remarks => 'Краткое наименование типа объекта' },
        full_type     => { type => 'varchar', length => 50, not_null => 1, remarks => 'Полное наименование типа объекта' },
        level         => { type => 'integer', not_null => 1, remarks => 'Уровень адресного объекта' },
        parent_guid   => { type => 'varchar', length => 36, remarks => 'Идентификатор объекта родительского объекта' },
        prev_aoid     => { type => 'varchar', length => 36, remarks => 'Идентификатор записи связывания с предыдушей исторической записью (ФИАС)' },
        next_aoid     => { type => 'varchar', length => 36, remarks => 'Идентификатор записи связывания с последующей исторической записью (ФИАС)' },
        code          => { type => 'varchar', length => 17, remarks => 'Код адресного объекта одной строкой с признаком актуальности из КЛАДР 4.0' },
        plain_code    => { type => 'varchar', length => 15, remarks => 'Код адресного объекта из КЛАДР 4.0 одной строкой без признака актуальности (последних двух цифр)' },
        act_status    => { type => 'integer', not_null => 1, remarks => 'Статус актуальности адресного объекта ФИАС' },
        curr_status   => { type => 'integer', not_null => 1, remarks => 'Статус актуальности КЛАДР 4 (последние две цифры в коде)' },
        start_date    => { type => 'date', not_null => 1, remarks => 'Начало действия записи' },
        update_date   => { type => 'date', not_null => 1, remarks => 'Дата  внесения (обновления) записи' },
        end_date      => { type => 'date', remarks => 'Окончание действия записи' },
        expanded_name => { type => 'varchar', length => 255, remarks => 'Развернутое имя объекта' },
        keywords      => { type => 'varchar', length => 128, remarks => 'Ключевые слова' },
        metadata      => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
        fts           => { type => 'scalar', remarks => 'Данные для полнотекстового поиска (только имя)' },
        fts2          => { type => 'scalar', remarks => 'Данные для полнотекстового поиска (имя + тип)' },
        fts3          => { type => 'scalar', remarks => 'Данные для полнотекстового поиска (simple конфигурация)' },
    ],

    primary_key_columns => [ 'id' ],

    unique_key => [ 'aoid' ],

    relationships => [
        realty => {
            class      => 'Rplus::Model::Realty',
            column_map => { id => 'address_object_id' },
            type       => 'one to many',
        },
    ],
);

1;

