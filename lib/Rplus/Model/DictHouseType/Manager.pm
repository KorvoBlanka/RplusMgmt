package Rplus::Model::DictHouseType::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::DictHouseType;

sub object_class { 'Rplus::Model::DictHouseType' }

__PACKAGE__->make_manager_methods('dict_house_types');

1;

