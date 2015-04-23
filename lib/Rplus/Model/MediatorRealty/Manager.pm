package Rplus::Model::MediatorRealty::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::MediatorRealty;

sub object_class { 'Rplus::Model::MediatorRealty' }

__PACKAGE__->make_manager_methods('mediator_realty');

1;

