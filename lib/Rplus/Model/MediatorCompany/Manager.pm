package Rplus::Model::MediatorCompany::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::MediatorCompany;

sub object_class { 'Rplus::Model::MediatorCompany' }

__PACKAGE__->make_manager_methods('mediator_companies');

1;

