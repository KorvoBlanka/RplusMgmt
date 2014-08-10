package Rplus::Model::Landmark;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'landmarks',

    columns => [
        id          => { type => 'serial', not_null => 1 },
        type        => { type => 'varchar', length => 16, not_null => 1, remarks => 'Тип (landmark, sublandmark, etc)' },
        name        => { type => 'varchar', length => 64, not_null => 1, remarks => 'Название' },
        keywords    => { type => 'varchar', length => 128, remarks => 'Ключевые слова для поиска' },
        geodata     => { type => 'geometry', remarks => 'PostGIS данные' },
        metadata    => { type => 'scalar', default => '{}', not_null => 1, remarks => 'Метаданные' },
        add_date    => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время добавления' },
        change_date => { type => 'timestamp with time zone', default => 'now()', not_null => 1, remarks => 'Дата/время последнего изменения' },
        delete_date => { type => 'timestamp with time zone', remarks => 'Дата/время удаления' },
        geojson     => { type => 'scalar', not_null => 1, remarks => 'GeoJSON данные' },
        center      => { type => 'scalar', not_null => 1, remarks => 'Leaflet LatLng объект' },
        zoom        => { type => 'integer', not_null => 1, remarks => 'Zoom карты во время сохранения' },
        grp         => { type => 'varchar', length => 64, remarks => 'Группа, к которой принадлежит ориентир' },
        grp_pos     => { type => 'integer', remarks => 'Позиция внутри группы (NULL - макс)' },
    ],

    primary_key_columns => [ 'id' ],

    allow_inline_column_values => 1,

    relationships => [
        realty => {
            class      => 'Rplus::Model::Realty',
            column_map => { id => 'sublandmark_id' },
            type       => 'one to many',
        },
    ],
);

1;

