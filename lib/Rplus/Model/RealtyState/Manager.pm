package Rplus::Model::RealtyState::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::RealtyState;

sub object_class { 'Rplus::Model::RealtyState' }

__PACKAGE__->make_manager_methods('realty_states');

1;

