package Rplus::Model::AddressObject::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::AddressObject;

sub object_class { 'Rplus::Model::AddressObject' }

__PACKAGE__->make_manager_methods('address_objects');

1;

