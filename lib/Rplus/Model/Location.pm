package Rplus::Model::Location;

use strict;

use base qw(Rplus::DB::Object);

__PACKAGE__->meta->setup(
    table   => 'locations',

    columns => [
        id           => { type => 'integer', not_null => 1, sequence => 'dict_locations_id_seq' },
        name         => { type => 'varchar', length => 32, not_null => 1 },
        city_guid    => { type => 'varchar', length => 64, not_null => 1 },
        phone_prefix => { type => 'varchar', length => 16, not_null => 1 },
        map_coords   => { type => 'scalar', default => '{}', not_null => 1 },
    ],

    primary_key_columns => [ 'id' ],

    relationships => [
        accounts => {
            class      => 'Rplus::Model::Account',
            column_map => { id => 'location_id' },
            type       => 'one to many',
        },
    ],
);

1;

