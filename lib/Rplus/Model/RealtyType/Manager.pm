package Rplus::Model::RealtyType::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::RealtyType;

sub object_class { 'Rplus::Model::RealtyType' }

__PACKAGE__->make_manager_methods('realty_types');

1;

