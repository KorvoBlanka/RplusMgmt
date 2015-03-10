package Rplus::Model::Billing::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Billing;

sub object_class { 'Rplus::Model::Billing' }

__PACKAGE__->make_manager_methods('billing');

1;

