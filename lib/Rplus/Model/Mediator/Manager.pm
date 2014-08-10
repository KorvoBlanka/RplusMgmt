package Rplus::Model::Mediator::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Mediator;

sub object_class { 'Rplus::Model::Mediator' }

__PACKAGE__->make_manager_methods('mediators');

1;

