package Rplus::Model::DictRoomScheme::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::DictRoomScheme;

sub object_class { 'Rplus::Model::DictRoomScheme' }

__PACKAGE__->make_manager_methods('dict_room_schemes');

1;

