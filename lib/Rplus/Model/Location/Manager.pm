package Rplus::Model::Location::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Location;

sub object_class { 'Rplus::Model::Location' }

__PACKAGE__->make_manager_methods('locations');

1;

