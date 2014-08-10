package Rplus::Model::DictBathroom::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::DictBathroom;

sub object_class { 'Rplus::Model::DictBathroom' }

__PACKAGE__->make_manager_methods('dict_bathrooms');

1;

